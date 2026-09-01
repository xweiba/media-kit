import FlutterMacOS

public class Utils: NSObject, UtilsProtocol {
  private let registrar: FlutterPluginRegistrar
  private var transitionObservers: [NSObjectProtocol] = []
  private var transitionTimeout: DispatchWorkItem?

  init(_ registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  private var window: NSWindow? {
    registrar.view?.window
  }

  public func enterNativeFullscreen(completion: @escaping () -> Void) {
    guard let window = window else {
      printWarning()
      return completion()
    }

    guard !window.styleMask.contains(.fullScreen) else {
      return completion()
    }
    observeTransition(
      window: window,
      success: NSWindow.didEnterFullScreenNotification,
      completion: completion
    )
    window.toggleFullScreen(nil)
  }

  public func exitNativeFullscreen(completion: @escaping () -> Void) {
    guard let window = window else {
      printWarning()
      return completion()
    }

    guard window.styleMask.contains(.fullScreen) else {
      return completion()
    }
    observeTransition(
      window: window,
      success: NSWindow.didExitFullScreenNotification,
      completion: completion
    )
    window.toggleFullScreen(nil)
  }

  private func printWarning() {
    NSLog("Utils: warning: unable to find the window")
  }

  private func observeTransition(
    window: NSWindow,
    success: Notification.Name,
    completion: @escaping () -> Void
  ) {
    clearTransitionObservers()
    let center = NotificationCenter.default
    transitionObservers.append(
      center.addObserver(forName: success, object: window, queue: .main) { [weak self] _ in
        self?.clearTransitionObservers()
        completion()
      }
    )
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, !self.transitionObservers.isEmpty else { return }
      self.clearTransitionObservers()
      completion()
    }
    transitionTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
  }

  private func clearTransitionObservers() {
    transitionTimeout?.cancel()
    transitionTimeout = nil
    let center = NotificationCenter.default
    for observer in transitionObservers {
      center.removeObserver(observer)
    }
    transitionObservers.removeAll()
  }
}
