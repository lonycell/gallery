/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/textandvoiceinput/VoiceRecognizerOverlay.kt

import SwiftUI

/// Full-screen overlay shown while the user is holding the "Hold to Dictate" button.
/// Mirrors `VoiceRecognizerOverlay` composable.
struct VoiceRecognizerOverlay: View {
  let task: Task
  let viewModel: HoldToDictateViewModel
  let bottomPadding: CGFloat
  let curAmplitude: Int

  @Environment(\.customColors) private var customColors

  private var bgColor: Color {
    getTaskBgGradientColors(task: task, customColors: customColors)[1]
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      // Audio waveform background
      AudioAnimation(bgColor: Color.black.opacity(0.8), amplitude: curAmplitude)

      // Recognised text in the centre
      Text(viewModel.uiState.recognizedText.isEmpty
           ? Str.listening
           : viewModel.uiState.recognizedText)
        .font(AppTypography.bodyLarge)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.bottom, (48 + bottomPadding) / 2)
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)

      // Bottom bar: instructions + listening pill
      VStack(spacing: 8) {
        HStack {
          Text(Str.releaseToSend)
            .font(AppTypography.labelMedium)
            .foregroundStyle(.black)
          Spacer()
          Text(Str.slideUpToCancel)
            .font(AppTypography.labelMedium)
            .foregroundStyle(.black)
        }

        // Covering pill that absorbs touch input (prevents accidental interaction)
        ZStack {
          Capsule().fill(bgColor)
          Text(Str.listening)
            .font(AppTypography.bodyMedium)
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .allowsHitTesting(true) // absorbs taps
      }
      .padding(.horizontal, 16)
      .padding(.bottom, bottomPadding)
    }
    .ignoresSafeArea()
  }
}
