import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import UIKit

#if SWIFT_PACKAGE
  import Mpv
#endif

/// 把 mpv 已渲染的同一像素帧送入系统 PiP，不创建第二个播放器或网络请求。
@available(iOS 15.0, *)
final class PictureInPictureRenderer: NSObject,
  AVPictureInPictureSampleBufferPlaybackDelegate,
  AVPictureInPictureControllerDelegate
{
  private var handle: OpaquePointer?
  private let handleLock = NSLock()
  private let stateCallback: (String, [String: Any]?) -> Void
  private let presentationOwnershipCallback: (Bool) -> Void
  private let renderBoundaryCallback: () -> UInt64
  private let postDiscontinuityFrameCallback: () -> Void
  private let displayLayer = AVSampleBufferDisplayLayer()
  private let captureLock = NSLock()
  private let presentationLock = NSLock()
  private let mediaDataQueue = DispatchQueue(
    label: "com.alexmercerind.media_kit_video.pip.samples"
  )
  private var playbackTimebase: CMTimebase?
  private var stateObserver: PictureInPictureStateObserver?
  private var stateObserverEpoch: UInt64 = 0
  private var timingPolicy = PictureInPictureTimingPolicy()
  private var pictureInPicturePossibleObservation: NSKeyValueObservation?
  private weak var hostLayer: CALayer?
  private var captureRequested = false
  private let frameGate = PictureInPictureFrameGate()
  private var renderBoundary = PictureInPictureRenderBoundary()
  private var nativeSeek = PictureInPictureNativeSeekTracker()
  private var awaitingRestartReplay = false
  private var pendingSample: PendingSample?
  private var readinessRequestActive = false
  private var startRequested = false
  private var requestGeneration = 0
  private var cachedPosition = 0.0
  private var cachedDuration = 0.0
  private var cachedPaused = false
  private var cachedBuffering = false
  private var cachedCoreIdle = false
  private var cachedSeeking = false
  private var cachedSpeed = 1.0
  private var presentationOwned = false
  private var cachedFormatDescription: CMVideoFormatDescription?
  private struct PendingSample {
    let sample: CMSampleBuffer
    let snapshot: PictureInPictureTimingPolicy.Snapshot
    let generation: UInt64
    let renderSerial: UInt64
  }
  private struct PresentedFrame {
    let position: Double
    let renderSerial: UInt64
  }
  private var lastPresentedFrame: PresentedFrame?
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
    stateCallback: @escaping (String, [String: Any]?) -> Void,
    presentationOwnershipCallback: @escaping (Bool) -> Void,
    renderBoundaryCallback: @escaping () -> UInt64,
    postDiscontinuityFrameCallback: @escaping () -> Void
  ) {
    self.handle = handle
    self.stateCallback = stateCallback
    self.presentationOwnershipCallback = presentationOwnershipCallback
    self.renderBoundaryCallback = renderBoundaryCallback
    self.postDiscontinuityFrameCallback = postDiscontinuityFrameCallback
    super.init()
    displayLayer.videoGravity = .resizeAspect
    configurePlaybackTimebase()
  }

  deinit {
    stateObserver?.cancel()
    displayLayer.stopRequestingMediaData()
    pictureInPicturePossibleObservation?.invalidate()
    if Thread.isMainThread {
      displayLayer.removeFromSuperlayer()
    } else {
      let layer = displayLayer
      DispatchQueue.main.async { layer.removeFromSuperlayer() }
    }
  }

  /// VideoOutput 必须在 mpv core 销毁前调用。AVKit 的 delegate 回调可能比
  /// Player.dispose 晚到；清空 handle 并撤销 controller 后，任何晚到回调都只读
  /// 最后一份播放状态，不再访问已经释放的 mpv 指针。
  func invalidate() {
    dispatchPrecondition(condition: .onQueue(.main))
    requestGeneration += 1
    startRequested = false
    setCaptureRequested(false)
    stopStateObserver()
    pictureInPicturePossibleObservation?.invalidate()
    pictureInPicturePossibleObservation = nil
    if controller.isPictureInPictureActive {
      controller.stopPictureInPicture()
    }
    controller.canStartPictureInPictureAutomaticallyFromInline = false
    controller.delegate = nil
    handleLock.lock()
    handle = nil
    handleLock.unlock()
    detachDisplayLayer()
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

  /// Token captured before copying a pixel buffer. Discontinuities invalidate
  /// in-flight copies before they can reach the sample queue.
  var captureGeneration: UInt64 {
    frameGate.token
  }

  func enqueue(
    _ pixelBuffer: CVPixelBuffer,
    generation: UInt64,
    renderSerial: UInt64
  ) {
    guard shouldCaptureFrame else { return }
    guard let description = formatDescription(for: pixelBuffer) else { return }
    let snapshot = readFrameSnapshot()
    let presentationTime = CMTime(seconds: snapshot.position, preferredTimescale: 600)
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
    PictureInPictureSampleBuffer.configureForImmediateDisplay(sample)
    presentationLock.lock()
    defer { presentationLock.unlock() }
    enqueueLocked(
      PendingSample(
        sample: sample,
        snapshot: snapshot,
        generation: generation,
        renderSerial: renderSerial
      )
    )
  }

  private func enqueueLocked(_ candidate: PendingSample) {
    guard frameGate.accepts(candidate.generation),
      renderBoundary.accepts(candidate.renderSerial)
    else { return }
    let decision = timingPolicy.prepareFrame(candidate.snapshot)
    guard decision.acceptsFrame else { return }
    if displayLayer.status == .failed {
      displayLayer.flushAndRemoveImage()
    }
    guard displayLayer.isReadyForMoreMediaData else {
      pendingSample = candidate
      requestMediaDataWhenReadyLocked()
      return
    }
    pendingSample = nil
    stopRequestingMediaDataLocked()
    if decision.flush { displayLayer.flushAndRemoveImage() }
    displayLayer.enqueue(candidate.sample)
    lastPresentedFrame = PresentedFrame(
      position: candidate.snapshot.position,
      renderSerial: candidate.renderSerial
    )
    let committed = timingPolicy.commitFrame(candidate.snapshot)
    awaitingRestartReplay = false
    apply(committed, allowingFlush: false)
  }

  private func requestMediaDataWhenReadyLocked() {
    guard !readinessRequestActive else { return }
    readinessRequestActive = true
    displayLayer.requestMediaDataWhenReady(on: mediaDataQueue) { [weak self] in
      self?.drainPendingSample()
    }
  }

  private func drainPendingSample() {
    presentationLock.lock()
    guard let candidate = pendingSample else {
      stopRequestingMediaDataLocked()
      presentationLock.unlock()
      return
    }
    guard frameGate.accepts(candidate.generation),
      renderBoundary.accepts(candidate.renderSerial)
    else {
      pendingSample = nil
      stopRequestingMediaDataLocked()
      presentationLock.unlock()
      return
    }
    guard displayLayer.isReadyForMoreMediaData else {
      presentationLock.unlock()
      return
    }
    pendingSample = nil
    stopRequestingMediaDataLocked()
    enqueueLocked(candidate)
    presentationLock.unlock()
  }

  private func stopRequestingMediaDataLocked() {
    guard readinessRequestActive else { return }
    displayLayer.stopRequestingMediaData()
    readinessRequestActive = false
  }

  private func discardPendingSampleLocked() {
    pendingSample = nil
    stopRequestingMediaDataLocked()
  }

  private func updatePendingSampleStateLocked(
    with snapshot: PictureInPictureTimingPolicy.Snapshot
  ) {
    guard let pendingSample else { return }
    var current = snapshot
    current.position = pendingSample.snapshot.position
    self.pendingSample = PendingSample(
      sample: pendingSample.sample,
      snapshot: current,
      generation: pendingSample.generation,
      renderSerial: pendingSample.renderSerial
    )
  }

  func start() -> Bool {
    dispatchPrecondition(condition: .onQueue(.main))
    guard prepare() else { return false }
    if controller.isPictureInPictureActive || startRequested {
      return true
    }
    requestGeneration += 1
    let generation = requestGeneration
    startRequested = true
    stateCallback("starting", nil)
    startWhenReady()
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

  /// 建立并持续喂给系统 PiP 内容源，但不主动显示系统小窗。
  ///
  /// `canStartPictureInPictureAutomaticallyFromInline` 只有在 controller 已创建、
  /// display layer 位于前台窗口且已有帧时才有效。应用内小窗阶段完成这些准备，
  /// 用户离开 App 时系统即可接管，而不会提前替换应用内小窗。
  func prepare() -> Bool {
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
    _ = controller
    observePictureInPicturePossibility()
    ensureStateObserver()
    let snapshot = readPlaybackSnapshot()
    presentationLock.lock()
    apply(timingPolicy.stateChanged(snapshot))
    presentationLock.unlock()
    setCaptureRequested(true)
    return true
  }

  func stop() -> Bool {
    dispatchPrecondition(condition: .onQueue(.main))
    requestGeneration += 1
    if controller.isPictureInPictureActive {
      controller.stopPictureInPicture()
      return true
    }
    guard startRequested || shouldCaptureFrame else { return false }
    startRequested = false
    setCaptureRequested(false)
    stopStateObserver()
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
    // Flutter Texture 才是应用内可见画面。PiP 的 sample-buffer layer 只需属于
    // 可见 UIWindow 图层树；限制为角落 1pt 承载区，避免透明 Flutter 区域透出
    // 第二个全屏视频画面。
    displayLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    layer.insertSublayer(displayLayer, at: 0)
    hostLayer = layer
    return true
  }

  /// Sample PTS、display layer 和 playback delegate 使用同一条影片时间轴。
  /// 只在准备、播放状态或 seek 改变时重同步；逐帧重置会让连续时钟跳变。
  private func configurePlaybackTimebase() {
    var timebase: CMTimebase?
    guard
      CMTimebaseCreateWithSourceClock(
        allocator: kCFAllocatorDefault,
        sourceClock: CMClockGetHostTimeClock(),
        timebaseOut: &timebase
      ) == noErr,
      let timebase
    else { return }
    playbackTimebase = timebase
    displayLayer.controlTimebase = timebase
    let snapshot = readPlaybackSnapshot()
    presentationLock.lock()
    apply(timingPolicy.stateChanged(snapshot))
    presentationLock.unlock()
  }

  private func apply(
    _ decision: PictureInPictureTimingPolicy.Decision,
    allowingFlush: Bool = true
  ) {
    if allowingFlush && decision.flush {
      displayLayer.flushAndRemoveImage()
    }
    guard let playbackTimebase else { return }
    if let anchor = decision.anchor, let rate = decision.rate {
      CMTimebaseSetRateAndAnchorTime(
        playbackTimebase,
        rate: rate,
        anchorTime: CMTime(seconds: anchor, preferredTimescale: 600),
        immediateSourceTime: CMClockGetTime(CMClockGetHostTimeClock())
      )
    } else if let rate = decision.rate {
      CMTimebaseSetRate(playbackTimebase, rate: rate)
    }
  }

  private func readPlaybackSnapshot() -> PictureInPictureTimingPolicy.Snapshot {
    handleLock.lock()
    defer { handleLock.unlock() }
    guard let handle else {
      return cachedSnapshot
    }
    var position = cachedPosition
    var duration = cachedDuration
    var paused: Int32 = cachedPaused ? 1 : 0
    var buffering: Int32 = cachedBuffering ? 1 : 0
    var coreIdle: Int32 = cachedCoreIdle ? 1 : 0
    var seeking: Int32 = cachedSeeking ? 1 : 0
    var speed = cachedSpeed
    mpv_get_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &position)
    mpv_get_property(handle, "duration", MPV_FORMAT_DOUBLE, &duration)
    mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &paused)
    mpv_get_property(handle, "paused-for-cache", MPV_FORMAT_FLAG, &buffering)
    mpv_get_property(handle, "core-idle", MPV_FORMAT_FLAG, &coreIdle)
    mpv_get_property(handle, "seeking", MPV_FORMAT_FLAG, &seeking)
    mpv_get_property(handle, "speed", MPV_FORMAT_DOUBLE, &speed)
    if position.isFinite && position >= 0 { cachedPosition = position }
    if duration.isFinite && duration > 0 { cachedDuration = duration }
    cachedPaused = paused != 0
    cachedCoreIdle = coreIdle != 0
    cachedBuffering = buffering != 0 || (cachedCoreIdle && paused == 0)
    cachedSeeking = seeking != 0
    if speed.isFinite && speed > 0 { cachedSpeed = speed }
    return cachedSnapshot
  }

  private var cachedSnapshot: PictureInPictureTimingPolicy.Snapshot {
    PictureInPictureTimingPolicy.Snapshot(
      position: cachedPosition,
      duration: cachedDuration,
      paused: cachedPaused,
      buffering: cachedBuffering,
      seeking: cachedSeeking,
      speed: cachedSpeed
    )
  }

  /// Render callbacks are frame-paced; only media time is sampled here. The
  /// separate mpv client keeps the slower-changing playback flags current.
  private func readFrameSnapshot() -> PictureInPictureTimingPolicy.Snapshot {
    handleLock.lock()
    defer { handleLock.unlock() }
    if let handle {
      var position = cachedPosition
      if mpv_get_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &position) >= 0,
        position.isFinite, position >= 0
      {
        cachedPosition = position
      }
    }
    return cachedSnapshot
  }

  private func playbackStateChanged(
    _ event: PictureInPictureStateObserver.Event,
    epoch: UInt64
  ) {
    let snapshot = readPlaybackSnapshot()
    presentationLock.lock()
    guard epoch == stateObserverEpoch else {
      presentationLock.unlock()
      return
    }
    let decision: PictureInPictureTimingPolicy.Decision
    switch event {
    case .discontinuity:
      let preservesNativeTarget = nativeSeek.pending
      if preservesNativeTarget {
        // The delegate established this boundary before issuing mpv_set_property.
        // Replacing it here could reject a sole paused target frame.
        decision = timingPolicy.beginDiscontinuity(
          at: snapshot.position,
          preservingPendingSeek: true
        )
      } else {
        let certifiedTargetSerial = certifiedTargetSerial(for: snapshot)
        decision = beginDiscontinuityLocked(
          at: snapshot.position,
          preservingPendingSeek: false
        )
        if let certifiedTargetSerial {
          renderBoundary.allowRendered(certifiedTargetSerial)
        }
      }
    case .playbackRestarted:
      nativeSeek.playbackRestarted()
      advanceCaptureGeneration()
      discardPendingSampleLocked()
      awaitingRestartReplay = true
      decision = timingPolicy.playbackRestarted(snapshot)
    case .stateChanged:
      updatePendingSampleStateLocked(with: snapshot)
      decision = timingPolicy.stateChanged(snapshot)
    }
    apply(decision)
    let isPlaybackRestart: Bool
    if case .playbackRestarted = event {
      isPlaybackRestart = true
    } else {
      isPlaybackRestart = false
    }
    let shouldPrimeRetainedFrame =
      isPlaybackRestart || (awaitingRestartReplay && !snapshot.seeking)
    presentationLock.unlock()
    if shouldPrimeRetainedFrame {
      postDiscontinuityFrameCallback()
    }
  }

  private func ensureStateObserver() {
    guard stateObserver == nil else { return }
    handleLock.lock()
    let currentHandle = handle
    handleLock.unlock()
    guard let currentHandle else { return }
    presentationLock.lock()
    stateObserverEpoch &+= 1
    timingPolicy = PictureInPictureTimingPolicy()
    nativeSeek = PictureInPictureNativeSeekTracker()
    awaitingRestartReplay = false
    renderBoundary.reset()
    discardPendingSampleLocked()
    let epoch = stateObserverEpoch
    presentationLock.unlock()
    stateObserver = PictureInPictureStateObserver(
      handle: currentHandle,
      callback: { [weak self] event in
        self?.playbackStateChanged(event, epoch: epoch)
      }
    )
  }

  private func stopStateObserver() {
    stateObserver?.cancel()
    stateObserver = nil
    presentationLock.lock()
    stateObserverEpoch &+= 1
    timingPolicy = PictureInPictureTimingPolicy()
    nativeSeek = PictureInPictureNativeSeekTracker()
    lastPresentedFrame = nil
    awaitingRestartReplay = false
    renderBoundary.reset()
    discardPendingSampleLocked()
    advanceCaptureGeneration()
    presentationLock.unlock()
  }

  private func advanceCaptureGeneration() {
    frameGate.advance()
  }

  private func beginDiscontinuityLocked(
    at position: Double,
    preservingPendingSeek: Bool
  ) -> PictureInPictureTimingPolicy.Decision {
    advanceCaptureGeneration()
    discardPendingSampleLocked()
    awaitingRestartReplay = false
    let boundary = renderBoundaryCallback()
    renderBoundary.requireRender(after: boundary)
    return timingPolicy.beginDiscontinuity(
      at: position,
      preservingPendingSeek: preservingPendingSeek
    )
  }

  private func certifiedTargetSerial(
    for snapshot: PictureInPictureTimingPolicy.Snapshot
  ) -> UInt64? {
    guard !snapshot.seeking, snapshot.position.isFinite, snapshot.position >= 0 else {
      return nil
    }
    let currentSerial = renderBoundaryCallback()
    let pendingFrame = pendingSample.map {
      PresentedFrame(position: $0.snapshot.position, renderSerial: $0.renderSerial)
    }
    return [pendingFrame, lastPresentedFrame]
      .compactMap { $0 }
      .filter {
        $0.renderSerial == currentSerial && abs($0.position - snapshot.position) <= 0.25
      }
      .map(\.renderSerial)
      .max()
  }

  private func detachDisplayLayer() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.detachDisplayLayer() }
      return
    }
    presentationLock.lock()
    discardPendingSampleLocked()
    displayLayer.flushAndRemoveImage()
    presentationLock.unlock()
    displayLayer.removeFromSuperlayer()
    hostLayer = nil
  }

  private func startWhenReady() {
    dispatchPrecondition(condition: .onQueue(.main))
    if hostLayer != nil {
      displayLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    guard startRequested,
      !controller.isPictureInPictureActive,
      controller.isPictureInPicturePossible
    else { return }
    startRequested = false
    controller.startPictureInPicture()
  }

  /// `isPictureInPicturePossible` 在首个 sample 入队后异步变化。App 进入
  /// inactive 后 mpv 可能不再产生下一帧，因此不能只靠 enqueue 再次检查。
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
    stopStateObserver()
    detachDisplayLayer()
    stateCallback("failed", ["domain": domain, "code": code])
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    setPresentationOwned(true)
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
    setPresentationOwned(false)
    stopStateObserver()
    detachDisplayLayer()
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
    let snapshot = readPlaybackSnapshot()
    presentationLock.lock()
    apply(timingPolicy.stateChanged(snapshot))
    presentationLock.unlock()
    pictureInPictureController.invalidatePlaybackState()
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    readPlaybackSnapshot().paused
  }

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    let duration = readPlaybackSnapshot().duration
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
    defer { completion() }
    let snapshot = readPlaybackSnapshot()
    let offset = CMTimeGetSeconds(skipInterval)
    presentationLock.lock()
    guard let request = timingPolicy.seek(
      from: snapshot.position,
      by: offset,
      duration: snapshot.duration
    ) else {
      presentationLock.unlock()
      return
    }
    nativeSeek.issued()
    apply(
      beginDiscontinuityLocked(
        at: request.origin,
        preservingPendingSeek: true
      )
    )
    presentationLock.unlock()

    stateCallback("seek", [
      "originSeconds": request.origin,
      "targetSeconds": request.target,
    ])
    var target = request.target
    handleLock.lock()
    let result: Int32
    if let handle {
      result = mpv_set_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &target)
    } else {
      result = -1
    }
    handleLock.unlock()
    if result < 0 {
      let current = readPlaybackSnapshot()
      presentationLock.lock()
      nativeSeek.failed()
      renderBoundary.reset()
      awaitingRestartReplay = false
      apply(timingPolicy.recoverFailedSeek(with: current))
      presentationLock.unlock()
      postDiscontinuityFrameCallback()
    }
    pictureInPictureController.invalidatePlaybackState()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
      @escaping (Bool) -> Void
  ) {
    // 系统负责把 App 拉回前台；Flutter 根级 coordinator 随后恢复对应详情页，
    // 并把同一个 PlayerSession 重新嵌入，避免落在无关页面或重新打开媒体。
    completionHandler(true)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}
}
