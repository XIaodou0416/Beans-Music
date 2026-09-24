import SwiftUI

struct SearchResultRouteRow: View {
    let result: SearchResultItem

    var body: some View {
        switch result {
        case .video(let video):
            VideoRouteLink(video) {
                SearchVideoResultRow(video: video)
            }
        case .user(let user):
            VideoOwnerRouteLink(owner: user.owner) {
                SearchUserResultRow(user: user)
            }
        case .bangumi(let media):
            SearchInternalMediaRouteRow(media: media, kind: "番剧")
        case .movie(let media):
            SearchInternalMediaRouteRow(media: media, kind: "影视")
        case .article(let article):
            SearchArticleRouteRow(article: article)
        }
    }
}

private struct SearchInternalMediaRouteRow: View {
    let media: SearchMediaItem
    let kind: String
    @Environment(\.openPgcSeasonRouteAction) private var openPgcSeasonRoute

    var body: some View {
        if let route = PgcSeasonRoute(media: media) {
            if let openPgcSeasonRoute {
                Button {
                    openPgcSeasonRoute(route)
                } label: {
                    SearchMediaResultRow(media: media, kind: kind)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: route) {
                    SearchMediaResultRow(media: media, kind: kind)
                }
            }
        } else if let url = media.destinationURL {
            AppLinkButton(url: url) {
                SearchMediaResultRow(media: media, kind: kind)
            }
        } else {
            SearchMediaResultRow(media: media, kind: kind)
        }
    }
}

private struct SearchArticleRouteRow: View {
    let article: SearchArticleItem

    var body: some View {
        if let url = article.destinationURL {
            AppLinkButton(url: url) {
                SearchArticleResultRow(article: article)
            }
        } else {
            SearchArticleResultRow(article: article)
        }
    }
}
