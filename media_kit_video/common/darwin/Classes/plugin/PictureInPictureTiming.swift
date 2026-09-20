import CoreMedia
import Foundation

/// State transition policy shared by the iOS and macOS sample-buffer PiP paths.
struct PictureInPictureTimingPolicy {
  struct Snapshot {
    var position: Double
    var duration: Double
    var paused: Bool
    var buffering: Bool
    var seeking: Bool
    var speed: Double

    var effectiveRate: Double {
      guard !paused, !buffering, !seeking, speed.isFinite, speed > 0 else {
        return 0
      }
      return speed
    }
  }

  struct Decision {
    var acceptsFrame = true
    var flush = false
    var anchor: Double?
    var rate: Double?
  }

  private(set) var pendingSeekTarget: Double?
  private var waitingForStableFrame = true
  private var restartObserved = true
  private var lastPresentedPosition: Double?
  private var lastEffectiveRate: Double?

  mutating func seek(
    from currentPosition: Double,
    by offset: Double,
    duration: Double
  ) -> (origin: Double, target: Double)? {
    guard currentPosition.isFinite, offset.isFinite else { return nil }
    let origin = pendingSeekTarget ?? currentPosition
    var target = max(0, origin + offset)
    if duration.isFinite && duration > 0 { target = min(target, duration) }
    guard target.isFinite else { return nil }
    pendingSeekTarget = target
    waitingForStableFrame = true
    restartObserved = false
    lastEffectiveRate = 0
    return (origin, target)
  }

  mutating func beginDiscontinuity(
    at position: Double,
    preservingPendingSeek: Bool = false
  ) -> Decision {
    if !preservingPendingSeek { pendingSeekTarget = nil }
    waitingForStableFrame = true
    restartObserved = false
    lastEffectiveRate = 0
    return Decision(
      acceptsFrame: false,
      flush: true,
      anchor: validPosition(position),
      rate: 0
    )
  }

  mutating func recoverFailedSeek(with snapshot: Snapshot) -> Decision {
    pendingSeekTarget = nil
    waitingForStableFrame = snapshot.effectiveRate == 0
    restartObserved = true
    lastPresentedPosition = validPosition(snapshot.position)
    lastEffectiveRate = snapshot.effectiveRate
    return Decision(
      anchor: validPosition(snapshot.position),
      rate: snapshot.effectiveRate
    )
  }

  mutating func stateChanged(_ snapshot: Snapshot) -> Decision {
    guard let position = validPosition(snapshot.position) else {
      return Decision(acceptsFrame: false)
    }
    if snapshot.seeking {
      waitingForStableFrame = true
      lastEffectiveRate = 0
      return Decision(acceptsFrame: false, anchor: position, rate: 0)
    }
    if snapshot.paused || snapshot.buffering {
      waitingForStableFrame = true
      lastEffectiveRate = 0
      return Decision(anchor: position, rate: 0)
    }
    if lastEffectiveRate == 0 || lastEffectiveRate != snapshot.effectiveRate {
      waitingForStableFrame = true
      lastEffectiveRate = 0
      return Decision(rate: 0)
    }
    return Decision()
  }

  mutating func playbackRestarted(_ snapshot: Snapshot) -> Decision {
    restartObserved = true
    return stateChanged(snapshot)
  }

  func prepareFrame(_ snapshot: Snapshot) -> Decision {
    guard let position = validPosition(snapshot.position) else {
      return Decision(acceptsFrame: false)
    }
    if !restartObserved || snapshot.seeking || snapshot.buffering {
      return Decision(acceptsFrame: false)
    }
    let jumped = lastPresentedPosition.map { previous in
      position < previous - 0.25 || position > previous + 2.0
    } ?? false
    let needsAnchor = waitingForStableFrame || jumped
    return Decision(
      flush: jumped,
      anchor: needsAnchor ? position : nil,
      rate: needsAnchor ? snapshot.effectiveRate : nil
    )
  }

  mutating func commitFrame(_ snapshot: Snapshot) -> Decision {
    let decision = prepareFrame(snapshot)
    guard decision.acceptsFrame,
      let position = validPosition(snapshot.position)
    else { return decision }
    pendingSeekTarget = nil
    waitingForStableFrame = false
    lastPresentedPosition = position
    lastEffectiveRate = snapshot.effectiveRate
    return decision
  }

  /// Convenience for callers that can guarantee immediate presentation.
  mutating func frame(_ snapshot: Snapshot) -> Decision {
    commitFrame(snapshot)
  }

  private func validPosition(_ value: Double) -> Double? {
    value.isFinite && value >= 0 ? value : nil
  }
}

/// Monotonic proof that a retained texture was rendered after a discontinuity.
final class PictureInPictureRenderSerial {
  private let lock = NSLock()
  private var value: UInt64 = 0

  var current: UInt64 {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func completeRender() -> UInt64 {
    lock.lock()
    value &+= 1
    let result = value
    lock.unlock()
    return result
  }
}

struct PictureInPictureRenderBoundary {
  private(set) var minimumSerial: UInt64 = 0

  mutating func requireRender(after serial: UInt64) {
    minimumSerial = serial == UInt64.max ? serial : serial + 1
  }

  mutating func reset() {
    minimumSerial = 0
  }

  mutating func allowRendered(_ serial: UInt64) {
    minimumSerial = min(minimumSerial, serial)
  }

  func accepts(_ serial: UInt64) -> Bool {
    serial >= minimumSerial
  }
}

/// Tracks one logical native seek until mpv reports playback restart. Repeated
/// requests may coalesce into one SEEK event, so event-counting is invalid.
struct PictureInPictureNativeSeekTracker {
  private(set) var pending = false

  mutating func issued() {
    pending = true
  }

  mutating func failed() {
    pending = false
  }

  mutating func playbackRestarted() {
    pending = false
  }
}

final class PictureInPictureFrameGate {
  private let lock = NSLock()
  private var generation: UInt64 = 0

  var token: UInt64 {
    lock.lock()
    defer { lock.unlock() }
    return generation
  }

  func advance() {
    lock.lock()
    generation &+= 1
    lock.unlock()
  }

  func accepts(_ token: UInt64) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return token == generation
  }
}

enum PictureInPictureSampleBuffer {
  static func configureForImmediateDisplay(_ sample: CMSampleBuffer) {
    guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
      sample,
      createIfNecessary: true
    ), CFArrayGetCount(attachments) > 0 else { return }
    let dictionary = unsafeBitCast(
      CFArrayGetValueAtIndex(attachments, 0),
      to: CFMutableDictionary.self
    )
    CFDictionarySetValue(
      dictionary,
      Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
      Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
    )
  }
}
