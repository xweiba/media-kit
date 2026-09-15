import AVFoundation
import AVKit
import CoreMedia
import CoreVideo

#if SWIFT_PACKAGE
  import Mpv
#endif

/// 把 mpv 已渲染的同一像素帧送入 macOS 系统画中画，不创建第二播放器或网络请求。
@available(macOS 12.0, *)
final class PictureInPictureRenderer: NSObject,
  AVPictureInPictureSampleBufferPlaybackDelegate,
  AVPictureInPictureControllerDelegate
{
  private var handle: OpaquePointer?
  private let handleLock = NSLock()
  private let stateCallback: (String, [String: Any]?) -> Void
  private let presentationOwnershipCallback: (Bool) -> Void
  private let displayLayer = AVSampleBufferDisplayLayer()
  private let captureLock = NSLock()
  private var pictureInPicturePossibleObservation: NSKeyValueObservation?
  private var captureRequested = false
  private var startRequested = false
  private var requestGeneration = 0
  private var cachedDuration = 0.0
  private var cachedPaused = false
  private var presentationOwned = false
  private var cachedFormatDescription: CMVideoFormatDescription?
  private lazy var controller: AVPictureInPictureController = {
    let source = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: displayLayer,
      playbackDelegate: self
    )
    let controller = AVPictureInPictureController(contentSource: source)
    controller.delegate = self
    controller.requiresLinearPlayback = false
    return controller
  }()

  init(
    handle: OpaquePointer,
    stateCallback: @escaping (String, [String: Any]?) -> Void,
    presentationOwnershipCallback: @escaping (Bool) -> Void
  ) {
    self.handle = handle
    self.stateCallback = stateCallback
    self.presentationOwnershipCallback = presentationOwnershipCallback
    super.init()
    displayLayer.videoGravity = .resizeAspect
  }

  /// VideoOutput must invalidate the renderer before releasing the mpv core.
  /// AVKit may deliver delegate callbacks after disposal, so those callbacks
  /// fall back to the cached state instead of dereferencing a stale handle.
  func invalidate() {
    dispatchPrecondition(condition: .onQueue(.main))
    requestGeneration += 1
    startRequested = false
    setCaptureRequested(false)
    pictureInPicturePossibleObservation?.invalidate()
    pictureInPicturePossibleObservation = nil
    if controller.isPictureInPictureActive {
      controller.stopPictureInPicture()
    }
    controller.delegate = nil
    handleLock.lock()
    handle = nil
    handleLock.unlock()
    displayLayer.flushAndRemoveImage()
  }

  /// 仅在准备或显示 PiP 时复制 mpv 像素帧，避免普通播放长期承担额外内存带宽。
  var shouldCaptureFrame: Bool {
    captureLock.lock()
    defer { captureLock.unlock() }
    return captureRequested
  }

  /// 系统 PiP 活跃时由 display layer 独占呈现，Flutter 无需同步合成同一帧。
  var ownsPresentation: Bool {
    captureLock.lock()
    defer { captureLock.unlock() }
    return presentationOwned
  }

  func enqueue(_ pixelBuffer: CVPixelBuffer) {
    guard shouldCaptureFrame else { return }
    guard let description = formatDescription(for: pixelBuffer) else { return }
    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
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
  }

  func start() -> Bool {
    dispatchPrecondition(condition: .onQueue(.main))
    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      reportFailure(domain: "AVPictureInPictureController", code: -1)
      return false
    }
    if controller.isPictureInPictureActive || startRequested {
      return true
    }
    requestGeneration += 1
    let generation = requestGeneration
    startRequested = true
    setCaptureRequested(true)
    observePictureInPicturePossibility()
    stateCallback("starting", nil)
    startWhenReady()
    // ContentSource 收到首个 sample 后才可能启动；超时必须撤销帧复制，
    // 避免系统拒绝 PiP 后继续承担无意义的内存带宽。
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
    stateCallback("stopped", nil)
    return true
  }

  private func startWhenReady() {
    dispatchPrecondition(condition: .onQueue(.main))
    guard startRequested, controller.isPictureInPicturePossible else { return }
    startRequested = false
    controller.startPictureInPicture()
  }

  private func observePictureInPicturePossibility() {
    guard pictureInPicturePossibleObservation == nil else { return }
    pictureInPicturePossibleObservation = controller.observe(
      \.isPictureInPicturePossible,
      options: [.initial, .new]
    ) { [weak self] _, change in
      guard change.newValue == true else { return }
      let start: () -> Void = { [weak self] in self?.startWhenReady() }
      if Thread.isMainThread {
        start()
      } else {
        DispatchQueue.main.async(execute: start)
      }
    }
  }

  private func formatDescription(
    for pixelBuffer: CVPixelBuffer
  ) -> CMVideoFormatDescription? {
    if let cachedFormatDescription,
      CMVideoFormatDescriptionMatchesImageBuffer(
        cachedFormatDescription,
        imageBuffer: pixelBuffer
      )
    {
      return cachedFormatDescription
    }
    var description: CMVideoFormatDescription?
    guard
      CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &description
      ) == noErr,
      let description
    else { return nil }
    cachedFormatDescription = description
    return description
  }

  private func setCaptureRequested(_ value: Bool) {
    captureLock.lock()
    captureRequested = value
    captureLock.unlock()
  }

  private func setPresentationOwned(_ value: Bool) {
    captureLock.lock()
    let changed = presentationOwned != value
    presentationOwned = value
    captureLock.unlock()
    if changed { presentationOwnershipCallback(value) }
  }

  private func reportFailure(domain: String, code: Int) {
    requestGeneration += 1
    startRequested = false
    setCaptureRequested(false)
    stateCallback("failed", ["domain": domain, "code": code])
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    setPresentationOwned(true)
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
    setPresentationOwned(false)
    stateCallback("stopped", nil)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {
    handleLock.lock()
    cachedPaused = !playing
    if let handle {
      var paused: Int32 = playing ? 0 : 1
      mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &paused)
    }
    handleLock.unlock()
    controller.invalidatePlaybackState()
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    handleLock.lock()
    defer { handleLock.unlock() }
    guard let handle else { return cachedPaused }
    var paused: Int32 = cachedPaused ? 1 : 0
    mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &paused)
    cachedPaused = paused != 0
    return cachedPaused
  }

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    handleLock.lock()
    var duration = cachedDuration
    if let handle {
      mpv_get_property(handle, "duration", MPV_FORMAT_DOUBLE, &duration)
      if duration.isFinite && duration > 0 {
        cachedDuration = duration
      }
    }
    handleLock.unlock()
    if duration.isFinite && duration > 0 {
      return CMTimeRange(
        start: .zero,
        duration: CMTime(seconds: duration, preferredTimescale: 600)
      )
    }
    return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion: @escaping () -> Void
  ) {
    let seconds = CMTimeGetSeconds(skipInterval)
    let command = "seek \(seconds) relative+exact"
    handleLock.lock()
    if let handle {
      command.withCString { value in
        _ = mpv_command_string(handle, value)
      }
    }
    handleLock.unlock()
    completion()
    controller.invalidatePlaybackState()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}
}
