import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video_controller/native_video_controller/real.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

void main() {
  test('decodes every native picture-in-picture lifecycle state', () {
    for (final state in PictureInPictureState.values) {
      expect(pictureInPictureStateFromName(state.name), state);
    }
  });

  test('ignores unknown picture-in-picture lifecycle states', () {
    expect(pictureInPictureStateFromName('future-state'), isNull);
    expect(pictureInPictureStateFromName(null), isNull);
  });
}
