@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/src/player/native/core/source_event_tracker.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late Media media;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('media-kit-source-');
    addTearDown(() => directory.delete(recursive: true));
    MediaKit.ensureInitialized();
    NativePlayer.test = true;
    final file = File('${directory.path}/silence.wav');
    const dataLength = 4 * 8000 * 2;
    final bytes = ByteData(44 + dataLength);
    void text(int offset, String value) {
      bytes.buffer
          .asUint8List()
          .setRange(offset, offset + value.length, ascii.encode(value));
    }

    text(0, 'RIFF');
    bytes.setUint32(4, 36 + dataLength, Endian.little);
    text(8, 'WAVEfmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, 8000, Endian.little);
    bytes.setUint32(28, 16000, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    text(36, 'data');
    bytes.setUint32(40, dataLength, Endian.little);
    await file.writeAsBytes(bytes.buffer.asUint8List());
    media = Media(file.path);
  });

  tearDownAll(() {
    NativePlayer.test = false;
  });

  test('source events retain entry identity across delayed delivery and reopen',
      () async {
    final player = Player();
    final native = player.platform! as NativePlayer;
    final events = <PlaybackSourceEvent>[];
    final sourceA = Object();
    final sourceB = Object();
    final sourceBDelivered = Completer<void>();
    final subscription = player.sourceEvents.listen((event) {
      events.add(event);
      if (identical(event.source, sourceB) &&
          event.kind == PlaybackSourceEventKind.firstFrame &&
          !sourceBDelivered.isCompleted) {
        sourceBDelivered.complete();
      }
    });
    addTearDown(() async {
      await subscription.cancel();
      await player.dispose();
    });
    expect(player.supportsSourceEvents, isTrue);

    final firstFrameA = player.sourceEvents.firstWhere((e) =>
        identical(e.source, sourceA) &&
        e.kind == PlaybackSourceEventKind.firstFrame);
    await player.open(media, source: sourceA);
    await firstFrameA.timeout(const Duration(seconds: 5));
    final entryA = events
        .firstWhere((e) =>
            identical(e.source, sourceA) &&
            e.kind == PlaybackSourceEventKind.start)
        .playlistEntryId!;

    subscription.pause();
    final advanced = player.stream.position.firstWhere(
      (position) => position > const Duration(milliseconds: 200),
    );
    await advanced.timeout(const Duration(seconds: 5));

    final firstFrameB = player.sourceEvents.firstWhere((e) =>
        identical(e.source, sourceB) &&
        e.kind == PlaybackSourceEventKind.firstFrame);
    await player.open(media, source: sourceB);
    await firstFrameB.timeout(const Duration(seconds: 5));
    subscription.resume();
    await sourceBDelivered.future.timeout(const Duration(seconds: 5));

    final entryB = events
        .firstWhere((e) =>
            identical(e.source, sourceB) &&
            e.kind == PlaybackSourceEventKind.start)
        .playlistEntryId!;
    expect(entryB, isNot(entryA),
        reason: 'Reopening the same URI receives a new mpv entry ID.');
    expect(
      events.where((e) => e.kind == PlaybackSourceEventKind.position),
      isNotEmpty,
    );
    for (final event in events) {
      if (identical(event.source, sourceA)) {
        expect(event.playlistEntryId, entryA);
      } else if (identical(event.source, sourceB)) {
        expect(event.playlistEntryId, entryB);
      } else {
        fail('An event was labeled with an unknown source token.');
      }
    }

    final beforeRejectedOpen = player.state.playlist.medias.single.uri;
    await expectLater(
      player.open(media, source: sourceB),
      throwsArgumentError,
    );
    await expectLater(
      player.open(Playlist([media]), source: Object()),
      throwsArgumentError,
    );
    expect(player.state.playlist.medias.single.uri, beforeRejectedOpen);
    expect(native.supportsSourceEvents, isTrue);
  });

  test('native load failure is attributed and later open remains usable',
      () async {
    final player = Player();
    final subscription = player.sourceEvents.listen((_) {});
    addTearDown(() async {
      await subscription.cancel();
      await player.dispose();
    });

    final failedSource = Object();
    final failure = player.sourceEvents.firstWhere(
      (event) =>
          identical(event.source, failedSource) &&
          event.kind == PlaybackSourceEventKind.error,
    );
    await player.open(
      Media('${directory.path}/missing.wav'),
      source: failedSource,
    );
    final error = await failure.timeout(const Duration(seconds: 5));
    expect(error.errorCode, isNegative);
    expect(error.playlistEntryId, isNotNull);

    final goodSource = Object();
    final ready = player.sourceEvents.firstWhere(
      (event) =>
          identical(event.source, goodSource) &&
          event.kind == PlaybackSourceEventKind.firstFrame,
    );
    await player.open(media, play: false, source: goodSource);
    await ready.timeout(const Duration(seconds: 5));
  });

  test('entry ID read failure revokes old attribution and permits recovery',
      () async {
    final player = Player();
    final events = <PlaybackSourceEvent>[];
    final subscription = player.sourceEvents.listen(events.add);
    addTearDown(() async {
      NativePlayer.sourceEntryIdReaderForTesting = null;
      await subscription.cancel();
      await player.dispose();
    });

    final oldSource = Object();
    final oldReady = player.sourceEvents.firstWhere(
      (event) =>
          identical(event.source, oldSource) &&
          event.kind == PlaybackSourceEventKind.firstFrame,
    );
    await player.open(media, source: oldSource);
    await oldReady.timeout(const Duration(seconds: 5));

    final failedSource = Object();
    NativePlayer.sourceEntryIdReaderForTesting = () {
      throw StateError('injected playlist entry ID read failure');
    };
    await expectLater(
      player.open(media, source: failedSource),
      throwsStateError,
    );
    NativePlayer.sourceEntryIdReaderForTesting = null;

    await Future<void>.delayed(const Duration(milliseconds: 100));
    final oldInvalidation = events.indexWhere(
      (event) =>
          identical(event.source, oldSource) &&
          event.kind == PlaybackSourceEventKind.invalidated,
    );
    expect(oldInvalidation, isNonNegative);
    expect(events.where((event) => identical(event.source, failedSource)),
        isEmpty);
    expect(
      events.skip(oldInvalidation + 1).where(
            (event) => identical(event.source, oldSource),
          ),
      isEmpty,
    );

    final recoveredSource = Object();
    final recoveredReady = player.sourceEvents.firstWhere(
      (event) =>
          identical(event.source, recoveredSource) &&
          event.kind == PlaybackSourceEventKind.firstFrame,
    );
    await player.open(media, play: false, source: recoveredSource);
    await recoveredReady.timeout(const Duration(seconds: 5));
  });

  test('revoked entry ignores delayed end events and permits later opens',
      () async {
    final player = Player();
    final native = player.platform! as NativePlayer;
    final handle = await native.handle;
    final tracker = SourceEventTracker(
      native.mpv,
      () => Pointer<generated.mpv_handle>.fromAddress(handle),
    );
    final failedSource = Object();
    final events = <PlaybackSourceEvent>[];
    final subscription = tracker.stream.listen(events.add);
    addTearDown(() async {
      await subscription.cancel();
      await tracker.close();
      await player.dispose();
    });

    const failedEntryId = 987654;
    tracker.register(failedEntryId, failedSource);
    tracker.invalidateSource(
      failedSource,
      reason: 'simulated post-registration open failure',
    );
    final trackedRecoverySource = Object();
    tracker.register(failedEntryId + 1, trackedRecoverySource);

    final end = calloc<generated.mpv_event_end_file>()
      ..ref.playlist_entry_id = failedEntryId;
    final event = calloc<generated.mpv_event>()
      ..ref.event_id = generated.mpv_event_id.MPV_EVENT_END_FILE
      ..ref.data = end.cast();
    try {
      tracker.handle(event);
    } finally {
      calloc.free(event);
      calloc.free(end);
    }
    await Future<void>.delayed(Duration.zero);

    expect(tracker.containsSource(failedSource), isFalse);
    expect(tracker.containsSource(trackedRecoverySource), isTrue);
    expect(
      events.map((event) => event.kind),
      [PlaybackSourceEventKind.invalidated],
    );

    final goodSource = Object();
    final goodReady = player.sourceEvents.firstWhere(
      (event) =>
          identical(event.source, goodSource) &&
          event.kind == PlaybackSourceEventKind.firstFrame,
    );
    await player.open(media, play: false, source: goodSource);
    await goodReady.timeout(const Duration(seconds: 5));
  });

  test('source attribution also works with synchronous libmpv commands',
      () async {
    final player =
        Player(configuration: const PlayerConfiguration(async: false));
    final source = Object();
    addTearDown(player.dispose);
    final started = player.sourceEvents.firstWhere(
      (event) =>
          identical(event.source, source) &&
          event.kind == PlaybackSourceEventKind.start,
    );
    final ready = player.sourceEvents.firstWhere(
      (event) =>
          identical(event.source, source) &&
          event.kind == PlaybackSourceEventKind.firstFrame,
    );

    await player.open(media, source: source);
    final startEvent = await started.timeout(const Duration(seconds: 5));
    final readyEvent = await ready.timeout(const Duration(seconds: 5));
    expect(startEvent.playlistEntryId, isNotNull);
    expect(readyEvent.playlistEntryId, startEvent.playlistEntryId);
  });
}
