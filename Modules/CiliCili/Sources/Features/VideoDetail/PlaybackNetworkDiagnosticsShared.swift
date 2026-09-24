enum PlaybackNetworkDiagnosticFormat {
}

extension PlaybackEnvironment.NetworkClass {
    var diagnosticTitle: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return "蜂窝网络"
        case .constrained:
            return "受限网络"
        case .unknown:
            return "未知"
        }
    }
}
