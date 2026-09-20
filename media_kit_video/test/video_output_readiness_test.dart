import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video/video_texture.dart';
import 'package:media_kit_video/src/video_controller/video_controller.dart';

void main() {
  test('accepts an output snapshot that was ready before Video mounted', () {
    const output = VideoOutputState(
      id: 42,
      rect: Rect.fromLTWH(0, 0, 1920, 1080),
    );

    expect(isVideoOutputReady(output), isTrue);
  });

  test('rejects output without both texture identity and dimensions', () {
    expect(
      isVideoOutputReady(
        const VideoOutputState(rect: Rect.fromLTWH(0, 0, 1920, 1080)),
      ),
      isFalse,
    );
    expect(
      isVideoOutputReady(const VideoOutputState(id: 42)),
      isFalse,
    );
  });

  test('rejects placeholder and invalid output dimensions', () {
    for (final rect in <Rect>[
      const Rect.fromLTWH(0, 0, 1, 1080),
      const Rect.fromLTWH(0, 0, 1920, 1),
      const Rect.fromLTWH(0, 0, 0, 0),
      const Rect.fromLTWH(0, 0, double.infinity, 1080),
      const Rect.fromLTWH(0, 0, 1920, double.nan),
    ]) {
      expect(
        isVideoOutputReady(VideoOutputState(id: 42, rect: rect)),
        isFalse,
        reason: '$rect must remain covered by the initialization fill',
      );
    }
  });
}
