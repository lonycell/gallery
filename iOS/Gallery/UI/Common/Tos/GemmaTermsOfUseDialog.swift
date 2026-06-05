/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/tos/GemmaTermsOfUseDialog.kt

import SwiftUI

/// Gemma Terms of Use dialog shown before downloading a Gemma model.
/// Mirrors `GemmaTermsOfUseDialog` composable.
struct GemmaTermsOfUseDialog: View {
  let onTosAccepted: () -> Void
  var onCancel: () -> Void = {}
  var viewingMode: Bool = false

  @Environment(\.galleryColors) private var colors

  var body: some View {
    ZStack {
      Color.black.opacity(0.4).ignoresSafeArea()
        .onTapGesture { onCancel() }

      RoundedRectangle(cornerRadius: 28)
        .fill(colors.surface)
        .overlay(
          VStack(alignment: .leading, spacing: 0) {
            // Title
            Text(Str.tosDialogTitleGemma)
              .font(AppTypography.headlineSmall)
              .fontWeight(.medium)
              .foregroundStyle(colors.onSurface)
              .minimumScaleFactor(0.67)
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.top, 24)

            // Body
            ScrollView {
              HStack(spacing: 0) {
                Text("Gemma models on the Google AI Edge Gallery app are governed by the ")
                  .font(AppTypography.bodyMedium)
                  .foregroundStyle(colors.onSurfaceVariant)
                + Text("[Gemma Terms of Service](https://ai.google.dev/gemma/terms)")
                  .font(AppTypography.bodyMedium)
                  .foregroundStyle(colors.onSurfaceVariant)
                + Text(". Please review these terms and ensure you agree before continuing.")
                  .font(AppTypography.bodyMedium)
                  .foregroundStyle(colors.onSurfaceVariant)
              }
              .padding(.top, 16)
            }
            .frame(maxHeight: 200)
            .tint(colors.primary)

            // Button row
            HStack {
              Spacer()
              if !viewingMode {
                Button(Str.cancel) { onCancel() }
                  .font(AppTypography.labelLarge)
                  .foregroundStyle(colors.primary)
                  .padding(.trailing, 8)
              }
              Button(viewingMode ? Str.close : Str.tosDialogAgreeAndContinueButtonLabel) {
                onTosAccepted()
              }
              .buttonStyle(.borderedProminent)
            }
            .padding(.top, 24)
            .padding(.bottom, 24)
          }
          .padding(.horizontal, 24)
        )
        .padding(.horizontal, 24)
    }
  }
}
