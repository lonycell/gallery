/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/ColorUtils.kt

import SwiftUI

/// Returns the background colour for the given task index slot. Mirrors `getTaskBgColor()`.
func getTaskBgColor(task: Task, customColors: CustomColors) -> Color {
  let idx = max(0, task.index) % customColors.taskBgColors.count
  return customColors.taskBgColors[idx]
}

/// Returns the two-stop gradient colours for the given task. Mirrors `getTaskBgGradientColors()`.
func getTaskBgGradientColors(task: Task, customColors: CustomColors) -> [Color] {
  let idx = max(0, task.index) % customColors.taskBgGradientColors.count
  return customColors.taskBgGradientColors[idx]
}

/// Returns the icon tint colour for a task. Mirrors `getTaskIconColor(task:)`.
func getTaskIconColor(task: Task, customColors: CustomColors) -> Color {
  let idx = max(0, task.index) % customColors.taskIconColors.count
  return customColors.taskIconColors[idx]
}

/// Returns the icon tint colour by index. Mirrors `getTaskIconColor(index:)`.
func getTaskIconColor(index: Int, customColors: CustomColors) -> Color {
  let idx = max(0, index) % customColors.taskIconColors.count
  return customColors.taskIconColors[idx]
}

// MARK: - View helpers that auto-read environment

/// A view-scoped wrapper that reads customColors from environment and exposes the helpers.
/// Use inside a View body for ergonomic access.
struct TaskColorReader: View {
  @Environment(\.customColors) private var customColors
  let task: Task
  let content: ([Color], Color) -> AnyView

  var body: some View {
    let gradients = getTaskBgGradientColors(task: task, customColors: customColors)
    let icon = getTaskIconColor(task: task, customColors: customColors)
    return content(gradients, icon)
  }
}
