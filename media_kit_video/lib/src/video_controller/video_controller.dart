/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

import 'package:media_kit_video/src/video_controller/native_video_controller/native_video_controller.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';
import 'package:media_kit_video/src/video_controller/ohos_video_controller/ohos_video_controller.dart';
import 'package:media_kit_video/src/video_controller/web_video_controller/web_video_controller.dart';

/// Texture identity and dimensions published as one render-frame snapshot.
///
/// Native resize callbacks carry both values atomically. Keeping the same
/// boundary in Dart prevents consumers from rebuilding with a new texture ID
/// and stale dimensions (or the reverse) during output initialization.
@immutable
class VideoOutputState {
  /// Texture ID registered by the platform implementation, or null before it
  /// is available.
  final int? id;

  /// Native video dimensions, or null before the first resize callback.
  final Rect? rect;

  /// Creates an immutable native video-output snapshot.
  const VideoOutputState({this.id, this.rect});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoOutputState && other.id == id && other.rect == rect;

  @override
  int get hashCode => Object.hash(id, rect);
}

/// {@template video_controller}
///
/// VideoController
/// ---------------
///
/// [VideoController] is used to initialize & display video output.
/// It takes reference to existing [Player] instance from `package:media_kit`.
///
/// Passing [VideoController] to [Video] widget will cause the video output to be displayed.
///
/// ```dart
/// late final player = Player();
/// late final controller = VideoController(player);
/// ```
///
/// **Configurable options:**
///
/// 1. You can limit size of the video output by specifying [VideoControllerConfiguration.width] & [VideoControllerConfiguration.height].
///    * A smaller width & height may yield substantial performance improvements.
///    * By default, both [VideoControllerConfiguration.height] & [VideoControllerConfiguration.width] are `null` i.e. output is based on video's resolution.
/// 2. You can reduce scale of the video output by specifying [VideoControllerConfiguration.scale].
///    * A smaller scale may yield substantial performance improvements. Specifying this value will cause [VideoControllerConfiguration.width] & [VideoControllerConfiguration.height] to be ignored.
///    * By default, [VideoControllerConfiguration.scale] is `1.0` i.e. output is based on video's resolution.
/// 3. You can switch between GPU & CPU rendering by specifying [VideoControllerConfiguration.enableHardwareAcceleration].
///    * Disabling the option may improve stability on certain devices.
///    * By default, [VideoControllerConfiguration.enableHardwareAcceleration] is `true` i.e. GPU (Direct3D/OpenGL/METAL) is utilized.
///
/// **Platform specific limitations & differences:**
///
/// **Android**
/// * [VideoControllerConfiguration.width] & [VideoControllerConfiguration.height] arguments have no effect.
///
/// **Web**
/// * [VideoControllerConfiguration.width] & [VideoControllerConfiguration.height] arguments have no effect.
/// * Only single [Video] output can be displayed for a [VideoController].
///   Displaying multiple [Video] widgets with same [VideoController] will cause only last mounted [Video] to be displayed.
/// * [VideoControllerConfiguration.enableHardwareAcceleration] is ignored i.e. GPU usage is dependent upon the web browser.
///
/// {@endtemplate}
class VideoController {
  /// The [Player] instance associated with this [VideoController].
  final Player player;

  /// Immutable output configuration used by both the native controller and
  /// the rendering widget.
  final VideoControllerConfiguration configuration;

  /// Platform specific internal implementation initialized depending upon the current platform.
  final platform = Completer<PlatformVideoController>();

  /// Platform specific internal implementation initialized depending upon the current platform.
  final notifier = ValueNotifier<PlatformVideoController?>(null);

  /// Texture ID of the video output, registered with Flutter engine by the native implementation.
  final ValueNotifier<int?> id = ValueNotifier<int?>(null);

  /// [Rect] of the video output, received from the native implementation.
  final ValueNotifier<Rect?> rect = ValueNotifier<Rect?>(null);

  /// Atomic texture ID and dimensions consumed by native texture widgets.
  final ValueNotifier<VideoOutputState> output =
      ValueNotifier<VideoOutputState>(const VideoOutputState());

  /// Current native picture-in-picture lifecycle state.
  final ValueNotifier<PictureInPictureState> pictureInPictureState =
      ValueNotifier<PictureInPictureState>(PictureInPictureState.stopped);

  /// {@macro video_controller}
  VideoController(
    this.player, {
    this.configuration = const VideoControllerConfiguration(),
  }) {
    player.platform?.isVideoControllerAttached = true;

    () async {
      final completer = Completer();
      WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
      await completer.future;

      try {
        if (NativeVideoController.supported) {
          final result = await NativeVideoController.create(
            player,
            configuration,
          );
          platform.complete(result);
          notifier.value = result;
        } else if (AndroidVideoController.supported) {
          final result = await AndroidVideoController.create(
            player,
            configuration,
          );
          platform.complete(result);
          notifier.value = result;
        } else if (OhosVideoController.supported) {
          final result = await OhosVideoController.create(
            player,
            configuration,
          );
          platform.complete(result);
          notifier.value = result;
        } else if (WebVideoController.supported) {
          final result = await WebVideoController.create(player, configuration);
          platform.complete(result);
          notifier.value = result;
        }

        if (platform.isCompleted) {
          // Populate [id] & [rect] [ValueNotifier]s with the values from [platform] implementation of [PlatformVideoController].
          final controller = await platform.future;
          // Add listeners.
          void fn0() => id.value = controller.id.value;
          void fn1() => rect.value = controller.rect.value;
          var outputUpdateScheduled = false;
          var released = false;
          void syncOutput() {
            // Platform implementations may update rect and ID back-to-back for
            // one resize callback. Publish after the current synchronous turn
            // so widgets observe one coherent state and build only once.
            if (outputUpdateScheduled) return;
            outputUpdateScheduled = true;
            scheduleMicrotask(() {
              outputUpdateScheduled = false;
              if (released) return;
              output.value = VideoOutputState(
                id: controller.id.value,
                rect: controller.rect.value,
              );
            });
          }

          void fn2() => pictureInPictureState.value =
              controller.pictureInPictureState.value;
          fn0();
          fn1();
          syncOutput();
          fn2();
          controller.id.addListener(fn0);
          controller.rect.addListener(fn1);
          controller.id.addListener(syncOutput);
          controller.rect.addListener(syncOutput);
          controller.pictureInPictureState.addListener(fn2);
          // Remove listeners upon [Player.dispose].
          player.platform?.release.add(() async {
            released = true;
            controller.id.removeListener(fn0);
            controller.rect.removeListener(fn1);
            controller.id.removeListener(syncOutput);
            controller.rect.removeListener(syncOutput);
            controller.pictureInPictureState.removeListener(fn2);
            pictureInPictureState.value = PictureInPictureState.stopped;
          });
        } else {
          platform.completeError(
            UnimplementedError(
              '[VideoController] is unavailable for this platform.',
            ),
          );
        }
      } catch (exception, stacktrace) {
        platform.completeError(exception);
        debugPrint(exception.toString());
        debugPrint(stacktrace.toString());
      }

      if (!(player.platform?.videoControllerCompleter.isCompleted ?? true)) {
        player.platform?.videoControllerCompleter.complete();
      }
    }();
  }

  /// Sets the required size of the video output.
  /// This may yield substantial performance improvements if a small [width] & [height] is specified.
  ///
  /// Remember:
  /// * “Premature optimization is the root of all evil”
  /// * “With great power comes great responsibility”
  Future<void> setSize({int? width, int? height}) async {
    final instance = await platform.future;
    return instance.setSize(width: width, height: height);
  }

  /// A [Future] that completes when the first video frame has been rendered.
  Future<void> get waitUntilFirstFrameRendered async {
    final instance = await platform.future;
    return instance.waitUntilFirstFrameRendered;
  }

  /// 使用当前视频输出进入系统画中画；不支持的平台返回 false。
  Future<bool> enterPictureInPicture() async {
    final instance = await platform.future;
    return instance.enterPictureInPicture();
  }

  /// Prepares native picture-in-picture without presenting it immediately.
  Future<bool> preparePictureInPicture() async {
    final instance = await platform.future;
    return instance.preparePictureInPicture();
  }

  /// Dismisses native picture-in-picture when supported by the platform.
  Future<bool> exitPictureInPicture() async {
    final instance = await platform.future;
    return instance.exitPictureInPicture();
  }
}
