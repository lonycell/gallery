/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/SmallFilledTonalButton.kt

import SwiftUI

/// Small tonal-filled button with an optional icon. Mirrors `SmallFilledTonalButton`.
struct SmallFilledTonalButton: View {
  let onClick: () -> Void
  var label: String = ""
  var systemImage: String? = nil
  var iconSize: CGFloat = 18
  var enabled: Bool = true

  @Environment(\.galleryColors) private var colors

  var body: some View {
    Button(action: onClick) {
      HStack(spacing: 4) {
        if let img = systemImage {
          Image(systemName: img)
            .frame(width: iconSize, height: iconSize)
        }
        if !label.isEmpty {
          Text(label)
            .font(AppTypography.labelMedium)
        }
      }
    }
    .buttonStyle(.borderedProminent)
    .tint(colors.secondaryContainer)
    .foregroundStyle(colors.onSecondaryContainer)
    .frame(height: 32)
    .disabled(!enabled)
  }
}
