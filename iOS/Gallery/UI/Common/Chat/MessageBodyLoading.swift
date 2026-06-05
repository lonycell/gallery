/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyLoading.kt

import SwiftUI

/// Animated loading indicator for an in-progress agent message.
struct MessageBodyLoading: View {
  var message: ChatMessageLoading?

  @State private var iconAlpha: Double = 0.3
  @Environment(\.galleryColors) private var colors

  var body: some View {
    HStack {
      ProgressView()
        .progressViewStyle(.circular)

      if let label = message?.extraProgressLabel, !label.isEmpty {
        HStack(spacing: 6) {
          Image(systemName: "wrench.and.screwdriver.fill")
            .resizable().scaledToFit()
            .frame(width: 16, height: 16)
            .opacity(iconAlpha)
            .foregroundColor(colors.primary)
            .onAppear { startFlashing() }
          Text(label)
            .font(.caption)
            .foregroundColor(colors.onSurfaceVariant.opacity(0.8))
        }
      } else {
        Spacer()
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private func startFlashing() {
    withAnimation(
      Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
    ) {
      iconAlpha = 1.0
    }
  }
}
