/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/modelitem/AICoreAccessPanel.kt

import SwiftUI

/// Access panel shown when an AICore model is unavailable.
/// Mirrors `AICoreAccessPanel` composable.
struct AICoreAccessPanel: View {
  @Environment(\.galleryColors) private var colors

  var body: some View {
    HStack(spacing: 0) {
      Text(Str.aicoreAccessPanelTitle)
        .font(AppTypography.bodyMedium)
        .foregroundStyle(colors.onSurfaceVariant)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 12)

      Button(Str.aicoreAccessPanelButton) {
        if let url = URL(string: "https://developers.google.com/ml-kit/genai/aicore-dev-preview") {
          UIApplication.shared.open(url)
        }
      }
      .font(AppTypography.labelLarge)
      .foregroundStyle(colors.primary)
      .padding(.horizontal, 8)
    }
    .padding(16)
    .background(colors.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: 12))
  }
}
