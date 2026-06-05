/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/SmallOutlinedButton.kt

import SwiftUI

/// Small outlined button with optional icon. Mirrors `SmallOutlinedButton`.
struct SmallOutlinedButton: View {
  let onClick: () -> Void
  var label: String = ""
  var systemImage: String? = nil
  var iconSize: CGFloat = 18
  var enabled: Bool = true

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
    .buttonStyle(.bordered)
    .frame(height: 32)
    .disabled(!enabled)
  }
}
