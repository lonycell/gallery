/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyWebview.kt
// NOTE: Android used a custom ChatGalleryWebView (AndroidView wrapping WebView).
// iOS bridge uses WKWebView via UIViewRepresentable. The full-screen sheet
// mirrors the ModalBottomSheet from Android.

import SwiftUI
import WebKit

struct MessageBodyWebview: View {
  let message: ChatMessageWebView

  @State private var showFullScreen = false
  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Inline web view
      ChatGalleryWebView(urlString: message.url)
        .frame(maxWidth: .infinity)
        .aspectRatio(CGFloat(message.aspectRatio), contentMode: .fit)

      // "View in full screen" chip
      Button {
        showFullScreen = true
      } label: {
        Label("전체 화면으로 보기", systemImage: "arrow.up.left.and.arrow.down.right")
          .font(.caption)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .overlay(RoundedRectangle(cornerRadius: 16).stroke(colors.outline, lineWidth: 1))
      }
      .buttonStyle(.plain)
      .padding(.top, 8)
    }
    .sheet(isPresented: $showFullScreen) {
      ZStack(alignment: .topTrailing) {
        ChatGalleryWebView(urlString: message.url)
          .ignoresSafeArea()
        Button {
          showFullScreen = false
        } label: {
          Image(systemName: "xmark")
            .padding(10)
            .background(colors.surfaceContainer)
            .clipShape(Circle())
            .overlay(Circle().stroke(colors.outlineVariant.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .padding(.trailing, 8)
      }
    }
  }
}

/// NOTE: WKWebView-based SwiftUI wrapper. Mirrors Android's ChatGalleryWebView (AndroidView + WebView).
struct ChatGalleryWebView: UIViewRepresentable {
  let urlString: String

  func makeUIView(context: Context) -> WKWebView {
    let webView = WKWebView()
    webView.scrollView.isScrollEnabled = true
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {
    if let url = URL(string: urlString) {
      let request = URLRequest(url: url)
      uiView.load(request)
    }
  }
}
