import Foundation

enum VideoDetailPlayURLFailureHandlingResult {
    case handled(signpostMessage: String)
    case aborted(signpostMessage: String)
}
