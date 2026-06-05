/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/TaskIcon.kt

import SwiftUI

/// The four background shape image names (from the asset catalog).
private let TASK_ICON_SHAPES = ["circle_shape", "double_circle_shape", "pantagon_shape", "four_circle_shape"]

/// Composable that displays a gradient-filled background shape with a white foreground icon.
/// Mirrors `TaskIcon`.
struct TaskIcon: View {
  let task: Task
  var width: CGFloat = 56
  var animationProgress: Float = 1

  @Environment(\.customColors) private var customColors

  private var shapeImageName: String {
    TASK_ICON_SHAPES[task.index % TASK_ICON_SHAPES.count]
  }

  private var gradientColors: [Color] {
    getTaskBgGradientColors(task: task, customColors: customColors)
  }

  private var iconAlpha: Double {
    let p = Double(animationProgress)
    return p >= 0.8 ? (p - 0.8) / 0.2 : 0
  }

  var body: some View {
    ZStack {
      // Background shape with gradient
      Image(shapeImageName)
        .resizable()
        .scaledToFit()
        .overlay(
          LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          .blendMode(.sourceAtop)
        )
        .rotationEffect(.degrees(Double(-180 * (1 - animationProgress))))
        .offset(x: CGFloat(80 * (1 - animationProgress)))
        .opacity(Double(animationProgress))

      // Foreground icon
      Image(systemName: task.sfSymbol ?? "sparkles")
        .resizable()
        .scaledToFit()
        .frame(width: width * 0.55, height: width * 0.55)
        .foregroundStyle(.white)
        .opacity(iconAlpha)
        .scaleEffect(CGFloat(iconAlpha))
    }
    .frame(width: width, height: width)
    .accessibilityHidden(true)
  }
}
