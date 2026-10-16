@TestOn('browser')
library;

import 'package:media_kit/media_kit.dart';
import 'package:test/test.dart';

void main() {
  test('conditional NativePlayer export keeps the per-media API on web',
      () async {
    // Compile through the public conditional export, not a direct stub import.
    final native = NativePlayer(configuration: const PlayerConfiguration());
    expect(native.supportsSourceEvents, isFalse);
    await expectLater(native.firstFrameOfMedia, emitsDone);
  });

  test('web Player rejects source attribution without changing legacy opens',
      () async {
    final player = Player();
    addTearDown(player.dispose);
    expect(player.supportsSourceEvents, isFalse);
    await expectLater(player.sourceEvents, emitsDone);
    await expectLater(
      player.open(Media('https://example.invalid/audio.mp3'), source: Object()),
      throwsUnsupportedError,
    );
  });
}
