import Foundation

extension VideoDetailViewModel {
    func dialogReplies(for root: Comment, reply: Comment) -> [Comment] {
        let key = dialogKey(root: root, reply: reply)
        return dialogThreads[key] ?? localDialogReplies(root: root, reply: reply)
    }

    func dialogState(for root: Comment, reply: Comment) -> LoadingState {
        dialogThreadStates[dialogKey(root: root, reply: reply)] ?? .idle
    }

    func loadDialog(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        guard dialogThreads[key] == nil else { return }
        await loadDialogPage(for: root, reply: reply)
    }

    func reloadDialog(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        dialogThreads[key] = nil
        await loadDialogPage(for: root, reply: reply)
    }

    func loadDialogPage(for root: Comment, reply: Comment) async {
        guard let target = commentTarget else {
            dialogThreadStates[dialogKey(root: root, reply: reply)] = .failed("没有找到评论对象，无法加载对话")
            return
        }

        let key = dialogKey(root: root, reply: reply)
        let token = beginDialogThreadLoad(for: key)
        defer {
            clearDialogThreadLoadIfCurrent(key: key, token: token)
        }
        let fallbackReplies = filteredComments(localDialogReplies(root: root, reply: reply))

        guard let dialogID = reply.dialogID, dialogID > 0 else {
            guard isCurrentDialogThreadLoad(key: key, rootID: root.id, token: token, target: target) else {
                return
            }
            dialogThreads[key] = fallbackReplies
            dialogThreadStates[key] = .loaded
            return
        }

        dialogThreadStates[key] = .loading
        do {
            let page = try await api.fetchCommentDialog(
                oid: target.oid,
                type: target.type,
                root: root.rpid,
                dialog: dialogID
            )
            guard isCurrentDialogThreadLoad(key: key, rootID: root.id, token: token, target: target) else {
                return
            }
            let replies = uniqueComments(filteredComments(page.replies ?? []) + fallbackReplies)
            dialogThreads[key] = replies.isEmpty ? fallbackReplies : replies
            dialogThreadStates[key] = .loaded
        } catch {
            guard isCurrentDialogThreadLoad(key: key, rootID: root.id, token: token, target: target) else {
                return
            }
            dialogThreads[key] = fallbackReplies
            dialogThreadStates[key] = .failed(error.localizedDescription)
        }
    }
}
