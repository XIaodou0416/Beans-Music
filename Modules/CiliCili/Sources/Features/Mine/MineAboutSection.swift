import SwiftUI
import UIKit

struct MineAboutSection: View {
    @Environment(\.openURL) private var openURL

    private static let projectURL = URL(string: "https://github.com/Rone89/cilicili")!

    var body: some View {
        Section("关于") {
            HStack {
                Label("版本", systemImage: "info.circle")
                Spacer(minLength: 12)
                Text(versionText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            projectRow
                .contentShape(Rectangle())
                .gesture(projectAddressGesture)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("轻点打开项目地址，长按复制")
                .accessibilityAction(named: "复制项目地址") {
                    copyProjectAddress()
                }
        }
    }

    private var projectRow: some View {
        HStack {
            Label("项目地址", systemImage: "arrow.up.right.square")
            Spacer(minLength: 12)
            Text("Rone89/cilicili")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var projectAddressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .onEnded { _ in
                copyProjectAddress()
            }
            .exclusively(before: TapGesture().onEnded {
                openURL(Self.projectURL)
            })
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(version) (\(build))"
    }

    private func copyProjectAddress() {
        UIPasteboard.general.string = Self.projectURL.absoluteString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
