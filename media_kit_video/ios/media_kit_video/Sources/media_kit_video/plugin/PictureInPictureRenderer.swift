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
  private let displayLayer = AVSampleBufferDisplayLayer()
  private let captureLock = NSLock()
  private var playbackTimebase: CMTimebase?
  private var pictureInPicturePossibleObservation: NSKeyValueObservation?
  private weak var hostLayer: CALayer?
  private var captureRequested = false
  private var startRequested = false
  private var requestGeneration = 0
  private var cachedPosition = 0.0
  private var cachedDuration = 0.0
  private var cachedPaused = false
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
    configurePlaybackTimebase()
  }

  deinit {
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
    let position = readPlaybackState().position
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
    syncPlaybackTimebase()
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
    syncPlaybackTimebase()
  }

  private func syncPlaybackTimebase(position suppliedPosition: CMTime? = nil) {
    guard let playbackTimebase else { return }
    let state = readPlaybackState()
    let time = suppliedPosition ?? (
      state.position.isFinite && state.position >= 0
        ? CMTime(seconds: state.position, preferredTimescale: 600)
        : .zero
    )
    CMTimebaseSetTime(playbackTimebase, time: time)
    CMTimebaseSetRate(playbackTimebase, rate: state.paused ? 0 : 1)
  }

  private func readPlaybackState() -> (position: Double, duration: Double, paused: Bool) {
    handleLock.lock()
    defer { handleLock.unlock() }
    guard let handle else {
      return (cachedPosition, cachedDuration, cachedPaused)
    }
    var position = cachedPosition
    var duration = cachedDuration
    var paused: Int32 = cachedPaused ? 1 : 0
    mpv_get_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &position)
    mpv_get_property(handle, "duration", MPV_FORMAT_DOUBLE, &duration)
    mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &paused)
    if position.isFinite && position >= 0 { cachedPosition = position }
    if duration.isFinite && duration > 0 { cachedDuration = duration }
    cachedPaused = paused != 0
    return (cachedPosition, cachedDuration, cachedPaused)
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
      options: [.new]
    ) { [weak self] _, change in
      guard change.newValue == true else { return }
      DispatchQueue.main.async { [weak self] in
        self?.startWhenReady()
      }
    }
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
    handleLock.lock()
    cachedPaused = !playing
    if let handle {
      var paused: Int32 = playing ? 0 : 1
      mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &paused)
    }
    handleLock.unlock()
    syncPlaybackTimebase()
    pictureInPictureController.invalidatePlaybackState()
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    readPlaybackState().paused
  }

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    let duration = readPlaybackState().duration
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
    let state = readPlaybackState()
    let position = state.position
    let duration = state.duration
    let offset = CMTimeGetSeconds(skipInterval)
    guard position.isFinite, offset.isFinite else {
      completion()
      return
    }
    var target = max(0, position + offset)
    if duration.isFinite && duration > 0 {
      target = min(target, duration)
    }
    handleLock.lock()
    cachedPosition = target
    if let handle {
      mpv_set_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &target)
    }
    handleLock.unlock()
    syncPlaybackTimebase(
      position: CMTime(seconds: target, preferredTimescale: 600)
    )
    pictureInPictureController.invalidatePlaybackState()
    completion()
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
