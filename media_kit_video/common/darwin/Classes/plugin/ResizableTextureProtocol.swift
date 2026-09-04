import CoreGraphics

#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

public protocol ResizableTextureProtocol: NSObject, FlutterTexture {
  func resize(_ size: CGSize)
  /// 仅在 mpv 提供新视频帧时执行渲染，并返回是否需要通知 Flutter 取帧。
  func render(_ size: CGSize) -> Bool
  func dispose()
}
