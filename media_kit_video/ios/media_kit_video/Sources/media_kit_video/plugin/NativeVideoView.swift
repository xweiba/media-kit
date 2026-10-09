import AVFoundation
import Flutter
import UIKit

/// iOS 原生直出：mpv 的 `vo=avfoundation_embed` 把 VideoToolbox 解出的帧直接送进
/// 一个 `AVSampleBufferDisplayLayer`，由系统合成显示，不经 mpv 的 GL 转换和 Flutter
/// 纹理（对应 Android 的 SurfaceView 模式）。
///
/// 显示层**每个播放器一个**（按 mpv 句柄），视图只是借来挂：Flutter 把视频从全屏
/// 挪到小窗、进系统画中画时会换视图，层不变，mpv 的 `--wid` 和画中画的内容源都
/// 不用换（否则画中画绑在旧层上，新帧送进新层，小窗一直灰着）。Dart 降级回纹理
/// 时发 `NativeVideoView.Release` 才释放层。
/// mpv `--wid` 指向的输出目标（每个播放器一个）：mpv 每帧调 `mpvDisplayLayers`，
/// 把同一块解码画面送进可见层和（准备好时）系统画中画的隐藏层，不复制像素。
/// 画中画仍用渲染器自己的隐藏层当内容源，行为与纹理方式一致（回 App 无占位
/// 图标、自动画中画可反复触发）。
@objc final class NativeVideoSink: NSObject {
  /// 屏幕上的可见层（挂在当前的原生视图里）。
  let visibleLayer = AVSampleBufferDisplayLayer()
  private let lock = NSLock()
  private var pipLayer: AVSampleBufferDisplayLayer?

  /// 系统画中画的内容源层；渲染器准备画中画时设上，停止时清空。
  var pictureInPictureLayer: AVSampleBufferDisplayLayer? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return pipLayer
    }
    set {
      lock.lock()
      pipLayer = newValue
      lock.unlock()
    }
  }

  /// mpv 输出线程每帧读取。
  @objc func mpvDisplayLayers() -> NSArray {
    lock.lock()
    defer { lock.unlock() }
    if let pipLayer { return [visibleLayer, pipLayer] }
    return [visibleLayer]
  }
}

final class NativeVideoHostView: UIView {
  private(set) var hosted: AVSampleBufferDisplayLayer?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isUserInteractionEnabled = false
  }

  required init?(coder: NSCoder) { fatalError("not supported") }

  /// 把层挂到自己下面（一个层只能有一个父层：后挂的视图把它接走）。
  func host(_ layer: AVSampleBufferDisplayLayer) {
    hosted = layer
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.frame = bounds
    self.layer.addSublayer(layer)
    CATransaction.commit()
  }

  /// 视图要销毁：层还挂在自己下面才摘（已被新视图接走就不动）。
  func unhost() {
    if let hosted, hosted.superlayer === layer { hosted.removeFromSuperlayer() }
    hosted = nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let hosted, hosted.superlayer === layer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    hosted.frame = bounds
    CATransaction.commit()
  }
}

final class NativeVideoPlatformView: NSObject, FlutterPlatformView {
  let content = NativeVideoHostView(frame: .zero)
  /// mpv 句柄（Player.handle）。
  let handle: Int64

  init(handle: Int64) {
    self.handle = handle
    super.init()
  }

  func view() -> UIView { content }
}

final class NativeVideoViewFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "com.alexmercerind/media_kit_video/native_view"

  private let channel: FlutterMethodChannel
  /// 输出目标建好 / 释放时告诉对应播放器（mpv 句柄）：画中画改由 mpv 供帧 / 回到纹理复制。
  private let onSink: (Int64, NativeVideoSink?) -> Void
  /// mpv 句柄 → 该播放器的输出目标。
  private var sinks: [Int64: NativeVideoSink] = [:]
  /// viewId → 视图。
  private var views: [Int64: NativeVideoPlatformView] = [:]

  init(
    channel: FlutterMethodChannel,
    onSink: @escaping (Int64, NativeVideoSink?) -> Void
  ) {
    self.channel = channel
    self.onSink = onSink
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    let values = args as? [String: Any]
    let handleText = values?["handle"] as? String ?? ""
    let handle = Int64(handleText) ?? 0
    let view = NativeVideoPlatformView(handle: handle)
    views[viewId] = view
    let sink: NativeVideoSink
    if let existing = sinks[handle] {
      sink = existing
    } else {
      sink = NativeVideoSink()
      sinks[handle] = sink
      onSink(handle, sink)
    }
    apply(fit: values?["fit"] as? String, to: sink.visibleLayer)
    view.content.host(sink.visibleLayer)
    // 输出目标地址作为 mpv 的 wid：由这里持有到 Release（Dart 先把 vo 切回 libmpv）。
    let wid = Int64(Int(bitPattern: Unmanaged.passUnretained(sink).toOpaque()))
    channel.invokeMethod(
      "NativeVideoView.Created",
      arguments: ["viewId": viewId, "handle": handleText, "wid": wid] as [String: Any]
    )
    return view
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  /// BoxFit → videoGravity：contain 留黑边、cover 裁边铺满、fill 拉伸。
  private func apply(fit: String?, to layer: AVSampleBufferDisplayLayer) {
    switch fit {
    case "cover": layer.videoGravity = .resizeAspectFill
    case "fill": layer.videoGravity = .resize
    default: layer.videoGravity = .resizeAspect
    }
  }

  /// `NativeVideoView.SetFit` / `.Disposed` / `.Release`；处理了返回 true。
  func handle(_ call: FlutterMethodCall, result: FlutterResult) -> Bool {
    let values = call.arguments as? [String: Any]
    switch call.method {
    case "NativeVideoView.SetFit":
      guard let viewId = (values?["viewId"] as? NSNumber)?.int64Value,
        let view = views[viewId], let sink = sinks[view.handle]
      else { break }
      apply(fit: values?["fit"] as? String, to: sink.visibleLayer)
    case "NativeVideoView.Disposed":
      guard let viewId = (values?["viewId"] as? NSNumber)?.int64Value else { break }
      views.removeValue(forKey: viewId)?.content.unhost()
    case "NativeVideoView.Release":
      // mpv 已切回纹理（不再碰这个层）：释放层，画中画回到纹理复制。
      guard let handle = Int64(values?["handle"] as? String ?? "") else { break }
      if let sink = sinks.removeValue(forKey: handle) {
        sink.visibleLayer.removeFromSuperlayer()
        sink.pictureInPictureLayer = nil
        onSink(handle, nil)
      }
    default:
      return false
    }
    result(nil)
    return true
  }
}
