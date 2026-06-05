/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/modelitem/StatusIcon.kt

import SwiftUI

/// Displays an icon representing a model's download status.
/// Mirrors `StatusIcon` composable.
struct StatusIcon: View {
  let task: Task?
  let model: Model
  let downloadStatus: ModelDownloadStatus?

  @Environment(\.customColors) private var customColors
  @Environment(\.galleryColors) private var colors

  private var iconColor: Color {
    if let t = task {
      return getTaskBgGradientColors(task: t, customColors: customColors)[1]
    }
    return colors.primary
  }

  var body: some View {
    if !model.localFileRelativeDirPathOverride.isEmpty {
      Image(systemName: "arrow.down.to.line.compact")
        .resizable()
        .scaledToFit()
        .frame(width: 16, height: 16)
        .foregroundStyle(iconColor)
    } else {
      switch downloadStatus?.status {
      case .notDownloaded:
        Image(systemName: "questionmark.circle")
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .foregroundStyle(colors.onSurfaceVariant.opacity(0.6))
      case .succeeded:
        Image(systemName: "arrow.down.to.line.compact")
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .foregroundStyle(iconColor)
      case .failed:
        Image(systemName: "exclamationmark.circle.fill")
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .foregroundStyle(Color(red: 0.667, green: 0, blue: 0))
      case .inProgress:
        Image(systemName: "arrow.down.circle")
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .foregroundStyle(colors.primary)
      default:
        EmptyView()
      }
    }
  }
}
