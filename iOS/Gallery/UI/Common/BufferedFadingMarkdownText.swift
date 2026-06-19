/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/BufferedFadingMarkdownText.kt

import SwiftUI

private let FADE_INTERVAL_MS: Double = 120

/// Two-layer crossfade markdown view that updates smoothly when text changes.
/// Mirrors `BufferedFadingMarkdownText`.
struct BufferedFadingMarkdownText: View {
  let text: String
  let inProgress: Bool

  @State private var text1: String = ""
  @State private var text2: String = ""
  @State private var alpha2: Double = 0
  @State private var showOverlay: Bool = true

  var body: some View {
    ZStack {
      // Layer 1 — base (fades out as overlay fades in)
      MarkdownText(text: text1)
        .opacity(1.0 - alpha2)

      // Layer 2 — overlay
      if showOverlay && !text2.isEmpty {
        MarkdownText(text: text2)
          .opacity(alpha2)
          .blendMode(.plusLighter)
          .accessibilityHidden(true)
      }
    }
    .task(id: text) {
      await updateText(newText: text)
    }
    .onChange(of: inProgress) { wasInProgress in
      // When inProgress flips false, hide overlay after 2x fade interval
      if !inProgress {
        _Concurrency.Task {
          try? await _Concurrency.Task.sleep(nanoseconds: UInt64(FADE_INTERVAL_MS * 2 * 1_000_000))
          showOverlay = false
        }
      }
    }
    .onAppear {
      text1 = text
    }
  }

  @MainActor
  private func updateText(newText: String) async {
    guard newText != text1 else { return }

    text2 = newText
    alpha2 = 0
    withAnimation(.linear(duration: FADE_INTERVAL_MS / 1000)) {
      alpha2 = 1
    }
    // Wait for animation
    try? await _Concurrency.Task.sleep(nanoseconds: UInt64(FADE_INTERVAL_MS * 1_000_000))
    text1 = newText
    // One frame pause then hide overlay
    try? await _Concurrency.Task.sleep(nanoseconds: 16_666_667)
    alpha2 = 0
  }
}
