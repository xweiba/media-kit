@TestOn('browser')
library;

import 'package:media_kit/media_kit.dart';
import 'package:test/test.dart';

void main() {
  test('conditional NativePlayer export keeps the per-media API on web',
      () async {
    // Compile through the public conditional export, not a direct stub import.
    final native = NativePlayer(configuration: const PlayerConfiguration());
    await expectLater(native.firstFrameOfMedia, emitsDone);
  });
}
