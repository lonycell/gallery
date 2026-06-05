/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/FloatingBanner.kt

import SwiftUI

/// Animated banner that slides in/out vertically. Mirrors `FloatingBanner`.
struct FloatingBanner: View {
  let visible: Bool
  let text: String

  @Environment(\.galleryColors) private var colors

  var body: some View {
    if visible {
      HStack {
        Text(text)
          .font(AppTypography.bodyMedium)
          .foregroundStyle(colors.onSurfaceVariant)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(colors.surfaceVariant)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .transition(.asymmetric(
        insertion: .move(edge: .top).combined(with: .opacity),
        removal: .move(edge: .top).combined(with: .opacity)
      ))
    }
  }
}
