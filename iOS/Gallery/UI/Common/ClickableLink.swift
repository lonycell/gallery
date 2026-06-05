/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/ClickableLink.kt

import SwiftUI

/// Builds an `AttributedString` with a coloured, underlined link. Mirrors `buildTrackableUrlAnnotatedString()`.
func buildTrackableUrlAnnotatedString(url: String, linkText: String, linkColor: Color) -> AttributedString {
  var str = AttributedString(linkText)
  str.link = URL(string: url)
  str.foregroundColor = UIColor(linkColor)
  str.underlineStyle = .single
  return str
}

/// Row with optional leading icon + underlined link text. Mirrors `ClickableLink`.
struct ClickableLink: View {
  let url: String
  let linkText: String
  var icon: String? = nil    // SF Symbol name
  var textAlignment: TextAlignment = .center

  @Environment(\.customColors) private var customColors

  var body: some View {
    HStack(spacing: 6) {
      if let icon = icon {
        Image(systemName: icon)
          .frame(width: 16, height: 16)
      }
      let str = buildTrackableUrlAnnotatedString(url: url, linkText: linkText, linkColor: customColors.linkColor)
      Text(str)
        .font(AppTypography.bodyMedium)
        .multilineTextAlignment(textAlignment)
        .tint(customColors.linkColor)
    }
  }
}
