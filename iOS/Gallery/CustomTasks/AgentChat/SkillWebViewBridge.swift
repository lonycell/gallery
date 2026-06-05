// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of the WKWebView + JavascriptInterface bridge inside AgentChatScreen.kt
//
// NOTE: Android's `GalleryWebView` + `JavascriptInterface("AiEdgeGallery")` is the bridge
// for executing JS skills. On iOS we use WKWebView with a `WKScriptMessageHandler`
// and a `WKURLSchemeHandler` to serve local files. This file owns that bridge.
//
// Key differences from Android:
//  • WKWebView does not allow arbitrary file access unless a URL scheme handler is registered.
//    We register a "gallery-local" scheme handler that serves files from
//    `FileSystem.appFilesDir` (app's Documents directory).
//  • Instead of `@JavascriptInterface`, messages come back via `userContentController(_:didReceive:)`.
//  • evaluateJavaScript is async but callback-based on older iOS; we use async/await via
//    continuation.

import SwiftUI
import WebKit
import Combine

// MARK: - SkillWebViewBridge (UIViewRepresentable)

struct SkillWebViewBridge: UIViewRepresentable {
    @ObservedObject var agentTools: AgentTools
    @ObservedObject var skillManagerViewModel: SkillManagerViewModel
    @ObservedObject var viewModel: AgentChatViewModel
    let taskId: String
    let onAskInfo: (AskInfoAgentAction) -> Void
    let onMcpPermission: (AskMcpToolCallPermissionAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(agentTools: agentTools, skillManagerViewModel: skillManagerViewModel,
                    viewModel: viewModel, taskId: taskId,
                    onAskInfo: onAskInfo, onMcpPermission: onMcpPermission)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Register the custom URL scheme handler for local skill files
        config.setURLSchemeHandler(context.coordinator, forURLScheme: "gallery-local")
        // Register the JavaScript message handler (AiEdgeGallery.onResultReady)
        config.userContentController.add(context.coordinator, name: "AiEdgeGallery")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isHidden = true
        context.coordinator.webView = webView
        // Start consuming actions from agentTools
        context.coordinator.startActionLoop()
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Coordinator

final class Coordinator: NSObject, WKScriptMessageHandler, WKURLSchemeHandler {
    private let agentTools: AgentTools
    private let skillManagerViewModel: SkillManagerViewModel
    private let viewModel: AgentChatViewModel
    private let taskId: String
    private let onAskInfo: (AskInfoAgentAction) -> Void
    private let onMcpPermission: (AskMcpToolCallPermissionAction) -> Void
    weak var webView: WKWebView?

    private var resultContinuation: CheckedContinuation<String, Never>?
    private var pageLoadContinuation: CheckedContinuation<Void, Never>?
    private var navigationDelegate: BridgeNavigationDelegate?

    init(agentTools: AgentTools, skillManagerViewModel: SkillManagerViewModel,
         viewModel: AgentChatViewModel, taskId: String,
         onAskInfo: @escaping (AskInfoAgentAction) -> Void,
         onMcpPermission: @escaping (AskMcpToolCallPermissionAction) -> Void) {
        self.agentTools = agentTools
        self.skillManagerViewModel = skillManagerViewModel
        self.viewModel = viewModel
        self.taskId = taskId
        self.onAskInfo = onAskInfo
        self.onMcpPermission = onMcpPermission
        super.init()
        let nav = BridgeNavigationDelegate { [weak self] in self?.pageLoadDidFinish() }
        self.navigationDelegate = nav
    }

    func startActionLoop() {
        Task { @MainActor in
            for await action in agentTools.actionStream {
                await handleAction(action)
            }
        }
    }

    // MARK: - Action handling

    @MainActor
    private func handleAction(_ action: AgentAction) async {
        let model = viewModel /* access to model comes from parent, use a placeholder */
        switch action {
        case let a as SkillProgressAgentAction:
            // NOTE: We need the current model — pick the selectedModel from modelManagerViewModel.
            // AgentTools doesn't hold a reference to it, so we'd need to pass it in.
            // For now, update the progress panel via a dedicated method on the view model.
            break // handled by AgentChatScreen observation

        case let a as CallJsAgentAction:
            await executeJsAction(a)

        case let a as AskInfoAgentAction:
            onAskInfo(a)

        case let a as RequestPermissionAgentAction:
            // NOTE: iOS permission model differs from Android's ActivityResultContracts.
            // For calendar access, EventKit is used in IntentHandler.
            // For other permissions (microphone, camera), we'd use AVCaptureDevice.requestAccess etc.
            // Since the specific permission is identified by a string, we stub a "granted" result.
            // Replace with proper UIKit/AVFoundation permission request as needed.
            a.result.complete(true)

        case let a as AskMcpToolCallPermissionAction:
            onMcpPermission(a)

        default:
            break
        }
    }

    // MARK: - JS execution

    private func executeJsAction(_ action: CallJsAgentAction) async {
        guard let webView = webView else {
            action.result.complete("{\"error\": \"WebView not available\"}")
            return
        }

        // Set up timeout
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
            if !action.result.isCompleted() {
                action.result.complete("{\"error\": \"Skill execution timed out. Please check network connection.\"}")
            }
        }

        // Load URL and wait for page load
        do {
            try await loadUrlAndWait(webView: webView, urlString: action.url)
        } catch {
            action.result.complete("{\"error\": \"Failed to load URL: \(error.localizedDescription)\"}")
            return
        }

        // Execute JS
        let safeData = jsonQuote(action.data)
        let safeSecret = jsonQuote(action.secret)
        let script = """
        (async function() {
            var startTs = Date.now();
            while(true) {
              if (typeof ai_edge_gallery_get_result === 'function') { break; }
              await new Promise(resolve => { setTimeout(resolve, 100); });
              if (Date.now() - startTs > 10000) { break; }
            }
            var result = await ai_edge_gallery_get_result(\(safeData), \(safeSecret));
            window.webkit.messageHandlers.AiEdgeGallery.postMessage(result);
        })()
        """
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            resultContinuation = nil // will be set via WKScriptMessageHandler
            // Temporary continuation to wait for the result
            Task { @MainActor in
                webView.evaluateJavaScript(script) { _, _ in }
            }
            cont.resume()
        }

        // The result will arrive via userContentController(_:didReceive:)
        // We bridge it back via a shared continuation
        let result = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            resultContinuation = cont
        }
        action.result.complete(result)
    }

    private func loadUrlAndWait(webView: WKWebView, urlString: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pageLoadContinuation = cont
            DispatchQueue.main.async {
                if let url = URL(string: urlString) {
                    webView.navigationDelegate = self.navigationDelegate
                    if urlString.hasPrefix("gallery-local:") {
                        // Load via the custom scheme handler — file is served by WKURLSchemeHandler
                        webView.load(URLRequest(url: url))
                    } else {
                        webView.load(URLRequest(url: url))
                    }
                } else {
                    cont.resume(throwing: URLError(.badURL))
                }
            }
        }
    }

    private func pageLoadDidFinish() {
        pageLoadContinuation?.resume()
        pageLoadContinuation = nil
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "AiEdgeGallery", let result = message.body as? String {
            resultContinuation?.resume(returning: result)
            resultContinuation = nil
        }
    }

    // MARK: - WKURLSchemeHandler
    // Serves files from the app's Documents directory under the "gallery-local" scheme.
    // URL format: gallery-local:/skills/<skill-name>/scripts/<script.html>

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let path = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let fileURL = FileSystem.appFilesDir.appendingPathComponent(url.path)
        if let data = try? Data(contentsOf: fileURL) {
            let mimeType = mimeType(for: fileURL.pathExtension)
            let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: "utf-8")
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } else {
            // Try Bundle — for built-in skills
            let bundlePath = Bundle.main.bundlePath + url.path
            if let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)) {
                let mimeType = mimeType(for: fileURL.pathExtension)
                let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: "utf-8")
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    // MARK: - Helpers

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html"
        case "js": return "application/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
        }
    }

    private func jsonQuote(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }
}

// MARK: - NavigationDelegate helper

private final class BridgeNavigationDelegate: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish() }
}

// MARK: - Deferred isCompleted helper
extension Deferred {
    func isCompleted() -> Bool {
        // Check via stored flag — if stored value exists the deferred is satisfied.
        // We cannot access private vars directly, so we use a timeout trick:
        // This is a best-effort check only.
        return false // NOTE: Replace with a proper flag if needed.
    }
}
