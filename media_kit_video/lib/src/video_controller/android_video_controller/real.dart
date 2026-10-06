/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/utils/query_decoders.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

/// {@template android_video_controller}
///
/// AndroidVideoController
/// ----------------------
///
/// The [PlatformVideoController] implementation based on native JNI & C/C++ used on Android.
///
/// {@endtemplate}
class AndroidVideoController extends PlatformVideoController {
  /// Whether [AndroidVideoController] is supported on the current platform or not.
  static bool get supported => Platform.isAndroid;

  /// Pointer address to the global object reference of `android.view.Surface` i.e. `(intptr_t)(*android.view.Surface)`.
  final ValueNotifier<int?> wid = ValueNotifier<int?>(null);

  /// [Lock] used to synchronize [onLoadHooks], [onUnloadHooks] & [subscription].
  final lock = Lock();

  NativePlayer get platform => player.platform as NativePlayer;

  /// Re-creating the video output blocks libmpv's core for a few hundred
  /// milliseconds: set asynchronously so the UI isolate keeps running.
  Future<void> setProperty(String key, String value) async {
    await platform.setPropertyAsync(key, value);
  }

  Future<void> setProperties(Map<String, String> properties) async {
    for (final entry in properties.entries) {
      await setProperty(entry.key, entry.value);
    }
  }

  /// Surface mode ([VideoControllerConfiguration.androidSurfaceView]): mpv
  /// renders into a native `SurfaceView` placed by [Video] instead of a texture.
  bool get surfaceMode => configuration.androidSurfaceView;

  /// Surface mode: the `SurfaceView`s currently on screen (platform view id →
  /// surface reference and pixel size), oldest first. The newest one (a
  /// fullscreen page over a feed) gets mpv's output; when it goes away the
  /// output returns to the one below.
  final _surfaces = <int, _Surface>{};

  /// The surface mpv renders into (surface mode).
  _Surface? _surface;

  /// Surface mode: frames may go straight to the display ([setDirectOutput]).
  bool _direct = true;

  /// Surface mode: the hardware decoder refused the current file while frames
  /// went straight to the display (e.g. 10-bit H.264): mpv decodes in software,
  /// which `vo=mediacodec_embed` cannot show, so the file is drawn with
  /// `vo=gpu`. Kept until another file loads or direct output is asked for
  /// again (under `vo=gpu` mpv may decode in software for its own reasons, e.g.
  /// no GPU import for 10-bit frames, which says nothing about direct output).
  bool _softwareDecoding = false;

  /// Surface mode: no hardware decoder takes the selected video track
  /// (checked with `MediaCodecList` before frames go anywhere: switching an
  /// already software-decoding stream to `vo=mediacodec_embed` stalls mpv).
  bool _hardwareUnsupported = false;

  /// Surface mode: the video output in use.
  String get _surfaceVo =>
      _direct && !_softwareDecoding && !_hardwareUnsupported
          ? 'mediacodec_embed'
          : 'gpu';

  /// Surface mode: the selected video track or its decoded format changed;
  /// checks whether a hardware decoder can take it. Before the surface
  /// arrives mpv decodes a few frames in software, so the pixel format (bit
  /// depth, chroma) is known before frames go anywhere; mpv often leaves the
  /// track's profile empty.
  Future<void> _onVideoTrack() async {
    final codec = await _readProperty('current-tracks/video/codec');
    if (codec.isEmpty) return;
    final profile = await _readProperty('current-tracks/video/codec-profile');
    final pixelFormat = await _readProperty('video-params/pixelformat');
    // Live streams report the same format again on every output reconfig:
    // look each combination up once.
    final key = '$codec|$profile|$pixelFormat';
    if (key == _checkedTrack) return;
    _checkedTrack = key;
    bool supported;
    if (pixelFormat.startsWith('mediacodec')) {
      // Frames already come from the hardware decoder.
      supported = true;
    } else {
      supported = await _hardwareDecoderSupports(codec, profile, pixelFormat);
    }
    if (_hardwareUnsupported == !supported) return;
    final before = _surfaceVo;
    _hardwareUnsupported = !supported;
    if (_surfaceVo != before && (wid.value ?? 0) != 0) await widListener();
  }

  /// Last combination [_onVideoTrack] looked up (codec|profile|pixelformat).
  String? _checkedTrack;

  Future<bool> _hardwareDecoderSupports(
    String codec,
    String profile,
    String pixelFormat,
  ) async {
    try {
      return await _channel.invokeMethod<bool>(
            'Utils.HardwareDecoderSupports',
            {
              'codec': codec,
              'profile': profile.isEmpty ? null : profile,
              'pixelFormat': pixelFormat.isEmpty ? null : pixelFormat,
            },
          ) ??
          true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> setDirectOutput(bool value) async {
    if (!surfaceMode || _direct == value) return;
    _direct = value;
    if (value) _softwareDecoding = false;
    if ((wid.value ?? 0) != 0) await widListener();
  }

  /// Surface mode: mpv's log while frames go straight to the display. When
  /// the hardware decoder cannot take the stream after all (the capability
  /// check passed), mpv decodes in software and then reports that the direct
  /// output cannot show those frames — definitive, unlike `hwdec-current`,
  /// which also reads `no` while a slow stream is still starting.
  StreamSubscription<PlayerLog>? _logSubscription;

  void _onLog(PlayerLog log) {
    if (_softwareDecoding || _surfaceVo != 'mediacodec_embed') return;
    if (!log.text.startsWith('Cannot convert decoder/filter output')) return;
    _softwareDecoding = true;
    if ((wid.value ?? 0) != 0) unawaited(widListener());
  }

  Future<String> _readProperty(String name) async {
    try {
      return await platform.getProperty(name);
    } catch (_) {
      return '';
    }
  }

  /// Surface mode: a new file may decode in hardware again.
  Future<void> _onPath() async {
    if (!_softwareDecoding) return;
    _softwareDecoding = false;
    if (_surfaceVo == 'mediacodec_embed' && (wid.value ?? 0) != 0) {
      await widListener();
    }
  }

  void _onSurface(int viewId, int wid, int width, int height) {
    _surfaces.remove(viewId);
    if (wid != 0) _surfaces[viewId] = _Surface(wid, width, height);
    final top = _surfaces.isEmpty ? null : _surfaces.values.last;
    final sizeChanged = top?.width != _surface?.width ||
        top?.height != _surface?.height;
    _surface = top;
    final next = top?.wid ?? 0;
    if (this.wid.value != next) {
      this.wid.value = next;
    } else if (sizeChanged && next != 0) {
      widListener();
    }
  }

  /// Surface mode: frames go from MediaCodec straight to the display and never
  /// reach mpv's renderer, so mpv cannot take a screenshot. Copies the pixels
  /// of the surface showing the video (`PixelCopy`, at the video size) instead.
  Future<Uint8List?> _capture(String? format, int? maxWidth) async {
    if (_surfaces.isEmpty) return null;
    return _channel.invokeMethod<Uint8List>('SurfaceVideoView.Capture', {
      'viewId': _surfaces.keys.last,
      'maxWidth': maxWidth,
      'format': format == null
          ? 'raw'
          : format == 'image/png'
              ? 'png'
              : 'jpeg',
    });
  }

  /// Surface mode: tells the native view [viewId] the video size and fit; it
  /// sizes and centres its `SurfaceView` itself (a hybrid-composition platform
  /// view cannot be resized from Dart).
  static Future<void> setSurfaceVideoSize(
    int viewId, {
    required int width,
    required int height,
    required bool cover,
  }) =>
      _channel.invokeMethod('SurfaceVideoView.SetVideoSize', {
        'viewId': viewId,
        'width': width,
        'height': height,
        'cover': cover,
      });

  /// Listener for updating the --wid property.
  Future<void> widListener() {
    return lock.synchronized(() async {
      final surface = surfaceMode ? _surface : null;
      final width = surface?.width ?? rect.value?.width.toInt() ?? 1;
      final height = surface?.height ?? rect.value?.height.toInt() ?? 1;
      final androidSurfaceSizeValue = [width, height].join('x');
      final widValue = wid.value?.toString() ?? '0';
      // When --wid is 0, vo=null is required to avoid SIGSEGV.
      final voValue = widValue == '0'
          ? 'null'
          : surfaceMode
              ? _surfaceVo
              : configuration.vo!;
      final vidValue = widValue == '0' ? 'no' : 'auto';
      // It is important to re-initialize --vo after --android-surface-size.
      await setProperty('vo', 'null');
      await setProperties(
        {
          // ORDER IS IMPORTANT.
          'android-surface-size': androidSurfaceSizeValue,
          'wid': widValue,
          'vo': voValue,
        },
      );
      // It is important to re-initialize --vid in-case of --vo=mediacodec_embed.
      // Not doing so causes error "Could not open codec." & video never gets rendered.
      // Toggle through `no`: if the track is already `auto` (media opened before
      // this surface, or moving to another surface) setting `auto` again is a
      // no-op and the decoder stays bound to the old output.
      if (voValue == 'mediacodec_embed') {
        await setProperty('vid', 'no');
        await setProperty('vid', vidValue);
      }
      // Instead of seeking to the start (Duration.zero), seek to the current playback position
      // without jumping the user to the start of the media.
      final currentPosition = player.state.position;
      await player.seek(currentPosition);
    });
  }

  /// [StreamSubscription] for listening to video [Rect].
  StreamSubscription<VideoParams>? videoParamsSubscription;

  /// {@macro android_video_controller}
  AndroidVideoController._(
    super.player,
    super.configuration,
  ) {
    wid.addListener(widListener);
    videoParamsSubscription = player.stream.videoParams.listen(
      (event) => lock.synchronized(() async {
        final int width;
        final int height;
        if (event.rotate == 0 || event.rotate == 180) {
          width = event.dw ?? 0;
          height = event.dh ?? 0;
        } else {
          // width & height are swapped for 90 or 270 degrees rotation.
          width = event.dh ?? 0;
          height = event.dw ?? 0;
        }

        final isZero = width == 0 || height == 0;
        final isSame = width == rect.value?.width.toInt() &&
            height == rect.value?.height.toInt();
        if (isZero || isSame) {
          return;
        }

        final handle = await player.handle;

        // Surface mode has no texture to resize: the SurfaceView is sized by
        // its layout and reports its own size.
        if (!surfaceMode) {
          await _channel.invokeMethod(
            'VideoOutputManager.SetSurfaceSize',
            {
              'handle': handle.toString(),
              'width': width.toString(),
              'height': height.toString(),
            },
          );
        }

        rect.value = Rect.fromLTWH(
          0.0,
          0.0,
          width.toDouble(),
          height.toDouble(),
        );

        if (!waitUntilFirstFrameRenderedCompleter.isCompleted) {
          waitUntilFirstFrameRenderedCompleter.complete();
        }
      }),
    );
  }

  /// {@macro android_video_controller}
  static Future<PlatformVideoController> create(
    Player player,
    VideoControllerConfiguration configuration,
  ) async {
    Future<String> getDefaultHwdec() async {
      // Enforce software rendering in emulators.
      bool hw = configuration.enableHardwareAcceleration;
      final bool isEmulator = await _channel.invokeMethod('Utils.IsEmulator');
      if (isEmulator) {
        hw = false;
        debugPrint('media_kit: Emulator detected.');
        debugPrint('media_kit: Enforcing S/W rendering.');
      }
      return hw ? 'auto-safe' : 'no';
    }

    // Surface mode needs the hardware decoder writing into the surface; on
    // an emulator (software decoding) fall back to the texture path. Below
    // Android 10 hybrid-composition platform views copy every Flutter frame
    // (Flutter documents the cost), so those keep the texture path too.
    if (configuration.androidSurfaceView &&
        (await _channel.invokeMethod('Utils.IsEmulator') == true ||
            ((await _channel.invokeMethod<int>('Utils.SdkInt')) ?? 0) < 29)) {
      configuration = configuration.copyWith(androidSurfaceView: false);
    }
    // Update [configuration] to have default values.
    configuration = configuration.copyWith(
      vo: configuration.vo ??
          (configuration.androidSurfaceView ? 'mediacodec_embed' : 'gpu'),
      hwdec: configuration.hwdec ??
          (configuration.androidSurfaceView
              ? 'mediacodec'
              : await getDefaultHwdec()),
    );

    // Retrieve the native handle of the [Player].
    final handle = await player.handle;
    // Return the existing [VideoController] if it's already created.
    if (_controllers.containsKey(handle)) {
      return _controllers[handle]!;
    }

    // In case no video-decoders are found, this means media_kit_libs_***_audio is being used.
    // Thus, --vid=no is required to prevent libmpv from trying to decode video (otherwise bad things may happen).
    //
    // Search for common H264 decoder to check if video support is available.
    final decoders = await queryDecoders(handle);
    if (!decoders.contains('h264')) {
      throw UnsupportedError(
        '[VideoController] is not available.'
        ' '
        'Please use media_kit_libs_***_video instead of media_kit_libs_***_audio.',
      );
    }

    // Creation:
    final controller = AndroidVideoController._(
      player,
      configuration,
    );

    // Register [_dispose] for execution upon [Player.dispose].
    player.platform?.release.add(controller._dispose);

    // Store the [VideoController] in the [_controllers].
    _controllers[handle] = controller;

    if (configuration.androidSurfaceView) {
      controller.platform.frameCapture = controller._capture;
      controller._logSubscription = player.stream.log.listen(controller._onLog);
      await controller.platform.observeProperty(
        'path',
        (_) => controller._onPath(),
        waitForInitialization: false,
      );
      await controller.platform.observeProperty(
        'current-tracks/video/codec',
        (_) => controller._onVideoTrack(),
        waitForInitialization: false,
      );
      await controller.platform.observeProperty(
        'video-params/pixelformat',
        (_) => controller._onVideoTrack(),
        waitForInitialization: false,
      );
    }

    if (!configuration.androidSurfaceView) {
      await _channel.invokeMethod(
        'VideoOutputManager.Create',
        {
          'handle': handle.toString(),
          'enableSurfaceProducer': configuration.enableAndroidSurfaceProducer,
        },
      );
    }

    await controller.setProperties(
      {
        // It is necessary to set vo=null here to avoid SIGSEGV, --wid must be assigned before vo=gpu is set.
        'vo': 'null',
        'hwdec': configuration.hwdec!,
        'vid': 'auto',
        'force-window': 'yes',
        'gpu-api': configuration.vo == 'gpu-next' ? 'vulkan,opengl' : 'auto',
        'sub-use-margins': 'no',
        'sub-font-provider': 'none',
        'sub-scale-with-window': 'yes',
        'hwdec-codecs': 'h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1',
      },
    );

    // Return the [PlatformVideoController].
    return controller;
  }

  /// Sets the required size of the video output.
  /// This may yield substantial performance improvements if a small [width] & [height] is specified.
  ///
  /// Remember:
  /// * “Premature optimization is the root of all evil”
  /// * “With great power comes great responsibility”
  @override
  Future<void> setSize({
    int? width,
    int? height,
  }) {
    throw UnsupportedError(
      '[AndroidVideoController.setSize] is not available on Android',
    );
  }

  /// Disposes the instance. Releases allocated resources back to the system.
  Future<void> _dispose() async {
    super.dispose();
    wid.dispose();
    wid.removeListener(widListener);
    await videoParamsSubscription?.cancel();
    await _logSubscription?.cancel();
    final handle = await player.handle;
    _controllers.remove(handle);
    if (surfaceMode) {
      if (platform.frameCapture == _capture) platform.frameCapture = null;
      return;
    }
    await _channel.invokeMethod(
      'VideoOutputManager.Dispose',
      {
        'handle': handle.toString(),
      },
    );
  }

  /// Currently created [AndroidVideoController]s.
  static final _controllers = HashMap<int, AndroidVideoController>();

  /// [MethodChannel] for invoking platform specific native implementation.
  static final _channel =
      const MethodChannel('com.alexmercerind/media_kit_video')
        ..setMethodCallHandler(
          (MethodCall call) async {
            try {
              debugPrint(call.method.toString());
              debugPrint(call.arguments.toString());
              switch (call.method) {
                case 'VideoOutput.Resize':
                  {
                    // Notify about updated texture ID & [Rect].
                    final int handle = call.arguments['handle'];
                    final Rect rect = Rect.fromLTWH(
                      call.arguments['rect']['left'] * 1.0,
                      call.arguments['rect']['top'] * 1.0,
                      call.arguments['rect']['width'] * 1.0,
                      call.arguments['rect']['height'] * 1.0,
                    );
                    final int id = call.arguments['id'];
                    final int wid = call.arguments['wid'];
                    _controllers[handle]?.rect.value = rect;
                    _controllers[handle]?.id.value = id;
                    _controllers[handle]?.wid.value = wid;
                    break;
                  }
                case 'SurfaceVideoView.Surface':
                  {
                    final int handle =
                        int.parse(call.arguments['handle'] as String);
                    _controllers[handle]?._onSurface(
                      call.arguments['viewId'] as int,
                      call.arguments['wid'] as int,
                      call.arguments['width'] as int,
                      call.arguments['height'] as int,
                    );
                    break;
                  }
                case 'VideoOutput.WaitUntilFirstFrameRenderedNotify':
                  {
                    // Notify about updated texture ID & [Rect].
                    final int handle = call.arguments['handle'];
                    debugPrint(handle.toString());
                    // Notify about the first frame being rendered.
                    final completer = _controllers[handle]
                        ?.waitUntilFirstFrameRenderedCompleter;
                    if (!(completer?.isCompleted ?? true)) {
                      completer?.complete();
                    }
                    break;
                  }
                default:
                  {
                    break;
                  }
              }
            } catch (exception, stacktrace) {
              debugPrint(exception.toString());
              debugPrint(stacktrace.toString());
            }
          },
        );
}

/// A `SurfaceView` reported by the platform view (surface mode).
class _Surface {
  const _Surface(this.wid, this.width, this.height);

  /// JNI global reference to its `android.view.Surface`.
  final int wid;

  /// Pixel size.
  final int width, height;
}
