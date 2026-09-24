import SwiftUI
import UIKit

// Adapted from CiliCili (Rone89), GPL-3.0, revision
// c61b0d33966c5d8e87ea20527b8ba48c702c10c1:
// CommentRow, CommentRowHeader, CommentRowLayout and
// DynamicCommentFullRowReplyTarget. See THIRD_PARTY_NOTICES.md.
struct BilibiliCommentRow: View {
    let reply: BilibiliReply
    let liked: Bool
    let likeDisabled: Bool
    let showsPreviews: Bool
    let openAuthor: () -> Void
    let like: () -> Void
    let compose: () -> Void
    let showReplies: () -> Void
    let showImage: (URL) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Put the row target behind the content, never over its buttons.
            // Avatar, like, image and thread actions retain their own hit areas.
            Button(action: compose) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("回复 \(reply.author.name) 的评论")

            HStack(alignment: .top, spacing: 10) {
                Button(action: openAuthor) {
                    CoverImage(url: reply.author.coverURL, size: 38, cornerRadius: 19)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开\(reply.author.name)主页")

                VStack(alignment: .leading, spacing: 0) {
                    header
                    Text(reply.message)
                        .font(.subheadline)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: compose)
                    if !reply.pictures.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], spacing: 6) {
                            ForEach(Array(reply.pictures.enumerated()), id: \.offset) { _, url in
                                Button { showImage(url) } label: {
                                    AsyncImage(url: url) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.secondary.opacity(0.12)
                                    }
                                    .frame(height: 90).frame(maxWidth: .infinity)
                                    .clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("查看评论图片")
                            }
                        }
                        .padding(.top, 8)
                    }
                    if showsPreviews && (reply.replyCount > 0 || !reply.previews.isEmpty) {
                        Button(action: showReplies) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(reply.previews.prefix(2)) { preview in
                                    (Text(preview.author.name + "：").foregroundColor(.secondary) + Text(preview.message))
                                        .font(.caption).lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Text("查看 \(reply.replyCount) 条回复 ›")
                                    .font(.caption.weight(.medium)).foregroundStyle(Color.beansAmber)
                            }
                            .multilineTextAlignment(.leading)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain).padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .padding(.vertical, 10)
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        .contextMenu { Button("复制评论") { UIPasteboard.general.string = reply.message } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Button(action: openAuthor) {
                    Text(reply.author.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                }.buttonStyle(.plain)
                Text(beansCommentDate(reply.date)).font(.caption).foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }.frame(minHeight: 38, alignment: .top)
            Spacer(minLength: 8)
            Button(action: like) {
                Label("\(max(0, reply.likeCount + (liked == reply.liked ? 0 : liked ? 1 : -1)))",
                      systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.caption).foregroundStyle(liked ? Color.beansAmber : Color.beansComment)
                    .frame(minWidth: 44, minHeight: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(likeDisabled)
            .accessibilityLabel(liked ? "取消点赞" : "点赞评论")
        }
    }
}

struct BilibiliCommentTarget {
    let root: String?
    let parent: String?
    let author: String?
}

enum BilibiliCommentSheet: Identifiable {
    case login
    case compose(BilibiliCommentTarget)
    case thread(BilibiliReply)
    case image(URL)

    var id: String {
        switch self {
        case .login: return "login"
        case .compose(let target): return "compose:\(target.root ?? "new"):\(target.parent ?? "new")"
        case .thread(let reply): return "thread:\(reply.id)"
        case .image(let url): return "image:\(url.absoluteString)"
        }
    }
}

struct BilibiliCommentSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(0..<4) { _ in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Color.secondary.opacity(0.12)).frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).frame(width: 90, height: 12)
                        RoundedRectangle(cornerRadius: 3).frame(height: 12)
                        RoundedRectangle(cornerRadius: 3).frame(height: 12).padding(.trailing, 35)
                    }.foregroundStyle(Color.secondary.opacity(0.12))
                }
            }
        }.padding(.vertical, 12).accessibilityLabel("正在加载评论")
    }
}

struct BilibiliCommentImagePreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        BeansNavigationStack {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else if phase.error != nil {
                    Text("图片加载失败").foregroundStyle(.secondary)
                } else { ProgressView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("评论图片").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
