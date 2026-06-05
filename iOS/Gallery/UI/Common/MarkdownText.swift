/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/MarkdownText.kt

import SwiftUI

/// Renders Markdown-formatted text.
/// Uses `AttributedString(markdown:)` for inline formatting; falls back to plain Text.
/// Mirrors the `MarkdownText` Composable.
struct MarkdownText: View {
  let text: String
  var smallFontSize: Bool = false
  var textColor: Color? = nil
  var linkColor: Color? = nil

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  private var resolvedTextColor: Color {
    textColor ?? colors.onSurface
  }

  private var resolvedLinkColor: Color {
    linkColor ?? customColors.linkColor
  }

  private var fontSize: CGFloat {
    smallFontSize ? 14 : 16
  }

  private var lineHeight: CGFloat {
    smallFontSize ? fontSize * 1.4 : fontSize * 1.5
  }

  var body: some View {
    let attributed = makeAttributed()
    Text(attributed)
      .font(AppFont.font(size: fontSize))
      .lineSpacing(lineHeight - fontSize)
      .foregroundStyle(resolvedTextColor)
      .tint(resolvedLinkColor)
      .textSelection(.enabled)
  }

  private func makeAttributed() -> AttributedString {
    do {
      var options = AttributedString.MarkdownParsingOptions()
      options.interpretedSyntax = .inlineOnlyPreservingWhitespace
      var attributed = try AttributedString(markdown: text, options: options)
      // Apply link colour
      for run in attributed.runs {
        if run.link != nil {
          attributed[run.range].foregroundColor = UIColor(resolvedLinkColor)
        }
      }
      return attributed
    } catch {
      return AttributedString(text)
    }
  }
}
