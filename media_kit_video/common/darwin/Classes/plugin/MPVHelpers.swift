import Darwin
import Foundation

#if SWIFT_PACKAGE
  import Mpv
#endif

public enum MPVHelpers {
  public static func checkError(_ status: CInt) {
    if status < 0 {
      NSLog("MPVHelpers: error: \(String(cString: mpv_error_string(status)))")
      exit(1)
    }
  }

  public static func getVideoOutParams(
    _ handle: OpaquePointer
  ) -> MPVVideoOutParams {
    var node = mpv_node()
    // A failed query (no video yet) transfers no ownership.
    guard mpv_get_property(handle, "video-out-params", MPV_FORMAT_NODE, &node) >= 0 else {
      return MPVVideoOutParams.empty
    }
    defer {
      mpv_free_node_contents(&node)
    }

    guard node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list else {
      return MPVVideoOutParams.empty
    }

    let map: mpv_node_list = list.pointee
    if map.num <= 0 {
      return MPVVideoOutParams.empty
    }

    return MPVVideoOutParams.fromMPVNodeList(map)
  }
}
