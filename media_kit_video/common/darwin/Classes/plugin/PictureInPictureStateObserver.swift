import Foundation

#if SWIFT_PACKAGE
  import Mpv
#endif

/// A weak libmpv client with an independent event queue for PiP state changes.
/// Its thread sleeps inside `mpv_wait_event` and is woken explicitly on cancel.
final class PictureInPictureStateObserver {
  enum Event {
    case discontinuity
    case playbackRestarted
    case stateChanged
  }

  private let lock = NSLock()
  private var cancelled = false
  private var started = false
  private var client: OpaquePointer?
  private let callback: (Event) -> Void
  private let terminationCallback: () -> Void

  init?(
    handle: OpaquePointer,
    startsImmediately: Bool = true,
    callback: @escaping (Event) -> Void,
    terminationCallback: @escaping () -> Void = {}
  ) {
    let client = "media_kit_pip".withCString {
      mpv_create_weak_client(handle, $0)
    }
    guard let client else { return nil }
    self.client = client
    self.callback = callback
    self.terminationCallback = terminationCallback

    let properties: [(String, mpv_format)] = [
      ("pause", MPV_FORMAT_FLAG),
      ("paused-for-cache", MPV_FORMAT_FLAG),
      ("core-idle", MPV_FORMAT_FLAG),
      ("seeking", MPV_FORMAT_FLAG),
      ("speed", MPV_FORMAT_DOUBLE),
    ]
    for (index, property) in properties.enumerated() {
      property.0.withCString {
        _ = mpv_observe_property(client, UInt64(index + 1), $0, property.1)
      }
    }
    if startsImmediately { start() }
  }

  func start() {
    lock.lock()
    guard !started, client != nil else {
      lock.unlock()
      return
    }
    started = true
    lock.unlock()
    Thread.detachNewThread { [self] in run() }
  }

  func cancel() {
    lock.lock()
    cancelled = true
    if let client { mpv_wakeup(client) }
    lock.unlock()
  }

  deinit {
    lock.lock()
    let unstartedClient = started ? nil : client
    client = nil
    lock.unlock()
    if let unstartedClient { mpv_destroy(unstartedClient) }
  }

  private func run() {
    lock.lock()
    guard let currentClient = client else {
      lock.unlock()
      return
    }
    lock.unlock()

    while let event = mpv_wait_event(currentClient, -1) {
      lock.lock()
      let shouldStop = cancelled
      lock.unlock()
      if shouldStop || event.pointee.event_id == MPV_EVENT_SHUTDOWN { break }
      switch event.pointee.event_id {
      case MPV_EVENT_SEEK:
        callback(.discontinuity)
      case MPV_EVENT_PLAYBACK_RESTART:
        callback(.playbackRestarted)
      case MPV_EVENT_PROPERTY_CHANGE:
        callback(.stateChanged)
      default:
        break
      }
    }

    lock.lock()
    client = nil
    lock.unlock()
    mpv_destroy(currentClient)
    terminationCallback()
  }
}
