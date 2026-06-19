// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/home/PromoScreenGm4.kt

import SwiftUI

private let DISMISS_DELAY_SECONDS: Double = 5

/// Full-screen Gemma 4 launch promo that auto-dismisses after 5 seconds.
/// Mirrors `PromoScreenGm4`.
struct PromoScreenGm4: View {
  let onDismiss: () -> Void

  var body: some View {
    ZStack {
      // Background gradient
      LinearGradient(
        colors: [Color(hex: 0x183570), Color(hex: 0x0A122D)],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      // Background star decoration
      // NOTE: gemma_promo_bg and gemini_star are vector drawables; use asset images here.
      Image("gemma_promo_bg")
        .resizable()
        .scaledToFit()
        .frame(maxWidth: .infinity)
        .opacity(0.46)
        .rotationEffect(.degrees(-15.7))
        .scaleEffect(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .blendMode(.multiply)

      // Center content
      VStack(spacing: 12) {
        Image("gemini_star")
          .resizable()
          .scaledToFit()
          .frame(width: 40, height: 40)

        Text("Introducing")
          .font(AppFont.font(size: 20))
          .foregroundStyle(.white)

        Text("Gemma 4")
          .font(AppFont.font(size: 38))
          .foregroundStyle(.white)

        Text("Experience the world's most capable open models, designed to run frontier-level intelligence directly on your hardware.")
          .font(AppFont.font(size: 16))
          .lineSpacing(5)
          .multilineTextAlignment(.center)
          .foregroundStyle(Color(hex: 0xF2F2F2))

        Button(action: onDismiss) {
          Text("Dismiss")
            .foregroundStyle(Color(hex: 0xA8C7FA))
        }
        .padding(.top, 24)
      }
      .frame(maxWidth: UIScreen.main.bounds.width * 0.6)
    }
    .task {
      try? await _Concurrency.Task.sleep(nanoseconds: UInt64(DISMISS_DELAY_SECONDS * 1_000_000_000))
      onDismiss()
    }
  }
}
