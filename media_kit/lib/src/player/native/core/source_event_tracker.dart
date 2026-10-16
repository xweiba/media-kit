import 'dart:async';
import 'dart:ffi';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/src/models/playback_source_event.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;

/// Correlates native mpv file events with the source token supplied to open.
///
/// The token-to-entry mapping is installed before playlist-pos can start the
/// media. Native hooks drain observed properties at file boundaries. Events
/// are snapshotted here, at native ingress, before any asynchronous handler
/// work or broadcast-stream delivery can delay them.
final class SourceEventTracker {
  SourceEventTracker(this.mpv, this.getContext);

  final generated.MPV mpv;
  final Pointer<generated.mpv_handle> Function() getContext;

  Pointer<generated.mpv_handle> get ctx => getContext();
  late final bool _supportsEntryIds =
      mpv.mpv_client_api_version() >= ((1 << 16) | 108);

  final StreamController<PlaybackSourceEvent> _controller =
      StreamController<PlaybackSourceEvent>.broadcast();
  final Map<int, _SourceEntry> _entries = {};
  final Map<int, int> _attempts = {};
  final Set<int> _revokedEntryIds = {};
  _SourceEntry? _active;
  _SourceEntry? _pending;
  Object? _nextSource;
  bool _awaitingFirstFrame = false;
  bool _suppressProperties = false;
  bool _valid = true;
  bool _startFenceSeen = false;
  bool? _paused;

  Stream<PlaybackSourceEvent> get stream => _controller.stream;
  bool get supportsEntryIds => _supportsEntryIds;

  bool containsSource(Object source) =>
      _entries.values.any((entry) => identical(entry.source, source));

  /// Associates one native playlist entry with the caller's exact token.
  void register(int playlistEntryId, Object source) {
    _revokedEntryIds.remove(playlistEntryId);
    _entries.removeWhere((id, entry) {
      if (id == _active?.playlistEntryId || id == _pending?.playlistEntryId) {
        return false;
      }
      if (!entry.started) {
        _emit(
          entry,
          PlaybackSourceEventKind.invalidated,
          reason: 'replaced before the native file start event',
        );
      }
      _attempts.remove(id);
      return true;
    });
    _entries[playlistEntryId] = _SourceEntry(playlistEntryId, source);
    _nextSource = source;
    _valid = true;
  }

  /// Revokes attribution after a source open fails after registration.
  ///
  /// A playlist entry can survive a failed follow-up property write. Remove
  /// its mapping so any delayed native events fail closed instead of inheriting
  /// the caller's token.
  void invalidateSource(Object source, {required String reason}) {
    final invalidated = _entries.entries
        .where((entry) => identical(entry.value.source, source))
        .toList(growable: false);
    for (final entry in invalidated) {
      final tracked = entry.value;
      _emit(
        tracked,
        PlaybackSourceEventKind.invalidated,
        reason: reason,
      );
      _entries.remove(entry.key);
      _attempts.remove(entry.key);
      _revokedEntryIds.add(entry.key);
      if (_active == tracked) {
        _active = null;
        _awaitingFirstFrame = false;
        _suppressProperties = true;
      }
      if (_pending == tracked) _pending = null;
    }
    if (identical(_nextSource, source)) _nextSource = null;
  }

  /// Fails closed when a source open mutates the native playlist but its exact
  /// entry cannot be identified or finalized.
  void invalidateForSourceOpenFailure(String reason) {
    _invalidateAll(reason);
    _nextSource = null;
  }

  /// Marks a normal, untagged open so its next native start retires attribution.
  void expectUnattributedOpen() {
    _nextSource = null;
    _entries.removeWhere((id, entry) {
      if (id == _active?.playlistEntryId || id == _pending?.playlistEntryId) {
        return false;
      }
      if (!entry.started) {
        _emit(
          entry,
          PlaybackSourceEventKind.invalidated,
          reason: 'replaced before the native file start event',
        );
      }
      _attempts.remove(id);
      return true;
    });
  }

  /// Handles provenance-bearing events synchronously before the legacy handler.
  ///
  /// Returns true only for hooks consumed here; all other hooks continue
  /// through the existing media-kit hook handling and are continued there.
  bool handle(Pointer<generated.mpv_event> event) {
    final id = event.ref.event_id;
    if (id == generated.mpv_event_id.MPV_EVENT_QUEUE_OVERFLOW) {
      _invalidateAll('native event queue overflow');
      return false;
    }

    if (id == generated.mpv_event_id.MPV_EVENT_HOOK) {
      final hook = event.ref.data.cast<generated.mpv_event_hook>().ref;
      final name = hook.name.cast<Utf8>().toDartString();
      if (name == 'on_before_start_file') {
        _beforeStart();
        mpv.mpv_hook_continue(ctx, hook.id);
        return true;
      }
      if (name == 'on_after_end_file') {
        _active = null;
        _pending = null;
        _awaitingFirstFrame = false;
        _suppressProperties = true;
        mpv.mpv_hook_continue(ctx, hook.id);
        return true;
      }
      if (name == 'on_load') {
        _active = _pending;
        _pending = null;
        _awaitingFirstFrame = _active != null;
        _suppressProperties = false;
        if (_active case final entry?) {
          final paused = _readFlag('pause');
          if (paused != null) {
            _paused = paused;
            _emit(
              entry,
              PlaybackSourceEventKind.playing,
              playing: !paused,
            );
          }
        }
      } else if (name == 'on_unload') {
        _suppressProperties = true;
      }
      return false;
    }

    if (!_valid) return false;

    if (id == generated.mpv_event_id.MPV_EVENT_START_FILE) {
      if (_entries.isEmpty) return false;
      if (!_supportsEntryIds) {
        _invalidateAll('libmpv does not expose playlist entry IDs');
        return false;
      }
      final entryId = event.ref.data
          .cast<generated.mpv_event_start_file>()
          .ref
          .playlist_entry_id;
      final entry = _entries[entryId];
      if (entry == null && _revokedEntryIds.contains(entryId)) return false;
      if (entry == null || !_startFenceSeen) {
        _invalidateAll(
          entry == null
              ? 'start event had an unknown playlist entry ID'
              : 'native start hook fence was not observed',
        );
        return false;
      }
      _startFenceSeen = false;
      entry.started = true;
      entry.attempt = (_attempts[entryId] ?? 0) + 1;
      _attempts[entryId] = entry.attempt;
      _pending = entry;
      _awaitingFirstFrame = false;
      _emit(entry, PlaybackSourceEventKind.start);
      return false;
    }

    if (id == generated.mpv_event_id.MPV_EVENT_END_FILE) {
      if (_entries.isEmpty) return false;
      if (!_supportsEntryIds) {
        _invalidateAll('libmpv does not expose playlist entry IDs');
        return false;
      }
      final end = event.ref.data.cast<generated.mpv_event_end_file>().ref;
      final entry = _entries[end.playlist_entry_id];
      if (entry == null || _revokedEntryIds.contains(end.playlist_entry_id)) {
        return false;
      }
      final reason = _endReason(end.reason);
      _emit(
        entry,
        PlaybackSourceEventKind.ended,
        reason: reason,
      );
      if (end.reason ==
              generated.mpv_end_file_reason.MPV_END_FILE_REASON_ERROR &&
          end.error < 0) {
        final error =
            mpv.mpv_error_string(end.error).cast<Utf8>().toDartString();
        _emit(
          entry,
          PlaybackSourceEventKind.error,
          errorCode: end.error,
          reason: error,
        );
      }
      if (end.reason ==
          generated.mpv_end_file_reason.MPV_END_FILE_REASON_REDIRECT) {
        _emit(
          entry,
          PlaybackSourceEventKind.invalidated,
          reason: 'media redirected to playlist entries without source mapping',
        );
        _entries.remove(end.playlist_entry_id);
        if (_active == entry) _active = null;
        if (_pending == entry) _pending = null;
      }
      return false;
    }

    if (id == generated.mpv_event_id.MPV_EVENT_PLAYBACK_RESTART &&
        _awaitingFirstFrame &&
        _active != null) {
      _awaitingFirstFrame = false;
      _emit(_active!, PlaybackSourceEventKind.firstFrame);
      return false;
    }

    if (id == generated.mpv_event_id.MPV_EVENT_PROPERTY_CHANGE) {
      readProperty(event.ref.data.cast<generated.mpv_event_property>());
    }
    return false;
  }

  void _beforeStart() {
    _startFenceSeen = true;
    if (_active != null && !identical(_active!.source, _nextSource)) {
      _emit(
        _active!,
        PlaybackSourceEventKind.invalidated,
        reason: 'native playback changed outside this source open',
      );
    }
    _active = null;
    _pending = null;
    _awaitingFirstFrame = false;
    _paused = null;
    _suppressProperties = true;
  }

  void readProperty(Pointer<generated.mpv_event_property> property) {
    if (!_valid || _suppressProperties || _active == null) return;
    final name = property.ref.name.cast<Utf8>().toDartString();
    final entry = _active!;
    if (property.ref.format == generated.mpv_format.MPV_FORMAT_DOUBLE &&
        (name == 'time-pos' || name == 'duration') &&
        property.ref.data != nullptr) {
      final duration = Duration(
        microseconds: (property.ref.data.cast<Double>().value * 1e6).round(),
      );
      _emit(
        entry,
        name == 'time-pos'
            ? PlaybackSourceEventKind.position
            : PlaybackSourceEventKind.duration,
        duration: duration,
      );
    } else if (name == 'pause' &&
        property.ref.format == generated.mpv_format.MPV_FORMAT_FLAG &&
        property.ref.data != nullptr) {
      _paused = property.ref.data.cast<Int8>().value != 0;
      _emit(
        entry,
        PlaybackSourceEventKind.playing,
        playing: !_paused!,
      );
    } else if (name == 'core-idle' &&
        property.ref.format == generated.mpv_format.MPV_FORMAT_FLAG &&
        property.ref.data != nullptr) {
      final idle = property.ref.data.cast<Int8>().value != 0;
      if (idle && _paused == true) return;
      _emit(
        entry,
        PlaybackSourceEventKind.buffering,
        buffering: idle,
      );
    } else if (name == 'paused-for-cache' &&
        property.ref.format == generated.mpv_format.MPV_FORMAT_FLAG &&
        property.ref.data != nullptr) {
      _emit(
        entry,
        PlaybackSourceEventKind.buffering,
        buffering: property.ref.data.cast<Int8>().value != 0,
      );
    } else if (name == 'cache-buffering-state' &&
        property.ref.format == generated.mpv_format.MPV_FORMAT_DOUBLE &&
        property.ref.data != nullptr) {
      final percentage = property.ref.data.cast<Double>().value;
      _emit(
        entry,
        PlaybackSourceEventKind.bufferingPercentage,
        percentage: percentage.clamp(0.0, 100.0),
      );
    } else if (name == 'eof-reached' &&
        property.ref.format == generated.mpv_format.MPV_FORMAT_FLAG &&
        property.ref.data != nullptr) {
      _emit(
        entry,
        PlaybackSourceEventKind.completed,
        completed: property.ref.data.cast<Int8>().value != 0,
      );
    }
  }

  void _invalidateAll(String reason) {
    final emitted = <Object>{};
    for (final entry in _entries.values) {
      if (emitted.add(entry.source)) {
        _emit(entry, PlaybackSourceEventKind.invalidated, reason: reason);
      }
    }
    _entries.clear();
    _active = null;
    _pending = null;
    _awaitingFirstFrame = false;
    _suppressProperties = true;
    _valid = false;
  }

  void _emit(
    _SourceEntry entry,
    PlaybackSourceEventKind kind, {
    Duration? duration,
    bool? playing,
    bool? buffering,
    double? percentage,
    bool? completed,
    int? errorCode,
    String? reason,
  }) {
    if (!_controller.isClosed) {
      _controller.add(
        PlaybackSourceEvent(
          source: entry.source,
          playlistEntryId: entry.playlistEntryId,
          attempt: entry.attempt,
          kind: kind,
          duration: duration,
          playing: playing,
          buffering: buffering,
          percentage: percentage,
          completed: completed,
          errorCode: errorCode,
          reason: reason,
        ),
      );
    }
  }

  String _endReason(int reason) => switch (reason) {
        generated.mpv_end_file_reason.MPV_END_FILE_REASON_EOF => 'eof',
        generated.mpv_end_file_reason.MPV_END_FILE_REASON_STOP => 'stop',
        generated.mpv_end_file_reason.MPV_END_FILE_REASON_QUIT => 'quit',
        generated.mpv_end_file_reason.MPV_END_FILE_REASON_ERROR => 'error',
        generated.mpv_end_file_reason.MPV_END_FILE_REASON_REDIRECT =>
          'redirect',
        _ => 'unknown:$reason',
      };

  bool? _readFlag(String name) {
    final property = name.toNativeUtf8();
    final value = calloc<Int8>();
    try {
      final result = mpv.mpv_get_property(
        ctx,
        property.cast(),
        generated.mpv_format.MPV_FORMAT_FLAG,
        value.cast(),
      );
      return result < 0 ? null : value.value != 0;
    } finally {
      calloc.free(property);
      calloc.free(value);
    }
  }

  Future<void> close() async {
    _entries.clear();
    _attempts.clear();
    _revokedEntryIds.clear();
    _active = null;
    _pending = null;
    _valid = false;
    await _controller.close();
  }
}

final class _SourceEntry {
  _SourceEntry(this.playlistEntryId, this.source);

  final int playlistEntryId;
  final Object source;
  int attempt = 0;
  bool started = false;
}
