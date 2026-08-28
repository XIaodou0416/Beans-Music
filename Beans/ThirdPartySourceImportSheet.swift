import SwiftUI
import UniformTypeIdentifiers

/// 导入第三方解锁源：粘贴 JSON / JS 配置，或直接从 .js / .json / .txt 文件导入，解析后保存到音源库
struct ThirdPartySourceImportSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = UnblockSourceStore.shared

    @State private var jsonText = ""
    @State private var errorMessage: String?
    @State private var showFilePicker = false
    @State private var isImporting = false

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("粘贴音源链接、配置内容，或从文件导入（支持 JSON / JS / TXT）")
                    .font(BeansFont.appFont(13, .semibold))
                    .foregroundStyle(Color.beansLabel)
                HStack(spacing: 8) {
                    Button {
                        BeansHaptics.tap()
                        showFilePicker = true
                    } label: {
                        Label("从文件导入", systemImage: "folder")
                            .font(BeansFont.appFont(12, .semibold))
                            .foregroundStyle(Color.beansAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.beansGlassFill))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                TextEditor(text: $jsonText)
                    .font(.system(size: 12, design: .monospaced))
                    .beansScrollContentBackgroundHidden()
                    .padding(8)
                    .frame(minHeight: 150)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.beansGlassFill))
                if let errorMessage {
                    Text(errorMessage)
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(.red)
                }
                Text("字段：name 名称；kind 查询方式（netease-id 按网易云 ID / keyword 按关键词 / lx 落雪 API 服务器）；template 请求模板；urlPath 响应里播放地址的字段路径（如 url、data.url）；headers 可选请求头。\n占位符：{id} 网易云ID、{name} 歌名、{artist} 歌手、{keyword} 歌名+歌手。\n落雪（kind 填 lx）：template 填 lx-music-api-server 的服务器地址，headers 里 source 可选 wy/tx，br 可选 320/128。播放时自动搜索并取流。\n支持直接选择 .js / .json / .txt 文件导入，JS 文件会尝试自动提取其中的 JSON 配置，一个文件可包含多个音源（JSON 数组）。")
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(Color.beansComment)
                Text("酷狗限制说明：酷狗部分歌曲的官方播放地址受会员、版权和地区策略限制。导入音源只能作为用户自行选择的备用来源，不保证所有歌曲都能播放；有会员的歌曲建议优先使用酷狗官方账号和官方播放地址。")
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(Color.beansComment)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    importSource()
                } label: {
                    HStack(spacing: 8) {
                        if isImporting { ProgressView().tint(.white) }
                        Text(isImporting ? "正在读取" : "导入")
                            .font(BeansFont.appFont(15, .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.beansAmber))
                }
                .buttonStyle(.plain)
                .disabled(isImporting)
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("导入第三方源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showFilePicker) {
            SourceFilePicker { url in
                importFromFile(url)
            }
            .ignoresSafeArea()
        }
    }

    /// 粘贴内容导入（支持单个音源或 JSON 数组）
    private func importSource() {
        let input = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            errorMessage = "请输入音源链接或配置内容"
            return
        }
        if let url = URL(string: input), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            if let sources = repositoryPresetSources(for: url) {
                finishImport(sources)
                return
            }
            isImporting = true
            errorMessage = nil
            Task {
                defer { isImporting = false }
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 20
                    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                          let text = String(data: data, encoding: .utf8) else {
                        errorMessage = "音源链接读取失败"
                        return
                    }
                    jsonText = text
                    finishImport(text)
                } catch {
                    errorMessage = "音源链接读取失败：\(error.localizedDescription)"
                }
            }
            return
        }
        finishImport(input)
    }

    private func finishImport(_ text: String) {
        let sources = parseSources(text)
        guard !sources.isEmpty else {
            errorMessage = "未识别到兼容的音源配置"
            return
        }
        finishImport(sources)
    }

    private func finishImport(_ sources: [ThirdPartySource]) {
        for source in sources {
            store.add(source)
        }
        BeansLogger.shared.log("导入第三方音源 \(sources.count) 个：\(sources.map(\.name).joined(separator: "、"))", level: .info)
        BeansHaptics.success()
        ToastCenter.shared.show(sources.count > 1 ? "已导入 \(sources.count) 个音源" : "已导入「\(sources.first?.name ?? "")」")
        dismiss()
    }

    /// guoyue2010/lxmusic- 是音源集合而非单一脚本，导入仓库地址时选用已验证的兼容接口。
    private func repositoryPresetSources(for url: URL) -> [ThirdPartySource]? {
        guard url.host?.lowercased() == "github.com" else { return nil }
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path == "guoyue2010/lxmusic-" || path == "guoyue2010/lxmusic-.git" else { return nil }
        return UnblockSourceStore.guoyuePresetSources
    }

    /// 从文件导入：读取文本后走同一套解析
    private func importFromFile(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "读取文件失败，请选择 .js / .json / .txt 文件"
            return
        }
        jsonText = text
        let sources = parseSources(text)
        guard !sources.isEmpty else {
            errorMessage = "文件中未找到可用的音源配置。若这是混淆后的 LX 脚本，需要脚本暴露可转换的接口地址后才能导入。"
            return
        }
        for source in sources {
            store.add(source)
        }
        BeansLogger.shared.log("从文件导入第三方音源 \(sources.count) 个：\(url.lastPathComponent)", level: .info)
        BeansHaptics.success()
        ToastCenter.shared.show(sources.count > 1 ? "已导入 \(sources.count) 个音源" : "已导入「\(sources.first?.name ?? "")」")
        dismiss()
    }

    /// 解析音源列表：支持单个 JSON 对象、JSON 数组、以及从 JS 代码中提取 JSON
    private func parseSources(_ text: String) -> [ThirdPartySource] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        if let lxSources = parseLXScript(trimmed), !lxSources.isEmpty {
            return lxSources
        }
        if let postSources = parseLXPostMusicURLScript(trimmed), !postSources.isEmpty {
            return postSources
        }
        if let eventSources = parseLXEventScript(trimmed), !eventSources.isEmpty {
            return eventSources
        }
        if let xinghaiSources = parseXinghaiEventScript(trimmed), !xinghaiSources.isEmpty {
            return xinghaiSources
        }
        if let rawSources = parseRawLXScript(trimmed), !rawSources.isEmpty {
            return rawSources
        }
        if let list = try? JSONDecoder().decode([ThirdPartySource].self, from: data), !list.isEmpty {
            return list
        }
        if let single = try? JSONDecoder().decode(ThirdPartySource.self, from: data) {
            return [single]
        }
        // JS 文件：提取完整的 {} 或 [] 内容再尝试作为 JSON 配置解析。
        for pair in [("{", "}"), ("[", "]")] as [(Character, Character)] {
            guard let first = trimmed.firstIndex(of: pair.0), let last = trimmed.lastIndex(of: pair.1), first < last else { continue }
            let sub = String(trimmed[first...last])
            guard let subData = sub.data(using: .utf8) else { continue }
            if let list = try? JSONDecoder().decode([ThirdPartySource].self, from: subData), !list.isEmpty {
                return list
            }
            if let single = try? JSONDecoder().decode(ThirdPartySource.self, from: subData) {
                return [single]
            }
        }
        return []
    }

    /// 将 Huibq keep-alive 等洛雪 musicUrl 脚本转换为 Beans 原生配置，不执行任意 JavaScript。
    private func parseLXScript(_ text: String) -> [ThirdPartySource]? {
        guard text.contains("globalThis.lx"),
              text.contains("musicUrl"),
              let apiURL = firstCapture(#"const\s+API_URL\s*=\s*['\"]([^'\"]+)['\"]"#, in: text) else { return nil }
        let apiKey = firstCapture(#"const\s+API_KEY\s*=\s*['\"]([^'\"]+)['\"]"#, in: text) ?? ""
        var sources: [ThirdPartySource] = []
        if text.range(of: #"\bwy\s*:"#, options: .regularExpression) != nil {
            sources.append(ThirdPartySource(
                name: "Huibq 洛雪源 · 网易云",
                kind: "lx-script",
                template: apiURL,
                headers: ["source": "wy", "quality": "320k", "apiKey": apiKey]
            ))
        }
        if text.range(of: #"\btx\s*:"#, options: .regularExpression) != nil {
            sources.append(ThirdPartySource(
                name: "Huibq 洛雪源 · QQ音乐",
                kind: "lx-script",
                template: apiURL,
                headers: ["source": "tx", "quality": "320k", "apiKey": apiKey]
            ))
        }
        return sources
    }

    /// 兼容 ikun 等新式 LX 音源：POST /music/url，body = source/musicId/quality。
    private func parseLXPostMusicURLScript(_ text: String) -> [ThirdPartySource]? {
        guard looksLikeLXScript(text),
              text.contains("EVENT_NAMES.request"),
              text.contains("musicUrl"),
              text.contains("/music/url") else { return nil }
        guard let apiURL = firstCapture(#"(?:const|let|var)\s+API_URL\s*=\s*['\"]([^'\"]+)['\"]"#, in: text)
                ?? firstCapture(#"['\"](https?://[^'\"]+)['\"]\s*\+\s*['\"]/music/url['\"]"#, in: text)
                ?? firstCapture(#"['\"](https?://[^'\"]+/music/url)['\"]"#, in: text) else { return nil }

        let scriptName = firstCapture(#"@name\s+([^\r\n]+)"#, in: text)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "LX POST 音源"
        let apiKey = firstCapture(#"(?:const|let|var)\s+API_KEY\s*=\s*['\"]([^'\"]*)['\"]"#, in: text) ?? ""
        let supported: [(code: String, name: String)] = [("wy", "网易云"), ("tx", "QQ音乐"), ("kg", "酷狗音乐")]
        let declared = declaredLXProviders(in: text)
        let providers = supported.filter { declared.isEmpty || declared.contains($0.code) }
        guard !providers.isEmpty else { return nil }

        let template = apiURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return providers.map { provider in
            ThirdPartySource(
                name: "\(scriptName) · \(provider.name)",
                kind: "lx-post-json",
                template: template,
                urlPath: "url|data.url|data.play_url|data.music_url|music_url|play_url",
                headers: ["source": provider.code, "quality": "flac", "apiKey": apiKey]
            )
        }
    }

    /// 将“非常刀”等 LX 事件脚本里声明的直链接口转换为 Beans 模板配置，不执行任意 JavaScript。
    private func parseLXEventScript(_ text: String) -> [ThirdPartySource]? {
        guard looksLikeLXScript(text),
              text.contains("EVENT_NAMES.request"),
              text.contains("musicUrl") else { return nil }

        var sources: [ThirdPartySource] = []
        if let qqAPI = firstCapture(#"const\s+SUYIN_QQ_API\s*=\s*['\"]([^'\"]+)['\"]"#, in: text),
           let qqKey = firstCapture(#"const\s+SUYIN_QQ_KEY\s*=\s*['\"]([^'\"]+)['\"]"#, in: text) {
            sources.append(ThirdPartySource(
                name: "LX 脚本 · QQ 溯音",
                kind: "template-api",
                template: "\(qqAPI)?key=\(qqKey)&type=json&br=5&n=1&mid={id}",
                urlPath: "data.music|data.url|url",
                headers: ["source": "tx"]
            ))
        }
        if let xinghaiAPI = firstCapture(#"const\s+XINGHAI_API\s*=\s*['\"]([^'\"]+)['\"]"#, in: text) {
            sources.append(ThirdPartySource(
                name: "LX 脚本 · 网易云星海",
                kind: "template-api",
                template: "\(xinghaiAPI)&types=url&source=netease&id={id}&br=999",
                urlPath: "url",
                headers: ["source": "wy"]
            ))
        }
        if let chkszAPI = firstCapture(#"const\s+CHKSZ_API\s*=\s*['\"]([^'\"]+)['\"]"#, in: text) {
            sources.append(ThirdPartySource(
                name: "LX 脚本 · 网易云 CHKSZ",
                kind: "template-api",
                template: "\(chkszAPI)/163_music?id={id}&level=lossless",
                urlPath: "data.url|url",
                headers: ["source": "wy", "Referer": "https://cp.chksz.top/"]
            ))
        }
        return sources.isEmpty ? nil : sources
    }

    /// 星海 2.x 事件式 LX 脚本：读取 MAIN_API_BASE，不执行脚本，转换成按平台直连模板。
    private func parseXinghaiEventScript(_ text: String) -> [ThirdPartySource]? {
        guard text.contains("globalThis.lx"),
              text.contains("EVENT_NAMES.request"),
              text.contains("MAIN_API_BASE"),
              let mainAPI = firstCapture(#"const\s+MAIN_API_BASE\s*=\s*['\"]([^'\"]+)['\"]"#, in: text) else { return nil }

        let platformMap: [(code: String, api: String, name: String)] = [
            ("wy", "netease", "网易云"),
            ("tx", "tencent", "QQ音乐"),
            ("kg", "kugou", "酷狗音乐"),
            ("kw", "kuwo", "酷我音乐"),
            ("mg", "migu", "咪咕音乐"),
        ]
        let declaredPlatforms = firstCapture(#"const\s+ALL_PLATFORMS\s*=\s*\[([^\]]+)\]"#, in: text) ?? ""
        let urlPath = "url|data.url|music_url|data.music_url|data.music_url.url|play_url|data.play_url"
        let base = mainAPI.contains("?") ? mainAPI : "\(mainAPI)?"
        let separator = base.hasSuffix("?") || base.hasSuffix("&") ? "" : "&"
        let quality = "999"

        var sources: [ThirdPartySource] = []
        for item in platformMap where declaredPlatforms.isEmpty || declaredPlatforms.contains("'\(item.code)'") || declaredPlatforms.contains("\"\(item.code)\"") {
            sources.append(ThirdPartySource(
                name: "星海音源 · \(item.name)",
                kind: "template-api",
                template: "\(base)\(separator)types=url&source=\(item.api)&id={id}&br=\(quality)",
                urlPath: urlPath,
                headers: ["source": item.code, "quality": "flac"]
            ))
        }
        return sources.isEmpty ? nil : sources
    }

    /// 混淆 LX 脚本兜底：无法静态转换接口时，保存脚本文本，由播放解析时在后台 JSContext 执行 musicUrl。
    private func parseRawLXScript(_ text: String) -> [ThirdPartySource]? {
        guard looksLikeLXScript(text),
              text.contains("EVENT_NAMES") else { return nil }
        let scriptName = firstCapture(#"@name\s+([^\r\n]+)"#, in: text)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "导入 LX 脚本"
        let providers: [(code: String, name: String)] = [("wy", "网易云"), ("tx", "QQ音乐"), ("kg", "酷狗音乐")]
        return providers.map { provider in
            ThirdPartySource(
                name: "\(scriptName) · \(provider.name)",
                kind: "lx-raw-script",
                template: text,
                urlPath: "url|data.url|data.play_url|data.music_url|music_url|play_url",
                headers: ["source": provider.code, "quality": "flac"]
            )
        }
    }

    private func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func looksLikeLXScript(_ text: String) -> Bool {
        text.contains("globalThis.lx") || text.contains("globalThis['lx']") || text.contains("globalThis[\"lx\"]")
    }

    private func declaredLXProviders(in text: String) -> Set<String> {
        let supported = ["wy", "tx", "kg"]
        if let json = firstCapture(#"MUSIC_QUALITY\s*=\s*JSON\.parse\(\s*'([^']+)'\s*\)"#, in: text),
           let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return Set(obj.keys.filter { supported.contains($0) })
        }
        return Set(supported.filter { code in
            text.contains("\"\(code)\"") || text.contains("'\(code)'") || text.range(of: #"\b\#(code)\s*:"#, options: .regularExpression) != nil
        })
    }
}

// MARK: - 音源文件选择器（UIDocumentPicker 封装，可选 .js / .json / .txt）

struct SourceFilePicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: SourceFilePicker
        init(_ parent: SourceFilePicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
