// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/modelmanager/PromoBannerGm4.kt

import SwiftUI

/// Banner promoting Gemma 4, dismissible, with a "Read more" CTA.
/// Mirrors `PromoBannerGm4`.
struct PromoBannerGm4: View {
  let onDismiss: () -> Void

  @Environment(\.customColors) private var customColors
  @Environment(\.galleryColors) private var colors

  var body: some View {
    ZStack(alignment: .trailing) {
      // Background gradient banner
      VStack(alignment: .leading, spacing: 0) {
        Text("Gemma 4: now available")
          .font(AppTypography.titleMedium)
          .foregroundStyle(colors.onSurface)

        Text("Built from the same world-class technology as Gemini 3, Gemma 4 brings frontier intelligence to your mobile and edge devices.")
          .font(AppFont.font(size: 12))
          .lineSpacing(3)
          .foregroundStyle(colors.onSurface)
          .padding(.top, 4)

        HStack(spacing: 0) {
          Spacer()

          Button(action: onDismiss) {
            Text("Dismiss")
              .font(AppTypography.labelLarge)
              .foregroundStyle(colors.primary)
          }
          .buttonStyle(.plain)
          .padding(.vertical, 4)

          Link(destination: URL(string: "https://ai.google.dev/gemma")!) {
            Text("Read more")
              .font(AppTypography.labelLarge)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(colors.primary)
              .foregroundStyle(colors.onPrimary)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          .padding(.leading, 8)
        }
        .padding(.top, 4)
      }
      .padding(.horizontal, 16)
      .padding(.top, 16)
      .padding(.bottom, 8)
      .frame(maxWidth: .infinity)
      .background(
        LinearGradient(
          colors: customColors.promoBannerBgColors.isEmpty
            ? [colors.primaryContainer]
            : customColors.promoBannerBgColors,
          startPoint: .leading,
          endPoint: .trailing
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
      )

      // Decorative star icon (right edge, same height as banner)
      // NOTE: gemini_star is a vector drawable; map to asset catalog image.
      Image("gemini_star")
        .resizable()
        .scaledToFit()
        .frame(width: 80, height: 80)
        .allowsHitTesting(false)
        .opacity(0.6)
        .overlay(
          LinearGradient(
            colors: customColors.promoBannerIconBgColors.isEmpty
              ? [colors.primary]
              : customColors.promoBannerIconBgColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          .blendMode(.sourceAtop)
        )
    }
  }
}
