@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late Media media;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('media-kit-events-');
    addTearDown(() => directory.delete(recursive: true));
    MediaKit.ensureInitialized();
    NativePlayer.test = true;
    final file = File('${directory.path}/silence.wav');
    const dataLength = 8000 * 2;
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

  test('observeEvent delivers raw events until unobserved', () async {
    final player = Player();
    addTearDown(player.dispose);
    final native = player.platform! as NativePlayer;
    const event = generated.mpv_event_id.MPV_EVENT_FILE_LOADED;

    final loaded = Completer<void>();
    var count = 0;
    await native.observeEvent(event, (pointer) async {
      expect(pointer.ref.event_id, event);
      count++;
      if (!loaded.isCompleted) loaded.complete();
    });
    expect(
      () => native.observeEvent(event, (_) async {}),
      throwsArgumentError,
    );

    await player.open(media, play: false);
    await loaded.future.timeout(const Duration(seconds: 10));
    expect(count, 1);

    await native.unobserveEvent(event);
    expect(() => native.unobserveEvent(event), throwsArgumentError);

    // Unobserving only drops the listener: the event still reaches mpv's
    // client and media_kit's own handling keeps working.
    await player.open(media, play: false);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(player.state.duration, greaterThan(Duration.zero));
    expect(count, 1);
  });
}
