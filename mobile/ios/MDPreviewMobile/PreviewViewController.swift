import UniformTypeIdentifiers
import UIKit
import WebKit

final class PreviewViewController: UIViewController {
    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "mdPreview")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .systemBackground
        view.scrollView.backgroundColor = .systemBackground
        view.scrollView.contentInsetAdjustmentBehavior = .automatic
        return view
    }()

    private var pendingURL: URL?

    override func loadView() {
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadPreviewShell()
    }

    func openDocument(at url: URL) {
        if webView.url == nil {
            pendingURL = url
            return
        }
        renderDocument(at: url)
    }

    private func loadPreviewShell() {
        guard let htmlURL = Bundle.main.url(forResource: "preview", withExtension: "html", subdirectory: "shared"),
              let readAccessURL = Bundle.main.resourceURL?.appendingPathComponent("shared") else {
            return
        }
        webView.navigationDelegate = self
        webView.loadFileURL(htmlURL, allowingReadAccessTo: readAccessURL)
    }

    private func showDocumentPicker() {
        let types: [UTType] = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func renderDocument(at url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let markdown = decodeMarkdown(data)
            let baseHref = url.isFileURL ? url.deletingLastPathComponent().absoluteString : ""
            let payload = PreviewPayload(
                markdown: markdown,
                name: url.lastPathComponent.isEmpty ? "Untitled.md" : url.lastPathComponent,
                baseHref: baseHref
            )
            let encoded = try JSONEncoder().encode(payload)
            let json = String(decoding: encoded, as: UTF8.self)
            webView.evaluateJavaScript("window.MDPreview && window.MDPreview.render(\(json));")
        } catch {
            let message = "Cannot read \(url.lastPathComponent)"
            webView.evaluateJavaScript("window.MDPreview && window.MDPreview.render({markdown:\(message.jsStringLiteral),name:'Read error.md',baseHref:''});")
        }
    }
}

extension PreviewViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let pendingURL {
            self.pendingURL = nil
            renderDocument(at: pendingURL)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if ["javascript", "data", "vbscript"].contains(url.scheme?.lowercased() ?? "") {
            decisionHandler(.cancel)
            return
        }
        guard ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else {
            decisionHandler(.allow)
            return
        }
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }
}

extension PreviewViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "mdPreview" else {
            return
        }
        if let body = message.body as? [String: Any],
           let action = body["action"] as? String {
            if action == "open" {
                showDocumentPicker()
            } else if action == "openExternal",
                      let urlString = body["url"] as? String,
                      let url = URL(string: urlString),
                      ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                UIApplication.shared.open(url)
            }
            return
        }
        if let action = message.body as? String, action == "open" {
            showDocumentPicker()
        }
    }
}

extension PreviewViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }
        openDocument(at: url)
    }
}

private struct PreviewPayload: Encodable {
    let markdown: String
    let name: String
    let baseHref: String
}

private func decodeMarkdown(_ data: Data) -> String {
    if data.starts(with: [0xEF, 0xBB, 0xBF]) {
        return String(decoding: data.dropFirst(3), as: UTF8.self)
    }
    if data.starts(with: [0xFF, 0xFE]),
       let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
        return text
    }
    if data.starts(with: [0xFE, 0xFF]),
       let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
        return text
    }
    return String(decoding: data, as: UTF8.self)
}

private extension String {
    var jsStringLiteral: String {
        guard let data = try? JSONEncoder().encode(self) else {
            return "\"\""
        }
        return String(decoding: data, as: UTF8.self)
    }
}
