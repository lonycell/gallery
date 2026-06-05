/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/RotationalLoader.kt
//
// NOTE: Android drew vector drawables (four_circle, circle, double_circle, pantegon)
// tinted via a gradient BlendMode. iOS uses SF Symbol approximations; replace with
// matching asset-catalog images if available.

import SwiftUI

/// A 2×2 grid of small shapes that rotate and pulse. Mirrors `RotationalLoader` composable.
struct RotationalLoader: View {
  let size: CGFloat

  @State private var rotationProgress: Double = 0
  @State private var scaleProgress: Double = 1

  @Environment(\.customColors) private var customColors

  private let symbols = ["4.circle.fill", "circle.fill", "circle.circle.fill", "pentagon.fill"]

  // Color-index mapping mirrors the Android implementation.
  private let colorIndices = [2, 1, 0, 3]

  // Alignment mapping mirrors the Android implementation.
  private let alignments: [Alignment] = [.bottomTrailing, .bottomLeading, .topTrailing, .topLeading]

  private var gridSpacing: CGFloat { size * 0.1 }
  private var cellSize: CGFloat { (size - gridSpacing) / 2 }
  private var iconSize: CGFloat { size * 0.3 }

  var body: some View {
    let rotationZ = 45.0 + rotationProgress * 360.0

    LazyVGrid(
      columns: [GridItem(.fixed(cellSize), spacing: gridSpacing),
                GridItem(.fixed(cellSize), spacing: gridSpacing)],
      spacing: gridSpacing
    ) {
      ForEach(0..<4) { index in
        let colorIdx = colorIndices[index] % max(1, customColors.taskBgGradientColors.count)
        let gradient = customColors.taskBgGradientColors[colorIdx]

        ZStack(alignment: alignments[index]) {
          Color.clear.frame(width: cellSize, height: cellSize)
          Image(systemName: symbols[index])
            .resizable()
            .frame(width: iconSize, height: iconSize)
            .foregroundStyle(
              LinearGradient(
                colors: gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .scaleEffect(scaleProgress)
            .rotationEffect(.degrees(-rotationZ))
        }
      }
    }
    .frame(width: size, height: size)
    .rotationEffect(.degrees(rotationZ))
    .accessibilityHidden(true)
    .onAppear {
      startAnimations()
    }
  }

  private func startAnimations() {
    // Outer rotation: cubic bezier approximated with easeInOut repeated.
    withAnimation(
      .timingCurve(0.5, 0.16, 0, 0.71, duration: 2.0).repeatForever(autoreverses: false)
    ) {
      rotationProgress = 1
    }
    // Inner scale: easeInOut reversing.
    withAnimation(
      .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
    ) {
      scaleProgress = 0.4
    }
  }
}
