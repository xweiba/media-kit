@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:test/test.dart';

// Uses the same libmpv discovery as the other native tests. A host can set
// LIBMPV_LIBRARY_PATH; no network, audio device or Flutter renderer is needed.
void main() {
  late Directory directory;
  late Media media;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('media-kit-lifecycle-');
    addTearDown(() => directory.delete(recursive: true));
    MediaKit.ensureInitialized();
    NativePlayer.test = true;
    final file = File('${directory.path}/silence.wav');
    // Ten seconds of mono 8 kHz signed PCM, long enough to seek twice.
    const dataLength = 10 * 8000 * 2;
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

  for (final async in [true, false]) {
    test(
        'failed seek propagates and does not publish completion (async=$async)',
        () async {
      final player = Player(configuration: PlayerConfiguration(async: async));
      final completionEvents = <bool>[];
      final subscription = player.stream.completed.listen(completionEvents.add);
      addTearDown(() async {
        await subscription.cancel();
        await player.dispose();
      });
      await player.platform!.waitForPlayerInitialization;
      await Future<void>.delayed(Duration.zero);
      completionEvents.clear();

      // No media is open: mpv rejects seek instead of acknowledging a landing.
      await expectLater(
        player.seek(const Duration(seconds: 1)),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'native error',
          contains('mpv seek failed:'),
        )),
      );
      await Future<void>.delayed(Duration.zero);
      expect(completionEvents, isEmpty);

      // The failed command releases the lock and the same player remains usable.
      final native = player.platform as NativePlayer;
      final ready = native.firstFrameOfMedia.first;
      await player.open(media);
      await ready.timeout(const Duration(seconds: 5));
      await player.seek(const Duration(seconds: 2));
    });
  }

  test('media restart is per file, not per seek or controller lifetime',
      () async {
    final player = Player();
    final native = player.platform as NativePlayer;
    final events = <void>[];
    final done = Completer<void>();
    final subscription = native.firstFrameOfMedia.listen(
      (_) => events.add(null),
      onDone: done.complete,
    );
    var disposed = false;
    addTearDown(() async {
      await subscription.cancel();
      if (!disposed) await player.dispose();
    });
    final handle = await player.handle;

    Future<void> openAndWait() async {
      final ready = native.firstFrameOfMedia.first;
      await player.open(media, play: false);
      await ready.timeout(const Duration(seconds: 5));
    }

    await openAndWait();
    expect(events, hasLength(1));

    // Observe actual seek advancement before checking that its restart did not
    // masquerade as a new file's first event. A command acknowledgement alone
    // would race the event queue.
    final advanced = player.stream.position.firstWhere(
      (position) => position > const Duration(milliseconds: 2250),
    );
    await player.seek(const Duration(seconds: 2));
    await player.play();
    await advanced.timeout(const Duration(seconds: 5));
    expect(events, hasLength(1));

    await player.stop();
    expect(player.state.playlist.medias, isEmpty);
    expect(player.state.playing, isFalse);
    expect(await player.handle, handle);

    final failed = player.stream.error.firstWhere(
      (error) => error.contains('Failed to open'),
    );
    await player.open(Media('${directory.path}/missing.wav'));
    await failed.timeout(const Duration(seconds: 5));
    await player.stop();
    expect(events, hasLength(1),
        reason: 'A failed file has no restart evidence');

    await openAndWait();
    expect(events, hasLength(2));
    expect(await player.handle, handle);
    await player.dispose();
    disposed = true;
    await done.future.timeout(const Duration(seconds: 5));
  });
}
