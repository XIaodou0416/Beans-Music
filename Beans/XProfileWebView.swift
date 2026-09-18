import SwiftUI
import WebKit

/// Hosts the bundled profile page while keeping image persistence in the app sandbox.
struct XProfileWebView: UIViewRepresentable {
    var listeningDuration: String = "--"
    var playCount: String = "--"

    func makeCoordinator() -> Coordinator {
        Coordinator(listeningDuration: listeningDuration, playCount: playCount)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "beansFileBridge")
        controller.addUserScript(WKUserScript(
            source: """
            (() => {
              const pending = new Map();
              let sequence = 0;
              window.__beansBridgeResolve = (id, value) => {
                const resolve = pending.get(id);
                if (!resolve) return;
                pending.delete(id);
                resolve(value);
              };
              const request = (action, fileName, dataURL) => new Promise(resolve => {
                const id = `beans-${Date.now()}-${sequence++}`;
                pending.set(id, resolve);
                window.webkit.messageHandlers.beansFileBridge.postMessage({
                  action, fileName, dataURL: dataURL || null, requestID: id
                });
              });
              window.tm = {
                saveFile: (fileName, dataURL) => request('save', fileName, dataURL),
                loadFile: fileName => request('load', fileName)
              };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator

        if let url = Bundle.main.url(forResource: "XProfile", withExtension: "html", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: "XProfile", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.listeningDuration = listeningDuration
        context.coordinator.playCount = playCount
        context.coordinator.syncStats(to: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let fileManager = FileManager.default
        var listeningDuration: String
        var playCount: String
        private var didFinishLoading = false

        init(listeningDuration: String, playCount: String) {
            self.listeningDuration = listeningDuration
            self.playCount = playCount
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishLoading = true
            syncStats(to: webView)
        }

        func syncStats(to webView: WKWebView) {
            guard didFinishLoading,
                  let durationData = try? JSONSerialization.data(withJSONObject: listeningDuration),
                  let countData = try? JSONSerialization.data(withJSONObject: playCount),
                  let duration = String(data: durationData, encoding: .utf8),
                  let count = String(data: countData, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.__beansUpdateStats && window.__beansUpdateStats({listeningDuration: \(duration), playCount: \(count)});")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "beansFileBridge",
                  let body = message.body as? [String: Any],
                  let action = body["action"] as? String,
                  let fileName = body["fileName"] as? String,
                  let requestID = body["requestID"] as? String,
                  let webView = message.webView,
                  let fileURL = storageURL(for: fileName) else { return }

            switch action {
            case "save":
                guard let dataURL = body["dataURL"] as? String else {
                    resolve(requestID, value: false, in: webView)
                    return
                }
                do {
                    try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    guard let data = dataURL.data(using: .utf8) else {
                        resolve(requestID, value: false, in: webView)
                        return
                    }
                    try data.write(to: fileURL, options: .atomic)
                    resolve(requestID, value: true, in: webView)
                } catch {
                    resolve(requestID, value: false, in: webView)
                }
            case "load":
                if let value = try? String(contentsOf: fileURL, encoding: .utf8) {
                    resolve(requestID, value: value, in: webView)
                } else {
                    resolve(requestID, value: NSNull(), in: webView)
                }
            default:
                resolve(requestID, value: false, in: webView)
            }
        }

        private func storageURL(for fileName: String) -> URL? {
            let allowed = ["zhou-x-avatar.txt", "zhou-x-banner.txt"]
            guard allowed.contains(fileName),
                  let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            return base.appendingPathComponent("BeansXProfile", isDirectory: true).appendingPathComponent(fileName)
        }

        private func resolve(_ requestID: String, value: Any, in webView: WKWebView) {
            guard JSONSerialization.isValidJSONObject(["value": value]) || value is NSNull || value is String || value is Bool else { return }
            let data = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) ?? Data("null".utf8)
            let json = String(data: data, encoding: .utf8) ?? "null"
            let escapedID = requestID.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("window.__beansBridgeResolve('\(escapedID)', \(json));")
        }
    }
}
