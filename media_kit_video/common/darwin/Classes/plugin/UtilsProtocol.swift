import Foundation

public protocol UtilsProtocol: NSObject {
  func enterNativeFullscreen(completion: @escaping () -> Void)
  func exitNativeFullscreen(completion: @escaping () -> Void)
}
