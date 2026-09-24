import Foundation

extension PlaybackNetworkDiagnosticsActionHandler {
    static func copyDiagnostics(
        text: String,
        stateActions: StateActions
    ) {
        PlaybackNetworkDiagnosticsCopyAction.copy(text)
        stateActions.setCopiedMessage("已复制诊断信息")
    }
}
