/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageActionButton.kt

import SwiftUI

/// A small pill-shaped action button shown below a chat message bubble.
struct MessageActionButton: View {
  let label: String
  let systemImage: String
  let onClick: () -> Void
  var enabled: Bool = true

  @Environment(\.galleryColors) private var colors

  var body: some View {
    Button(action: onClick) {
      HStack(spacing: 4) {
        Image(systemName: systemImage)
          .resizable()
          .scaledToFit()
          .frame(width: 14, height: 14)
        Text(label)
          .font(.caption)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
    }
    .buttonStyle(.plain)
    .background(
      enabled
        ? colors.secondaryContainer
        : colors.surfaceContainerHigh
    )
    .clipShape(Capsule())
    .opacity(enabled ? 1.0 : 0.3)
    .disabled(!enabled)
  }
}
