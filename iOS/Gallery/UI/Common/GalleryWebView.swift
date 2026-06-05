/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/GalleryWebView.kt
//
// NOTE: Android used WebView + WebViewAssetLoader to serve local assets and
// handle camera/audio permission requests inside the WebView. iOS uses WKWebView
// via UIViewRepresentable with equivalent local-file and URL-scheme support.
// Camera/mic permissions inside WKWebView are handled by setting
// `mediaTypesRequiringUserActionForPlayback = []` and providing a
// WKUIDelegate that calls the decisionHandler with `.grant` when permission
// is requested. App-level camera/mic NSUsageDescription entries must be present
// in Info.plist.

import SwiftUI
import WebKit

// MARK: - GalleryWebView

/// A reusable SwiftUI wrapper around WKWebView. Mirrors `GalleryWebView` composable.
struct GalleryWebView: UIViewRepresentable {
  var initialUrl: String? = nil
  var useIframeWrapper: Bool = false
  var allowRequestPermission: Bool = false
  var onWebViewCreated: ((WKWebView) -> Void)? = nil
  var onConsoleMessage: ((String) -> Void)? = nil

  func makeCoordinator() -> Coordinator {
    Coordinator(
      allowRequestPermission: allowRequestPermission,
      onConsoleMessage: onConsoleMessage
    )
  }

  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.mediaTypesRequiringUserActionForPlayback = []
    // Allow inline media playback (important for audio/video in web content)
    config.allowsInlineMediaPlayback = true

    let webView = WKWebView(frame: .zero, configuration: config)
    webView.navigationDelegate = context.coordinator
    webView.uiDelegate = context.coordinator
    context.coordinator.webView = webView

    // Inject a JS console-message bridge so we can observe console.log output.
    if onConsoleMessage != nil {
      let script = WKUserScript(
        source: """
          (function() {
            var origLog = console.log;
            console.log = function(msg) {
              window.webkit.messageHandlers.consoleLog.postMessage(msg);
              origLog.apply(console, arguments);
            };
          })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
      )
      config.userContentController.addUserScript(script)
      config.userContentController.add(context.coordinator, name: "consoleLog")
    }

    if let urlStr = initialUrl {
      if useIframeWrapper {
        let html = iframeWrapper.replacingOccurrences(of: "___", with: urlStr)
        webView.loadHTMLString(html, baseURL: nil)
      } else if let url = URL(string: urlStr) {
        webView.load(URLRequest(url: url))
      }
    }

    onWebViewCreated?(webView)
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {}

  // MARK: - Coordinator

  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var webView: WKWebView?
    let allowRequestPermission: Bool
    let onConsoleMessage: ((String) -> Void)?

    init(allowRequestPermission: Bool, onConsoleMessage: ((String) -> Void)?) {
      self.allowRequestPermission = allowRequestPermission
      self.onConsoleMessage = onConsoleMessage
    }

    // MARK: WKScriptMessageHandler
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
      if message.name == "consoleLog", let body = message.body as? String {
        onConsoleMessage?(body)
      }
    }

    // MARK: WKUIDelegate — camera / microphone permissions inside WKWebView
    func webView(
      _ webView: WKWebView,
      requestMediaCapturePermissionFor origin: WKSecurityOrigin,
      initiatedByFrame frame: WKFrameInfo,
      type: WKMediaCaptureType,
      decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
      // NOTE: iOS 15+ API. If allowRequestPermission is false, deny.
      decisionHandler(allowRequestPermission ? .grant : .deny)
    }
  }
}

// MARK: - Private helpers

private let iframeWrapper = """
<html>
  <body style="margin:0;padding:0;">
    <iframe
        width="100%"
        height="100%"
        src="___"
        frameborder="0"
        style="border:0;">
    </iframe>
  </body>
</html>
"""
