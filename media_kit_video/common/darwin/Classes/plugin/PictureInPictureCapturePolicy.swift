import Foundation

enum PictureInPictureCaptureMode: Equatable {
  case stopped
  case priming
  case fullRate
}

/// Keeps the sample-buffer source warm without copying every foreground frame.
struct PictureInPictureCapturePolicy {
  private(set) var prepared = false
  private(set) var applicationActive = true
  private(set) var explicitStartRequested = false
  private(set) var pictureInPictureActive = false
  private(set) var disposed = false
  private var lastPrimeCaptureTime: TimeInterval?

  let primingInterval: TimeInterval

  init(primingInterval: TimeInterval = 1.0) {
    self.primingInterval = primingInterval
  }

  var mode: PictureInPictureCaptureMode {
    guard prepared, !disposed else { return .stopped }
    if !applicationActive || explicitStartRequested || pictureInPictureActive {
      return .fullRate
    }
    return .priming
  }

  mutating func prepare(applicationActive: Bool) {
    guard !disposed else { return }
    prepared = true
    self.applicationActive = applicationActive
  }

  mutating func setApplicationActive(_ active: Bool) {
    guard !disposed else { return }
    applicationActive = active
  }

  mutating func requestStart() {
    guard prepared, !disposed else { return }
    explicitStartRequested = true
  }

  mutating func setPictureInPictureActive(_ active: Bool) {
    guard !disposed else { return }
    pictureInPictureActive = active
    if active { explicitStartRequested = false }
  }

  mutating func stop() {
    prepared = false
    explicitStartRequested = false
    pictureInPictureActive = false
    lastPrimeCaptureTime = nil
  }

  mutating func dispose() {
    stop()
    disposed = true
  }

  mutating func admitsFrame(at time: TimeInterval) -> Bool {
    switch mode {
    case .stopped:
      return false
    case .fullRate:
      return true
    case .priming:
      guard let lastPrimeCaptureTime else {
        self.lastPrimeCaptureTime = time
        return true
      }
      guard time - lastPrimeCaptureTime >= primingInterval else { return false }
      self.lastPrimeCaptureTime = time
      return true
    }
  }
}
