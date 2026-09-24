import Foundation

extension VideoDetailViewModel {
    func interactionFailureMessage(_ error: Error) -> String {
        if case BiliAPIError.missingSESSDATA = error {
            return "请先登录后再进行互动操作"
        }
        return error.localizedDescription
    }
}
