import SwiftUI

struct MineHomeSettingsSection: View {
    @EnvironmentObject private var homeRecommendDiagnosticsStore: HomeRecommendDiagnosticsStore
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section("首页") {
            Picker(selection: Binding(
                get: { libraryStore.homeFeedLayout },
                set: { libraryStore.setHomeFeedLayout($0) }
            )) {
                ForEach(HomeFeedLayout.allCases) { layout in
                    Text(layout.title).tag(layout)
                }
            } label: {
                MineSettingsLabel("首页布局", systemImage: "rectangle.grid.1x2")
            }
            .pickerStyle(.menu)

            Picker(selection: Binding(
                get: { libraryStore.homeRecommendFeedSourcePreference },
                set: { libraryStore.setHomeRecommendFeedSourcePreference($0) }
            )) {
                ForEach(HomeRecommendFeedSourcePreference.allCases) { source in
                    Text(source.title).tag(source)
                }
            } label: {
                MineSettingsLabel("首页推荐内容来源", systemImage: "sparkles.tv")
            }
            .pickerStyle(.menu)

            Text(recommendSourceHint)
                .font(.footnote)
                .foregroundStyle(.secondary)

            NavigationLink {
                MineHomeRecommendDiagnosticsView()
            } label: {
                PlainSettingsNavigationRow(
                    title: "推荐诊断",
                    subtitle: MineHomeRecommendDiagnosticsSummary(
                        snapshot: homeRecommendDiagnosticsStore.snapshot
                    ).text,
                )
            }

            Toggle(isOn: Binding(
                get: { libraryStore.nativePullRefreshEnabled },
                set: { libraryStore.setNativePullRefreshEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("原生下拉刷新", systemImage: "arrow.clockwise.circle")

                    Text("默认使用系统原生刷新；关闭后可调整自定义触发距离。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            MineHomeRefreshDistanceControl(libraryStore: libraryStore)
        }
    }

    private var recommendSourceHint: String {
        switch libraryStore.homeRecommendFeedSourcePreference {
        case .web:
            switch sessionStore.loginCredentialKind {
            case .appQRCodeTV:
                return "当前是扫码登录：按实测，网页端推荐会比 App 端更接近官方。"
            case .appSMS:
                return "当前是短信登录：如果想更像官方 App，可尝试切到 App 端推荐。"
            case .web:
                return "当前是网页登录：网页端推荐更稳定，App 端个性化会较弱。"
            case .unknown:
                return "网页端更稳定；如果 App 端推荐不准，优先保留网页端。"
            }
        case .app:
            if libraryStore.guestModeEnabled {
                return "当前是 App 端游客推荐：隐私里的游客推荐模式已开启，不会使用你的账号画像。"
            }
            if sessionStore.appAccessKey() != nil {
                switch sessionStore.loginCredentialKind {
                case .appSMS:
                    return "当前是 App 端账号推荐 + 短信登录：已带移动端凭证，这是目前最接近官方 App 推荐的组合。"
                case .appQRCodeTV:
                    return "当前是 App 端账号推荐 + 扫码登录：已带移动端凭证；如推荐不准，可改用短信登录或切网页端。"
                case .web, .unknown:
                    return "当前是 App 端账号推荐：已带移动端凭证，更接近官方客户端推荐。"
                }
            }
            let snapshot = homeRecommendDiagnosticsStore.snapshot
            if snapshot.source == .app,
               snapshot.status != .idle,
               snapshot.isLoggedIn,
               !snapshot.hasAccessKey {
                return "当前是 App 端账号推荐，但缺少移动端 access_key；请在“我的”里用 App 短信验证码登录。"
            }
            switch sessionStore.loginCredentialKind {
            case .appSMS:
                return "当前是 App 端账号推荐 + 短信登录：这是目前最接近官方 App 推荐的组合。"
            case .appQRCodeTV:
                return "当前是 App 端账号推荐 + 扫码登录：扫码凭证偏 TV 端，如推荐不准请改用短信登录或切网页端。"
            case .web:
                return "当前是 App 端账号推荐，但你是网页登录；如推荐偏泛，请改用短信验证码登录。"
            case .unknown:
                return "当前是 App 端账号推荐；如推荐不像官方，建议用 App 短信验证码重新登录。"
            }
        }
    }
}

private struct MineHomeRefreshDistanceControl: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MineSettingsLabel("下拉刷新距离", systemImage: "arrow.down.circle")
                Spacer()
                Text(
                    libraryStore.nativePullRefreshEnabled
                        ? "系统默认"
                        : "\(Int(libraryStore.homeRefreshTriggerDistance)) pt"
                )
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if libraryStore.nativePullRefreshEnabled {
                Text(refreshDistanceHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Slider(
                    value: Binding(
                        get: { libraryStore.homeRefreshTriggerDistance },
                        set: { libraryStore.setHomeRefreshTriggerDistance($0) }
                    ),
                    in: LibraryStore.homeRefreshDistanceRange,
                    step: 5
                ) {
                    Text("下拉刷新距离")
                } minimumValueLabel: {
                    Text("近")
                } maximumValueLabel: {
                    Text("远")
                }

                HStack {
                    Text(refreshDistanceHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("默认") {
                        libraryStore.setHomeRefreshTriggerDistance(
                            LibraryStore.defaultHomeRefreshTriggerDistance
                        )
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var refreshDistanceHint: String {
        if libraryStore.nativePullRefreshEnabled {
            return "关闭原生下拉刷新后可调整触发距离。"
        }
        return "当前使用自定义刷新指示器和触发距离。"
    }
}
