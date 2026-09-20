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

  test('decodes a finite non-negative picture-in-picture seek', () {
    final message = pictureInPictureSeekEventFromArguments({
      'handle': 7,
      'originSeconds': 12.25,
      'targetSeconds': 22.5,
    });

    expect(message?.key, 7);
    expect(
      message?.value,
      const PictureInPictureSeekEvent(
        origin: Duration(milliseconds: 12250),
        target: Duration(milliseconds: 22500),
      ),
    );
  });

  test('rejects malformed picture-in-picture seek payloads', () {
    expect(pictureInPictureSeekEventFromArguments(null), isNull);
    expect(
      pictureInPictureSeekEventFromArguments({
        'handle': '7',
        'originSeconds': 1.0,
        'targetSeconds': 2.0,
      }),
      isNull,
    );
    expect(
      pictureInPictureSeekEventFromArguments({
        'handle': 7,
        'originSeconds': -1.0,
        'targetSeconds': 2.0,
      }),
      isNull,
    );
    expect(
      pictureInPictureSeekEventFromArguments({
        'handle': 7,
        'originSeconds': 1.0,
        'targetSeconds': double.infinity,
      }),
      isNull,
    );
    expect(
      pictureInPictureSeekEventFromArguments({
        'handle': 7,
        'originSeconds': 1.0,
        'targetSeconds': 9223372036855.0,
      }),
      isNull,
    );
  });
}
