#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

public class VideoOutputManager: NSObject {
  public typealias PictureInPictureStateCallback = (Int64, String, [String: Any]?) -> Void

  private let registry: FlutterTextureRegistry
  private let pictureInPictureStateCallback: PictureInPictureStateCallback
  private var videoOutputs = [Int64: VideoOutput]()

  init(
    registry: FlutterTextureRegistry,
    pictureInPictureStateCallback: @escaping PictureInPictureStateCallback
  ) {
    self.registry = registry
    self.pictureInPictureStateCallback = pictureInPictureStateCallback
  }

  public func create(
    handle: Int64,
    configuration: VideoOutputConfiguration,
    textureUpdateCallback: @escaping VideoOutput.TextureUpdateCallback
  ) {
    let videoOutput = VideoOutput(
      handle: handle,
      configuration: configuration,
      registry: self.registry,
      textureUpdateCallback: textureUpdateCallback,
      pictureInPictureStateCallback: { [weak self] state, error in
        self?.pictureInPictureStateCallback(handle, state, error)
      }
    )

    self.videoOutputs[handle] = videoOutput
  }

  public func setSize(
    handle: Int64,
    width: Int64?,
    height: Int64?
  ) {
    let videoOutput = self.videoOutputs[handle]
    if videoOutput == nil {
      return
    }

    videoOutput!.setSize(
      width: width,
      height: height
    )
  }

  public func destroy(
    handle: Int64,
    completion: @escaping () -> Void
  ) {
    let videoOutput = self.videoOutputs[handle]
    if videoOutput == nil {
      completion()
      return
    }

    // 必须等待 VideoOutput 的串行 worker 释放 mpv_render_context 后再回复
    // Dart；否则 Player.dispose 可能同时销毁 mpv core，造成双向析构竞态。
    videoOutput!.dispose { [weak self] in
      self?.videoOutputs[handle] = nil
      completion()
    }
  }

  public func enterPictureInPicture(handle: Int64) -> Bool {
    videoOutputs[handle]?.enterPictureInPicture() ?? false
  }

  public func exitPictureInPicture(handle: Int64) -> Bool {
    videoOutputs[handle]?.exitPictureInPicture() ?? false
  }
}
