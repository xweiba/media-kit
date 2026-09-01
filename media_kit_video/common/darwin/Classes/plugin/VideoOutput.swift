import CoreGraphics
import Foundation

#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

// This class creates and manipulates the different types of FlutterTexture,
// handles resizing, rendering calls, and notify Flutter when a new frame is
// available to render.
//
// To improve the user experience, a worker is used to execute heavy tasks on a
// dedicated thread.
public class VideoOutput: NSObject {
  // Will be called on the main thread
  public typealias TextureUpdateCallback = (Int64, CGSize) -> Void
  public typealias PictureInPictureStateCallback = (String, [String: Any]?) -> Void

  private static let isSimulator: Bool = {
    let isSim: Bool
    #if targetEnvironment(simulator)
      isSim = true
    #else
      isSim = false
    #endif
    return isSim
  }()

  private let handle: OpaquePointer
  private let enableHardwareAcceleration: Bool
  private let registry: FlutterTextureRegistry
  private let textureUpdateCallback: TextureUpdateCallback
  private let pictureInPictureStateCallback: PictureInPictureStateCallback
  private let worker: Worker = .init()
  private var width: Int64?
  private var height: Int64?
  private var texture: ResizableTextureProtocol!
  private var textureId: Int64 = -1
  private var currentSize: CGSize = CGSize.zero
  private var disposed: Bool = false
  private var disposalStarted: Bool = false
  #if os(iOS)
    private var pictureInPictureRenderer: Any?
  #endif

  init(
    handle: Int64,
    configuration: VideoOutputConfiguration,
    registry: FlutterTextureRegistry,
    textureUpdateCallback: @escaping TextureUpdateCallback,
    pictureInPictureStateCallback: @escaping PictureInPictureStateCallback
  ) {
    let handle = OpaquePointer(bitPattern: Int(handle))
    assert(handle != nil, "handle casting")

    self.handle = handle!
    width = configuration.width
    height = configuration.height
    enableHardwareAcceleration = configuration.enableHardwareAcceleration
    self.registry = registry
    self.textureUpdateCallback = textureUpdateCallback
    self.pictureInPictureStateCallback = pictureInPictureStateCallback

    super.init()

    #if os(iOS)
      if #available(iOS 15.0, *) {
        pictureInPictureRenderer = PictureInPictureRenderer(
          handle: self.handle,
          stateCallback: pictureInPictureStateCallback
        )
      }
    #endif

    worker.enqueue {
      self._init()
    }
  }

  deinit {
    // 正常 Player.dispose 已在 worker 上同步释放纹理；这里只处理引擎异常
    // 拆除等没有经过显式 dispose 的兜底路径。
    if !disposalStarted {
      worker.cancel()
      disposed = true
      disposeTextureId()
    }
  }

  public func dispose(completion: @escaping () -> Void) {
    if disposalStarted {
      completion()
      return
    }
    disposalStarted = true
    worker.enqueue { [self] in
      disposed = true
      // Flutter 纹理注册表可能继续持有 texture 到 raster 线程下一次
      // autorelease pool；必须在当前串行 worker 上显式释放 render context。
      texture.dispose()
      disposeTextureId()
      worker.cancel()
      DispatchQueue.main.async(execute: completion)
    }
  }

  public func setSize(width: Int64?, height: Int64?) {
    worker.enqueue {
      self.width = width
      self.height = height
    }
  }

  private func _init() {
    let enableHardwareAcceleration =
      VideoOutput.isSimulator ? false : enableHardwareAcceleration

    NSLog(
      "VideoOutput: enableHardwareAcceleration: \(enableHardwareAcceleration)"
    )

    if VideoOutput.isSimulator {
      NSLog(
        "VideoOutput: warning: hardware rendering is disabled in the iOS simulator, due to an incompatibility with OpenGL ES"
      )
    }

    if enableHardwareAcceleration {
      texture = SafeResizableTexture(
        TextureHW(
          handle: handle,
          // Use `weak self` to prevent memory leaks
          updateCallback: { [weak self]() in
            guard let that = self else {
              return
            }
            that.updateCallback()
          }
        )
      )
    } else {
      texture = SafeResizableTexture(
        TextureSW(
          handle: handle,
          // Use `weak self` to prevent memory leaks
          updateCallback: { [weak self]() in
            guard let that = self else {
              return
            }
            that.updateCallback()
          }
        )
      )
    }

    DispatchQueue.main.sync { [weak self]() in
      guard let that = self else {
        return
      }
      that.registerTextureId()
    }
  }

  // Must be run on the main thread
  private func registerTextureId() {
    // Textures must be registered on the platform thread.
    textureId = registry.register(texture)
    // textureUpdateCallback must run on the main thread
    textureUpdateCallback(textureId, CGSize(width: 0, height: 0))
  }

  private func disposeTextureId() {
    let registry_ = self.registry
    let textureId_ = self.textureId
    textureId = -1
    DispatchQueue.main.async {
      // Textures must be unregistered on the platform thread
      registry_.unregisterTexture(textureId_)
    }
  }

  public func updateCallback() {
    worker.enqueue {
      self._updateCallback()
    }
  }

  private func _updateCallback() {
    let size = videoSize

    if size.width == 0 || size.height == 0 {
      return
    }

    if currentSize != size {
      currentSize = size

      texture.resize(size)
      DispatchQueue.main.sync { [weak self] in
        guard let that = self else { return }
        // textureUpdateCallback must run on the main thread
        that.textureUpdateCallback(that.textureId, size)
      }
    }

    if disposed {
      return
    }

    texture.render(size)
    #if os(iOS)
      if #available(iOS 15.0, *),
        let renderer = pictureInPictureRenderer as? PictureInPictureRenderer,
        renderer.shouldCaptureFrame,
        let pixelBuffer = texture.copyPixelBuffer()?.takeRetainedValue()
      {
        renderer.enqueue(pixelBuffer)
      }
    #endif
    DispatchQueue.main.sync { [weak self] in
      guard let that = self else { return }
      // Textures must be marked as available from the main thread
      that.registry.textureFrameAvailable(that.textureId)
    }
  }

  public func enterPictureInPicture() -> Bool {
    #if os(iOS)
      if #available(iOS 15.0, *),
        let renderer = pictureInPictureRenderer as? PictureInPictureRenderer
      {
        return renderer.start()
      }
    #endif
    return false
  }

  public func exitPictureInPicture() -> Bool {
    #if os(iOS)
      if #available(iOS 15.0, *),
        let renderer = pictureInPictureRenderer as? PictureInPictureRenderer
      {
        return renderer.stop()
      }
    #endif
    return false
  }

    private var videoSize: CGSize {
        // fixed size
        if width != nil && height != nil {
            return CGSize(
                width: Double(width!),
                height: Double(height!)
            )
        }
        
        let params = MPVHelpers.getVideoOutParams(handle)
        return CGSize(
            width: Double(width ?? (params.rotate == 0 || params.rotate == 180
                                    ? params.dw
                                    : params.dh)),
            height: Double(height ?? (params.rotate == 0 || params.rotate == 180
                                      ? params.dh
                                      : params.dw))
        )
  }
}
