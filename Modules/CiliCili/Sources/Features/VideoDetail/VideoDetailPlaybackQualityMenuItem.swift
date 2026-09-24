import Foundation

struct VideoDetailPlaybackQualityMenuItem: Identifiable, Equatable {
    let variant: PlayVariant
    let title: String
    let subtitle: String?
    let systemImage: String
    let isDisabled: Bool

    var id: String { variant.id }
}
