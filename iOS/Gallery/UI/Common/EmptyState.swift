/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/EmptyState.kt

import SwiftUI

/// Configuration for the optional action button in `EmptyState`.
struct EmptyStateButtonConfig {
  let buttonLabel: String
  let buttonSystemImage: String?
  let onButtonClick: () -> Void
  let extraContent: AnyView

  init(
    buttonLabel: String,
    buttonSystemImage: String? = nil,
    onButtonClick: @escaping () -> Void = {},
    extraContent: AnyView = AnyView(EmptyView())
  ) {
    self.buttonLabel = buttonLabel
    self.buttonSystemImage = buttonSystemImage
    self.onButtonClick = onButtonClick
    self.extraContent = extraContent
  }
}

/// Empty-state view with icon, title, description, and optional button. Mirrors `EmptyState`.
struct EmptyState: View {
  let systemImage: String
  let title: String
  let description: String
  var buttonConfig: EmptyStateButtonConfig? = nil

  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: systemImage)
        .resizable()
        .scaledToFit()
        .frame(width: 56, height: 56)
        .foregroundStyle(colors.onSurfaceVariant)

      Text(title)
        .font(AppTypography.headlineMedium)
        .foregroundStyle(colors.onSurface)
        .multilineTextAlignment(.center)

      Text(description)
        .font(AppTypography.bodyLarge)
        .foregroundStyle(colors.onSurfaceVariant)
        .multilineTextAlignment(.center)

      if let cfg = buttonConfig {
        ZStack {
          Button(action: cfg.onButtonClick) {
            HStack(spacing: 8) {
              if let img = cfg.buttonSystemImage {
                Image(systemName: img)
                  .frame(width: 20, height: 20)
              }
              Text(cfg.buttonLabel)
            }
            .padding(SMALL_BUTTON_CONTENT_PADDING)
          }
          .buttonStyle(.borderedProminent)

          cfg.extraContent
        }
      }
    }
    .padding(.horizontal, 48)
  }
}
