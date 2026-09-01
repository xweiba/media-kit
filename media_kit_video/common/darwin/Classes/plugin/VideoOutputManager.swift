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
    handle: Int64
  ) {
    let videoOutput = self.videoOutputs[handle]
    if videoOutput == nil {
      return
    }

    self.videoOutputs[handle] = nil
  }

  public func enterPictureInPicture(handle: Int64) -> Bool {
    videoOutputs[handle]?.enterPictureInPicture() ?? false
  }

  public func exitPictureInPicture(handle: Int64) -> Bool {
    videoOutputs[handle]?.exitPictureInPicture() ?? false
  }
}
