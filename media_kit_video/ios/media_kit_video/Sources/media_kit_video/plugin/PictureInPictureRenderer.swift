import AVFoundation
import AVKit
import CoreMedia
import CoreVideo

#if SWIFT_PACKAGE
  import Mpv
#endif

/// 把 mpv 已渲染的同一像素帧送入系统 PiP，不创建第二个播放器或网络请求。
@available(iOS 15.0, *)
final class PictureInPictureRenderer: NSObject,
  AVPictureInPictureSampleBufferPlaybackDelegate,
  AVPictureInPictureControllerDelegate
{
  private let handle: OpaquePointer
  private let stateCallback: (String, [String: Any]?) -> Void
  private let displayLayer = AVSampleBufferDisplayLayer()
  private let captureLock = NSLock()
  private weak var hostLayer: CALayer?
  private var captureRequested = false
  private var startRequested = false
  private var requestGeneration = 0
  private lazy var controller: AVPictureInPictureController = {
    let source = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: displayLayer,
      playbackDelegate: self
    )
    let controller = AVPictureInPictureController(contentSource: source)
    controller.delegate = self
    controller.canStartPictureInPictureAutomaticallyFromInline = true
    controller.requiresLinearPlayback = false
    return controller
  }()

  init(
    handle: OpaquePointer,
    stateCallback: @escaping (String, [String: Any]?) -> Void
  ) {
    self.handle = handle
    self.stateCallback = stateCallback
    super.init()
    displayLayer.videoGravity = .resizeAspect
  }

  deinit {
    if Thread.isMainThread {
      displayLayer.removeFromSuperlayer()
    } else {
      let layer = displayLayer
      DispatchQueue.main.async { layer.removeFromSuperlayer() }
    }
  }

  /// 仅在准备或显示 PiP 时复制 mpv 像素帧，避免普通播放长期承担额外内存带宽。
  var shouldCaptureFrame: Bool {
    captureLock.lock()
    defer { captureLock.unlock() }
    return captureRequested
  }

  func enqueue(_ pixelBuffer: CVPixelBuffer) {
    guard shouldCaptureFrame else { return }
    var description: CMVideoFormatDescription?
    guard
      CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &description
      ) == noErr,
      let description
    else { return }
    var position = 0.0
    mpv_get_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &position)
    let presentationTime = position.isFinite && position >= 0
      ? CMTime(seconds: position, preferredTimescale: 600)
      : .zero
    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: presentationTime,
      decodeTimeStamp: .invalid
    )
    var sample: CMSampleBuffer?
    guard
      CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescription: description,
        sampleTiming: &timing,
        sampleBufferOut: &sample
      ) == noErr,
      let sample
    else { return }
    if displayLayer.status == .failed {
      displayLayer.flush()
    }
    if displayLayer.isReadyForMoreMediaData {
      displayLayer.enqueue(sample)
    }
    DispatchQueue.main.async { [weak self] in
      self?.startWhenReady()
    }
  }

  func start() -> Bool {
    dispatchPrecondition(condition: .onQueue(.main))
    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      reportFailure(domain: "AVPictureInPictureController", code: -1)
      return false
    }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback)
      try session.setActive(true)
    } catch {
      let error = error as NSError
      reportFailure(domain: error.domain, code: error.code)
      return false
    }
    // `AVPictureInPictureController.ContentSource` 不只需要 sample buffer，承载
    // buffer 的 layer 还必须属于前台 UIWindow 的可见图层树，否则
    // `isPictureInPicturePossible` 会一直保持 false。Flutter 正片仍由上层
    // Texture 展示；该 layer 插在根图层最底部，只作为系统 PiP 的内容源。
    guard attachDisplayLayerToActiveWindow() else {
      reportFailure(domain: "AVPictureInPictureController", code: -3)
      return false
    }
    if controller.isPictureInPictureActive || startRequested {
      return true
    }
    requestGeneration += 1
    let generation = requestGeneration
    startRequested = true
    setCaptureRequested(true)
    stateCallback("starting", nil)
    // ContentSource 只有收到首个 sample 后才会变为 possible，因此等待渲染回调启动。
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
      guard let self,
        self.startRequested,
        self.requestGeneration == generation
      else { return }
      self.reportFailure(domain: "AVPictureInPictureController", code: -2)
    }
    return true
  }

  func stop() -> Bool {
    dispatchPrecondition(condition: .onQueue(.main))
    requestGeneration += 1
    if controller.isPictureInPictureActive {
      controller.stopPictureInPicture()
      return true
    }
    guard startRequested else { return false }
    startRequested = false
    setCaptureRequested(false)
    detachDisplayLayer()
    stateCallback("stopped", nil)
    return true
  }

  private func attachDisplayLayerToActiveWindow() -> Bool {
    if displayLayer.superlayer != nil { return true }
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter {
        $0.activationState == .foregroundActive ||
          $0.activationState == .foregroundInactive
      }
    let window = scenes
      .flatMap(\.windows)
      .first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
    guard let layer = window?.rootViewController?.view.layer else {
      return false
    }
    displayLayer.frame = layer.bounds
    layer.insertSublayer(displayLayer, at: 0)
    hostLayer = layer
    return true
  }

  private func detachDisplayLayer() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.detachDisplayLayer() }
      return
    }
    displayLayer.flushAndRemoveImage()
    displayLayer.removeFromSuperlayer()
    hostLayer = nil
  }

  private func startWhenReady() {
    dispatchPrecondition(condition: .onQueue(.main))
    if let hostLayer {
      displayLayer.frame = hostLayer.bounds
    }
    guard startRequested, controller.isPictureInPicturePossible else { return }
    startRequested = false
    controller.startPictureInPicture()
  }

  private func setCaptureRequested(_ value: Bool) {
    captureLock.lock()
    captureRequested = value
    captureLock.unlock()
  }

  private func reportFailure(domain: String, code: Int) {
    requestGeneration += 1
    startRequested = false
    setCaptureRequested(false)
    detachDisplayLayer()
    stateCallback("failed", ["domain": domain, "code": code])
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    pictureInPictureController.invalidatePlaybackState()
    stateCallback("active", nil)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    let error = error as NSError
    reportFailure(domain: error.domain, code: error.code)
  }

  func pictureInPictureControllerWillStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    stateCallback("stopping", nil)
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    setCaptureRequested(false)
    detachDisplayLayer()
    stateCallback("stopped", nil)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {
    var paused: Int32 = playing ? 0 : 1
    mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &paused)
    pictureInPictureController.invalidatePlaybackState()
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    var paused: Int32 = 0
    mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &paused)
    return paused != 0
  }

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    var duration = 0.0
    mpv_get_property(handle, "duration", MPV_FORMAT_DOUBLE, &duration)
    if duration.isFinite && duration > 0 {
      return CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
    }
    return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion: @escaping () -> Void
  ) {
    var position = 0.0
    var duration = 0.0
    mpv_get_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &position)
    mpv_get_property(handle, "duration", MPV_FORMAT_DOUBLE, &duration)
    let offset = CMTimeGetSeconds(skipInterval)
    guard position.isFinite, offset.isFinite else {
      completion()
      return
    }
    var target = max(0, position + offset)
    if duration.isFinite && duration > 0 {
      target = min(target, duration)
    }
    mpv_set_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &target)
    pictureInPictureController.invalidatePlaybackState()
    completion()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
      @escaping (Bool) -> Void
  ) {
    // Flutter 页面一直保留同一播放器，不需要系统先恢复一层原生全屏界面。
    completionHandler(false)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}
}
