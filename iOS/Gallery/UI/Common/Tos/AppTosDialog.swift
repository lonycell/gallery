/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/tos/AppTosDialog.kt

import SwiftUI

/// Terms of Service dialog shown once when the app launches. Mirrors `AppTosDialog` composable.
struct AppTosDialog: View {
  let onTosAccepted: () -> Void
  var viewingMode: Bool = false

  @Environment(\.galleryColors) private var colors

  var body: some View {
    ZStack {
      Color.black.opacity(0.4).ignoresSafeArea()
        // In viewing mode, allow dismiss via background tap.
        .onTapGesture { if viewingMode { onTosAccepted() } }

      RoundedRectangle(cornerRadius: 28)
        .fill(colors.surface)
        .overlay(
          VStack(alignment: .leading, spacing: 0) {
            // Title
            Text(Str.tosDialogTitleApp)
              .font(AppTypography.headlineSmall)
              .fontWeight(.medium)
              .foregroundStyle(colors.onSurface)
              .minimumScaleFactor(0.67)
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.top, 24)

            // Body (scrollable)
            ScrollView {
              MarkdownText(
                text:
                  "By using this app, you agree to the " +
                  "[Google Terms of Service](https://policies.google.com/terms?hl=en-US).\n\n" +
                  "To learn what information we collect and why, how we use it, " +
                  "and how to review and update it, please review the " +
                  "[Google Privacy Policy](https://policies.google.com/privacy?hl=en-US).\n\n" +
                  "Your use of each model is subject to the applicable model license terms.",
                smallFontSize: true,
                textColor: colors.onSurfaceVariant
              )
              .padding(.top, 16)
            }
            .frame(maxHeight: 300)

            // Accept button
            HStack {
              Spacer()
              Button(viewingMode ? Str.close : Str.tosDialogAcceptAndContinueButtonLabel) {
                onTosAccepted()
              }
              .buttonStyle(.borderedProminent)
              .padding(.top, 28)
              .padding(.bottom, 24)
            }
          }
          .padding(.horizontal, 24)
        )
        .padding(.horizontal, 24)
    }
  }
}
