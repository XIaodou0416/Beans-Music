import SwiftUI

enum CommentSectionStyle: Equatable {
    case grouped
    case plain

    var horizontalPadding: CGFloat {
        switch self {
        case .grouped:
            return 11
        case .plain:
            return 13
        }
    }

    var showsReplyPreviewContainer: Bool {
        true
    }

    var usesGroupedFooter: Bool {
        self == .grouped
    }
}
