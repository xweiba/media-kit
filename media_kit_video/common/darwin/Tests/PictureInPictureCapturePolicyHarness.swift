import Foundation

@main
enum PictureInPictureCapturePolicyHarness {
  static func main() {
    var policy = PictureInPictureCapturePolicy(primingInterval: 1)
    precondition(policy.mode == .stopped)

    policy.prepare(applicationActive: true)
    policy.prepare(applicationActive: true)
    precondition(policy.mode == .priming)
    precondition(policy.admitsFrame(at: 0))
    precondition(!policy.admitsFrame(at: 0.5))
    precondition(policy.admitsFrame(at: 1))

    policy.setApplicationActive(false)
    policy.setApplicationActive(false)
    precondition(policy.mode == .fullRate)
    precondition(policy.admitsFrame(at: 1.1))

    policy.setApplicationActive(true)
    precondition(policy.mode == .priming)
    policy.requestStart()
    precondition(policy.mode == .fullRate)
    policy.setPictureInPictureActive(true)
    precondition(policy.mode == .fullRate)
    policy.setPictureInPictureActive(false)
    precondition(policy.mode == .priming)

    policy.dispose()
    policy.prepare(applicationActive: false)
    policy.requestStart()
    precondition(policy.mode == .stopped)
    precondition(!policy.admitsFrame(at: 10))
  }
}
