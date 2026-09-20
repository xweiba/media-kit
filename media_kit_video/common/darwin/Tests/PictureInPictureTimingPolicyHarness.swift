import Foundation
import CoreMedia
import CoreVideo

@main
private enum PictureInPictureTimingPolicyHarness {
  static func main() {
    repeatedSeekUsesPendingTarget()
    staleFramesCannotCrossSeekGeneration()
    bufferingAndResumeReanchorOnce()
    pauseAndSpeedUseActualRate()
    appSeekWaitsForPlaybackRestart()
    delayedFrameTokensAreRejected()
    pausedSeekRefreshUsesRestartGeneration()
    renderBeforeRestartReplaysCertifiedTarget()
    restartBeforeRenderRejectsRetainedOldFrame()
    prepareDoesNotCommitBeforeEnqueue()
    readinessCallbackCommitsOnce()
    seekingClearAfterRestartRecovers()
    failedSeekRestoresClockImmediately()
    appSeekClearsPendingNativeTarget()
    newSeekInvalidatesPendingRetry()
    coalescedNativeSeeksDoNotLeaveEventCredit()
    settledRenderedTargetCanRelaxLateBoundary()
    immediateDisplayIsASampleAttachment()
    print("PictureInPictureTimingPolicyHarness: passed")
  }

  private static func snapshot(
    _ position: Double,
    paused: Bool = false,
    buffering: Bool = false,
    seeking: Bool = false,
    speed: Double = 1
  ) -> PictureInPictureTimingPolicy.Snapshot {
    .init(
      position: position,
      duration: 120,
      paused: paused,
      buffering: buffering,
      seeking: seeking,
      speed: speed
    )
  }

  private static func repeatedSeekUsesPendingTarget() {
    var policy = PictureInPictureTimingPolicy()
    let first = require(policy.seek(from: 10, by: 15, duration: 120))
    let second = require(policy.seek(from: 10.2, by: 15, duration: 120))
    let third = require(policy.seek(from: 10.3, by: -15, duration: 120))
    expect(first.origin == 10 && first.target == 25, "first seek")
    expect(second.origin == 25 && second.target == 40, "forward accumulation")
    expect(third.origin == 40 && third.target == 25, "backward accumulation")
  }

  private static func staleFramesCannotCrossSeekGeneration() {
    var policy = PictureInPictureTimingPolicy()
    _ = policy.frame(snapshot(10))
    _ = policy.seek(from: 10, by: 30, duration: 120)
    _ = policy.beginDiscontinuity(at: 10)
    expect(!policy.frame(snapshot(10.1)).acceptsFrame, "pre-restart old frame")
    _ = policy.playbackRestarted(snapshot(39.8))
    let recovered = policy.frame(snapshot(39.8))
    expect(recovered.acceptsFrame, "post-seek frame")
    expect(recovered.anchor == 39.8 && recovered.rate == 1, "actual seek anchor")
  }

  private static func bufferingAndResumeReanchorOnce() {
    var policy = PictureInPictureTimingPolicy()
    _ = policy.frame(snapshot(20))
    let stalled = policy.stateChanged(snapshot(20.4, buffering: true))
    expect(stalled.anchor == 20.4 && stalled.rate == 0, "buffer freeze")
    expect(!policy.frame(snapshot(20.4, buffering: true)).acceptsFrame, "buffer frame drop")
    let waiting = policy.stateChanged(snapshot(20.4))
    expect(waiting.rate == 0, "resume waits for media")
    let recovered = policy.frame(snapshot(20.6))
    expect(recovered.anchor == 20.6 && recovered.rate == 1, "buffer recovery anchor")
    let steady = policy.frame(snapshot(20.7))
    expect(steady.anchor == nil && steady.rate == nil, "steady frame has no clock write")
  }

  private static func pauseAndSpeedUseActualRate() {
    var policy = PictureInPictureTimingPolicy()
    _ = policy.frame(snapshot(30))
    let paused = policy.stateChanged(snapshot(30.2, paused: true, speed: 1.5))
    expect(paused.rate == 0, "pause freezes")
    _ = policy.stateChanged(snapshot(30.2, speed: 1.5))
    let resumed = policy.frame(snapshot(30.3, speed: 1.5))
    expect(resumed.anchor == 30.3 && resumed.rate == 1.5, "actual playback rate")
  }

  private static func appSeekWaitsForPlaybackRestart() {
    var policy = PictureInPictureTimingPolicy()
    _ = policy.frame(snapshot(50))
    let seek = policy.beginDiscontinuity(at: 50)
    expect(seek.flush && seek.rate == 0, "app seek flush")
    expect(!policy.frame(snapshot(80)).acceptsFrame, "restart barrier")
    _ = policy.playbackRestarted(snapshot(80))
    let recovered = policy.frame(snapshot(80))
    expect(recovered.acceptsFrame && recovered.anchor == 80, "app seek recovery")
  }

  private static func delayedFrameTokensAreRejected() {
    let gate = PictureInPictureFrameGate()
    let beforeSeek = gate.token
    gate.advance()
    expect(!gate.accepts(beforeSeek), "pre-seek copy rejected")
    let duringSeek = gate.token
    gate.advance()
    expect(!gate.accepts(duringSeek), "pre-restart copy rejected")
    expect(gate.accepts(gate.token), "post-restart copy accepted")
  }

  private static func pausedSeekRefreshUsesRestartGeneration() {
    var policy = PictureInPictureTimingPolicy()
    let gate = PictureInPictureFrameGate()
    _ = policy.frame(snapshot(40, paused: true))
    _ = policy.seek(from: 40, by: 15, duration: 120)
    gate.advance()
    let preRestartToken = gate.token
    _ = policy.beginDiscontinuity(at: 40, preservingPendingSeek: true)
    gate.advance()
    _ = policy.playbackRestarted(snapshot(55, paused: true))
    expect(!gate.accepts(preRestartToken), "paused pre-restart frame rejected")
    let refreshed = policy.frame(snapshot(55, paused: true))
    expect(gate.accepts(gate.token), "paused retained frame generation")
    expect(refreshed.acceptsFrame, "paused retained frame accepted")
    expect(refreshed.anchor == 55 && refreshed.rate == 0, "paused target anchor")
  }

  private static func renderBeforeRestartReplaysCertifiedTarget() {
    var policy = PictureInPictureTimingPolicy()
    var boundary = PictureInPictureRenderBoundary()
    boundary.requireRender(after: 7)
    _ = policy.beginDiscontinuity(at: 10)
    expect(boundary.accepts(8), "post-seek render is certified")
    expect(!policy.prepareFrame(snapshot(25)).acceptsFrame, "restart barrier")
    _ = policy.playbackRestarted(snapshot(25, paused: true))
    let replay = policy.prepareFrame(snapshot(25, paused: true))
    expect(replay.acceptsFrame && replay.anchor == 25, "certified retained replay")
  }

  private static func restartBeforeRenderRejectsRetainedOldFrame() {
    var policy = PictureInPictureTimingPolicy()
    var boundary = PictureInPictureRenderBoundary()
    boundary.requireRender(after: 11)
    _ = policy.beginDiscontinuity(at: 30)
    _ = policy.playbackRestarted(snapshot(45))
    expect(!boundary.accepts(11), "old retained render rejected")
    expect(boundary.accepts(12), "subsequent render accepted")
    expect(policy.prepareFrame(snapshot(45)).acceptsFrame, "subsequent target frame")
  }

  private static func coalescedNativeSeeksDoNotLeaveEventCredit() {
    var tracker = PictureInPictureNativeSeekTracker()
    tracker.issued()
    tracker.issued()
    expect(tracker.pending, "repeated native seeks share one pending operation")
    tracker.playbackRestarted()
    expect(!tracker.pending, "restart clears coalesced native seek")
    tracker.issued()
    tracker.failed()
    expect(!tracker.pending, "failed native seek clears pending operation")
  }

  private static func settledRenderedTargetCanRelaxLateBoundary() {
    var boundary = PictureInPictureRenderBoundary()
    boundary.requireRender(after: 12)
    expect(!boundary.accepts(12), "late observer initially excludes current render")
    boundary.allowRendered(12)
    expect(boundary.accepts(12), "certified target render can be replayed")
    expect(!boundary.accepts(11), "older retained render remains excluded")
  }

  private static func prepareDoesNotCommitBeforeEnqueue() {
    var policy = PictureInPictureTimingPolicy()
    _ = policy.beginDiscontinuity(at: 15)
    _ = policy.playbackRestarted(snapshot(30))
    let notReady = policy.prepareFrame(snapshot(30))
    expect(notReady.anchor == 30 && notReady.rate == 1, "candidate prepared")
    let retry = policy.prepareFrame(snapshot(30))
    expect(retry.anchor == 30 && retry.rate == 1, "not-ready does not commit")
    _ = policy.commitFrame(snapshot(30))
    let steady = policy.prepareFrame(snapshot(30.1))
    expect(steady.anchor == nil && steady.rate == nil, "enqueue commits once")
  }

  private static func readinessCallbackCommitsOnce() {
    var policy = PictureInPictureTimingPolicy()
    _ = policy.beginDiscontinuity(at: 5)
    _ = policy.playbackRestarted(snapshot(20, paused: true))
    var pending: PictureInPictureTimingPolicy.Snapshot? = snapshot(20, paused: true)
    var enqueueCount = 0
    for _ in 0..<2 {
      guard let candidate = pending else { continue }
      pending = nil
      _ = policy.commitFrame(candidate)
      enqueueCount += 1
    }
    expect(enqueueCount == 1, "readiness callback enqueues retained sample once")
    expect(
      policy.prepareFrame(snapshot(20, paused: true)).anchor == nil,
      "readiness callback commits recovery"
    )
  }

  private static func seekingClearAfterRestartRecovers() {
    var policy = PictureInPictureTimingPolicy()
    _ = policy.beginDiscontinuity(at: 20)
    _ = policy.playbackRestarted(snapshot(35, seeking: true))
    expect(!policy.prepareFrame(snapshot(35, seeking: true)).acceptsFrame, "seeking frame rejected")
    _ = policy.stateChanged(snapshot(35, seeking: false))
    let recovered = policy.prepareFrame(snapshot(35, seeking: false))
    expect(recovered.acceptsFrame && recovered.anchor == 35, "seeking clear recovers")
  }

  private static func failedSeekRestoresClockImmediately() {
    var policy = PictureInPictureTimingPolicy()
    _ = policy.frame(snapshot(60, speed: 1.5))
    _ = policy.seek(from: 60, by: 15, duration: 120)
    _ = policy.beginDiscontinuity(at: 60, preservingPendingSeek: true)
    let recovered = policy.recoverFailedSeek(with: snapshot(60.2, speed: 1.5))
    expect(recovered.anchor == 60.2 && recovered.rate == 1.5, "playing seek failure")

    _ = policy.seek(from: 60.2, by: 15, duration: 120)
    _ = policy.beginDiscontinuity(at: 60.2, preservingPendingSeek: true)
    let paused = policy.recoverFailedSeek(with: snapshot(60.2, paused: true, speed: 1.5))
    expect(paused.anchor == 60.2 && paused.rate == 0, "paused seek failure")
  }

  private static func appSeekClearsPendingNativeTarget() {
    var policy = PictureInPictureTimingPolicy()
    _ = policy.seek(from: 10, by: 15, duration: 120)
    _ = policy.beginDiscontinuity(at: 70)
    let next = require(policy.seek(from: 70, by: 15, duration: 120))
    expect(next.origin == 70 && next.target == 85, "app seek supersedes native target")
  }

  private static func newSeekInvalidatesPendingRetry() {
    let gate = PictureInPictureFrameGate()
    let retainedGeneration = gate.token
    gate.advance()
    expect(!gate.accepts(retainedGeneration), "new seek invalidates retained sample")
  }

  private static func immediateDisplayIsASampleAttachment() {
    var pixelBuffer: CVPixelBuffer?
    expect(
      CVPixelBufferCreate(
        kCFAllocatorDefault,
        2,
        2,
        kCVPixelFormatType_32BGRA,
        nil,
        &pixelBuffer
      ) == kCVReturnSuccess,
      "pixel buffer"
    )
    var format: CMVideoFormatDescription?
    expect(
      CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: require(pixelBuffer),
        formatDescriptionOut: &format
      ) == noErr,
      "format description"
    )
    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: .zero,
      decodeTimeStamp: .invalid
    )
    var sample: CMSampleBuffer?
    expect(
      CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: require(pixelBuffer),
        formatDescription: require(format),
        sampleTiming: &timing,
        sampleBufferOut: &sample
      ) == noErr,
      "sample buffer"
    )
    let readySample = require(sample)
    PictureInPictureSampleBuffer.configureForImmediateDisplay(readySample)
    let attachments = require(
      CMSampleBufferGetSampleAttachmentsArray(
        readySample,
        createIfNecessary: false
      )
    )
    let dictionary = unsafeBitCast(
      CFArrayGetValueAtIndex(attachments, 0),
      to: CFDictionary.self
    )
    expect(
      CFDictionaryContainsKey(
        dictionary,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque()
      ),
      "display-immediate sample attachment"
    )
  }

  private static func require<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
    guard let value else {
      fatalError("unexpected nil", file: file, line: line)
    }
    return value
  }

  private static func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard condition() else {
      fatalError(message, file: file, line: line)
    }
  }
}
