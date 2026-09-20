import Foundation
import Mpv

@main
private enum PictureInPictureStateObserverHarness {
  static func main() {
    let handle = require(mpv_create())
    expect(setOption(handle, "idle", "yes") >= 0, "set idle")
    expect(setOption(handle, "terminal", "no") >= 0, "disable terminal")
    expect(mpv_initialize(handle) >= 0, "initialize mpv")

    initialPropertyEventsAndCancellation(handle)
    cancelBeforeThreadStarts(handle)
    repeatedLifecycle(handle)
    shutdownEndsObserver(handle)
    print("PictureInPictureStateObserverHarness: passed")
  }

  private static func initialPropertyEventsAndCancellation(_ handle: OpaquePointer) {
    let event = DispatchSemaphore(value: 0)
    let terminated = DispatchSemaphore(value: 0)
    let observer = require(
      PictureInPictureStateObserver(
        handle: handle,
        callback: { if case .stateChanged = $0 { event.signal() } },
        terminationCallback: { terminated.signal() }
      )
    )
    wait(event, "initial property event")
    observer.cancel()
    wait(terminated, "observer cancellation")
  }

  private static func cancelBeforeThreadStarts(_ handle: OpaquePointer) {
    let terminated = DispatchSemaphore(value: 0)
    let observer = require(
      PictureInPictureStateObserver(
        handle: handle,
        startsImmediately: false,
        callback: { _ in },
        terminationCallback: { terminated.signal() }
      )
    )
    observer.cancel()
    observer.start()
    wait(terminated, "cancel before thread start")
  }

  private static func repeatedLifecycle(_ handle: OpaquePointer) {
    for index in 0..<8 {
      let terminated = DispatchSemaphore(value: 0)
      let observer = require(
        PictureInPictureStateObserver(
          handle: handle,
          callback: { _ in },
          terminationCallback: { terminated.signal() }
        )
      )
      observer.cancel()
      observer.cancel()
      wait(terminated, "repeated lifecycle \(index)")
    }
  }

  private static func shutdownEndsObserver(_ handle: OpaquePointer) {
    let terminated = DispatchSemaphore(value: 0)
    let observer = require(
      PictureInPictureStateObserver(
        handle: handle,
        callback: { _ in },
        terminationCallback: { terminated.signal() }
      )
    )
    expect(command(handle, "quit") >= 0, "request shutdown")
    wait(terminated, "shutdown observer")
    observer.cancel()
    observer.cancel()
    mpv_destroy(handle)
  }

  private static func setOption(
    _ handle: OpaquePointer,
    _ name: String,
    _ value: String
  ) -> Int32 {
    name.withCString { namePointer in
      value.withCString { valuePointer in
        mpv_set_option_string(handle, namePointer, valuePointer)
      }
    }
  }

  private static func command(_ handle: OpaquePointer, _ value: String) -> Int32 {
    value.withCString { mpv_command_string(handle, $0) }
  }

  private static func wait(_ semaphore: DispatchSemaphore, _ message: String) {
    expect(semaphore.wait(timeout: .now() + 3) == .success, message)
  }

  private static func require<T>(
    _ value: T?,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> T {
    guard let value else { fatalError("unexpected nil", file: file, line: line) }
    return value
  }

  private static func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard condition() else { fatalError(message, file: file, line: line) }
  }
}
