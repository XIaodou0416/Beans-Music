import SwiftUI

// MARK: - 首次使用引导页（分页引导 + 免责确认）

/// 首次进入 App 时的引导式提示：欢迎 → DIY 美化 → 三平台 → 免责确认。
/// 免责确认沿用原硬性要求：必须输入「我已了解并同意继续使用」才能进入软件。
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0
    @State private var typed = ""
    @AppStorage("beans.language") private var languageRaw = AppLanguage.chinese.rawValue

    private let totalPages = 4
    private var confirmText: String {
        languageRaw == AppLanguage.english.rawValue ? "I understand and agree to continue" : "我已了解并同意继续使用"
    }

    private var isEnglish: Bool { languageRaw == AppLanguage.english.rawValue }
    private var nextText: String { isEnglish ? "Next" : "下一步" }
    private var skipText: String { isEnglish ? "Skip Intro" : "跳过介绍" }
    private var enterText: String { isEnglish ? "Enter Beans Music" : "进入软件" }

    var body: some View {
        ZStack {
            Color.beansBackground.ignoresSafeArea()
            // 主题色光晕（跟随当前配色主题）
            LinearGradient(
                colors: [Color.clear, Color.beansHighlight.opacity(0.12), Color.clear],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    diyPage.tag(1)
                    platformPage.tag(2)
                    disclaimerPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: page)

                // 底部控制区
                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
            }
            .overlay(alignment: .topTrailing) {
                Picker("语言", selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.beansHighlight)
                .padding(.top, 14)
                .padding(.trailing, 18)
            }
        }
    }

    // MARK: 底部指示器 + 按钮

    private var bottomBar: some View {
        VStack(spacing: 16) {
            // 分页圆点指示器
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color.beansHighlight : Color.beansLabel.opacity(0.22))
                        .frame(width: i == page ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
                }
            }

            if page < totalPages - 1 {
                // 下一步 / 跳过介绍
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
                } label: {
                    Text(nextText)
                        .font(BeansFont.appFont(16, .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient.beansAccent)
                        )
                        .beansCardShadow(radius: 10, y: 4)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { page = totalPages - 1 }
                } label: {
                    Text(skipText)
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansSecondary)
                }
            } else {
                // 免责确认输入框（上方固定提示，输入时不会消失）
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringKey("请输入："))
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansHighlight)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(LinearGradient.beansAccent)
                        TextField(confirmText, text: $typed)
                            .font(BeansFont.appFont(14))
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if typed != confirmText {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) { typed = confirmText }
                            } label: {
                                Text(isEnglish ? "Fill" : "一键填入")
                                    .font(BeansFont.appFont(12, .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .frame(height: 30)
                                    .background(
                                        Capsule().fill(LinearGradient.beansAccent)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.beansCard.opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                Color.beansHighlight.opacity(typed.isEmpty ? 0.3 : 0.75),
                                lineWidth: 1.2
                            )
                    )
                }

                Button {
                    onFinish()
                } label: {
                    Text(enterText)
                        .font(BeansFont.appFont(16, .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(typed == confirmText ? Color.beansHighlight : Color.beansHighlight.opacity(0.35))
                        )
                        .beansCardShadow(radius: 10, y: 4)
                }
                .disabled(typed != confirmText)
                .animation(.easeOut(duration: 0.2), value: typed == confirmText)
            }
        }
    }

    // MARK: 第 1 页 · 欢迎

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            // 真实 App 图标
            Image("OnboardingLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: Color.beansHighlight.opacity(0.45), radius: 24, y: 12)
                .padding(.bottom, 6)

            Text(isEnglish ? "Welcome to Beans Music" : "欢迎使用 Beans Music")
                .font(BeansFont.appFont(30, .bold))
                .foregroundStyle(Color.beansLabel)

            Text(isEnglish ? "Native Liquid Glass on iOS 26 · NetEase Cloud Music / QQ Music / Kugou\nPure SwiftUI · Fully open source" : "iOS 26 原生液态玻璃 · 聚合网易云 / QQ / 酷狗\n纯 SwiftUI · 完全开源")
                .font(BeansFont.appFont(15))
                .foregroundStyle(Color.beansSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: 第 2 页 · DIY 美化

    private var diyPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient.beansAccent)

            Text(isEnglish ? "Your player, your rules" : "你的播放器，你做主")
                .font(BeansFont.appFont(26, .bold))
                .foregroundStyle(Color.beansLabel)

            Text(isEnglish ? "Customize everything from the global theme to each player component" : "从全局主题到播放器每个组件，全部可以自定义")
                .font(BeansFont.appFont(14))
                .foregroundStyle(Color.beansSecondary)

            VStack(spacing: 12) {
                diyRow(icon: "circle.hexagongrid.fill", tint: Color.beansHighlight,
                       title: isEnglish ? "Global Theme Colors" : "全局主题色盘",
                       detail: isEnglish ? "Nine themes and custom colors across the app" : "9 套主题一键换肤，色盘任选颜色，全 App 跟随")
                diyRow(icon: "photo.on.rectangle.angled", tint: .beansSage,
                       title: isEnglish ? "Custom Wallpaper Library" : "自定义壁纸库",
                       detail: isEnglish ? "Switch wallpapers anytime with synchronized backgrounds" : "多张壁纸随时切换，深浅两套背景，全局同步")
                diyRow(icon: "slider.horizontal.3", tint: Color(red: 0.39, green: 0.71, blue: 0.96),
                       title: isEnglish ? "Flexible Player Layout" : "底部布局自由拖动",
                       detail: isEnglish ? "Position and scale the progress bar, buttons, and indicator" : "进度条 / 按钮 / 指示线任意摆放缩放")
                diyRow(icon: "text.quote", tint: Color(red: 0.96, green: 0.56, blue: 0.70),
                       title: isEnglish ? "Fully Customizable Lyrics" : "歌词全套定制",
                       detail: isEnglish ? "Colors / gradients / glow / blur" : "颜色 / 渐变 / 发光 / 模糊")
            }
            .padding(.horizontal, 28)

            Spacer()
            Spacer()
        }
    }

    private func diyRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.16))
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(tint)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(BeansFont.appFont(15, .bold))
                    .foregroundStyle(Color.beansLabel)
                Text(LocalizedStringKey(detail))
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansSecondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.beansCard.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.beansLabel.opacity(0.08), lineWidth: 1)
        )
        .beansCardShadow(radius: 8, y: 3)
    }

    // MARK: 第 3 页 · 三平台

    private var platformPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient.beansAccent)

            Text(isEnglish ? "Three platforms, one app for all your music" : "三平台聚合，一个 App 全听遍")
                .font(BeansFont.appFont(26, .bold))
                .foregroundStyle(Color.beansLabel)

            Text(isEnglish ? "Sync playlists from NetEase Cloud Music, QQ Music, and Kugou" : "网易云 + QQ 音乐 + 酷狗歌单同步")
                .font(BeansFont.appFont(14))
                .foregroundStyle(Color.beansSecondary)

            VStack(spacing: 12) {
                platformRow(imageName: "BrandNetease", tint: Color(red: 0.87, green: 0.23, blue: 0.23),
                            title: isEnglish ? "NetEase Cloud Music" : "网易云音乐",
                            detail: isEnglish ? "Scan or sign in on the web to sync playlists, favorites, charts, and VIP status" : "扫码 / 网页登录，同步歌单、收藏、听歌排行、VIP")
                platformRow(imageName: "BrandQQ", tint: Color(red: 0.13, green: 0.51, blue: 0.95),
                            title: isEnglish ? "QQ Music" : "QQ 音乐",
                            detail: isEnglish ? "Scan, sign in on the web, or use a Cookie to sync playlists and VIP status" : "扫码 / 网页 / Cookie 登录，同步歌单与 VIP")
                platformRow(imageName: "BrandKugou", tint: Color(red: 0.12, green: 0.55, blue: 1.0),
                            title: isEnglish ? "Kugou Music" : "酷狗音乐",
                            detail: isEnglish ? "Sign in to sync cloud playlists and search Kugou songs" : "登录同步云端歌单，并支持酷狗歌曲搜索")
            }
            .padding(.horizontal, 28)

            Spacer()
            Spacer()
        }
    }

    private func platformRow(imageName: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.16))
                .frame(width: 46, height: 46)
                .overlay(
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(BeansFont.appFont(15, .bold))
                    .foregroundStyle(Color.beansLabel)
                Text(LocalizedStringKey(detail))
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.beansCard.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.beansLabel.opacity(0.08), lineWidth: 1)
        )
        .beansCardShadow(radius: 8, y: 3)
    }

    // MARK: 第 4 页 · 免责确认

    private var disclaimerPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "shield.checkmark")
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient.beansAccent)

            Text(isEnglish ? "Disclaimer" : "免责声明")
                .font(BeansFont.appFont(24, .bold))
                .foregroundStyle(Color.beansLabel)

            VStack(alignment: .leading, spacing: 10) {
                Text(isEnglish ? "· Beans Music is for personal learning and research only. Commercial and illegal use is prohibited." : "· Beans Music 只用作个人学习研究，禁止用于商业及非法用途，如产生法律纠纷与本人无关。")
                Text(isEnglish ? "· Music APIs come from open-source GitHub projects. This app does not store audio. Please support official music services." : "· 音乐 API 来自于 GitHub 开源项目（非官方版 API），本软件不提供任何音频存储服务，如需下载音频，请支持正版！")
                Text(isEnglish ? "· Music copyrights belong to their respective platforms. Beans Music assumes no related legal liability." : "· 音乐版权归各网站所有，本站不承担任何法律责任和连带责任。")
            }
            .font(BeansFont.appFont(13))
            .foregroundStyle(Color.beansSecondary)
            .lineSpacing(5)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.beansCard.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.beansHighlight.opacity(0.25), lineWidth: 1)
            )
            .padding(.horizontal, 28)

            Text(isEnglish ? "Enter the exact text shown above to continue" : "请按输入框上方的提示，完整输入指定文字后进入软件")
                .font(BeansFont.appFont(12))
                .foregroundStyle(Color.beansSecondary.opacity(0.8))

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}
