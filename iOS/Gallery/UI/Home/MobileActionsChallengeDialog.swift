// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/home/MobileActionsChallengeDialog.kt

import SwiftUI

/// Bottom sheet explaining the Mobile Actions Challenge and offering deep-link actions.
/// Mirrors `MobileActionsChallengeDialog`.
struct MobileActionsChallengeDialog: View {
  let onDismiss: () -> Void
  let onLoadModel: () -> Void
  let onSendEmail: () -> Void

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  private let guideUrl = "https://ai.google.dev/gemma/docs/mobile-actions"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Trophy and title
      Text("🏆")
        .font(.system(size: 32))
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)

      Text(Str.mobileActionsChallengeTitle)
        .font(AppFont.font(size: 16, weight: .bold))
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 4)

      Text(Str.mobileActionsChallengeSubtitle)
        .font(AppTypography.bodyMedium)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 4)

      Spacer().frame(height: 16)

      Text(Str.mobileActionsChallengeDescription)
        .font(AppTypography.bodyMedium)
        .foregroundStyle(colors.onSurface)

      Spacer().frame(height: 24)

      Text(Str.mobileActionsChallengeInstructionsTitle)
        .font(AppFont.font(size: 14, weight: .bold))

      // Instructions with inline link
      Group {
        HStack(alignment: .top, spacing: 0) {
          Text("1. ")
          Text("On your computer")
            .bold()
          Text(", open ")
          ClickableLink(url: guideUrl, linkText: "this guide")
        }
        Text("2. Follow the instructions to fine tune the model and convert it to .litertlm format.")
        Text("3. Transfer the file to this phone.")
        HStack(alignment: .top, spacing: 0) {
          Text("4. Tap ")
          Text("Load Model").bold()
          Text(" below to unlock the demo.")
        }
      }
      .font(AppTypography.bodyMedium)
      .foregroundStyle(colors.onSurface)

      Spacer().frame(height: 16)

      HStack {
        Button(action: onSendEmail) {
          Text(Str.mobileActionsChallengeEmailColab)
            .font(AppTypography.labelLarge)
        }
        .buttonStyle(.plain)
        .foregroundStyle(colors.primary)

        Spacer()

        Button(action: onLoadModel) {
          Text(Str.mobileActionsChallengeLoadModel)
            .font(AppTypography.labelLarge)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(colors.primary)
            .foregroundStyle(colors.onPrimary)
            .clipShape(Capsule())
        }
      }
    }
    .padding(16)
    .padding(.bottom, 16)
  }
}
