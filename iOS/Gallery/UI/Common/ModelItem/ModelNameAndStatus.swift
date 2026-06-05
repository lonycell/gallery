/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/modelitem/ModelNameAndStatus.kt

import SwiftUI

/// Displays the model name, download status, and optional "learn more" link.
/// Mirrors `ModelNameAndStatus` composable.
struct ModelNameAndStatus: View {
  let model: Model
  let task: Task?
  let downloadStatus: ModelDownloadStatus?
  let isExpanded: Bool
  var showModelSizeAndDownloadProgressLabel: Bool = true

  @State private var showUpdateDialog: Bool = false

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      // "Best overall" badge
      if let t = task,
         model.bestForTaskIds.contains(t.id),
         t.models.first?.name == model.name {
        HStack(spacing: 8) {
          Image(systemName: "star.fill")
            .resizable()
            .frame(width: 18, height: 18)
            .foregroundStyle(Color(red: 0.988, green: 0.788, blue: 0.204))
          Text(Str.bestOverall)
            .font(AppTypography.labelMedium)
            .foregroundStyle(colors.onSurfaceVariant.opacity(0.6))
        }
        .padding(.bottom, 2)
      }

      // "Update available" row
      if model.updatable {
        Button {
          if !model.updateInfo.isEmpty { showUpdateDialog = true }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
              .resizable()
              .frame(width: 18, height: 18)
              .foregroundStyle(colors.primary)
            Text(Str.updateAvailable)
              .font(AppTypography.labelMedium)
              .foregroundStyle(colors.onSurfaceVariant)
          }
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
      }

      // Model name
      Text(model.displayName.isEmpty ? model.name : model.displayName)
        .font(AppTypography.titleMedium)
        .foregroundStyle(colors.onSurface)
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.trailing, 64)

      // Status details
      if model.runtimeType != .aicore && showModelSizeAndDownloadProgressLabel {
        ModelStatusDetails(
          model: model,
          task: task,
          downloadStatus: downloadStatus,
          isExpanded: isExpanded
        )
        .padding(.top, 2)
      }

      // Learn more
      if !model.imported && !model.learnMoreUrl.isEmpty {
        if let url = URL(string: model.learnMoreUrl) {
          Link(destination: url) {
            HStack(spacing: 4) {
              Image(systemName: "arrow.up.right.square")
                .resizable()
                .frame(width: 14, height: 14)
                .foregroundStyle(customColors.linkColor)
              Text(Str.learnMore)
                .font(AppTypography.bodySmall)
                .foregroundStyle(customColors.linkColor)
            }
          }
        }
      }
    }
    .alert(Str.aboutThisUpdate, isPresented: $showUpdateDialog) {
      Button(Str.ok) { showUpdateDialog = false }
    } message: {
      Text(model.updateInfo)
    }
  }
}

// MARK: - ModelStatusDetails

/// Shows download status icon + label row. Mirrors `ModelStatusDetails` composable.
struct ModelStatusDetails: View {
  let model: Model
  let task: Task?
  let downloadStatus: ModelDownloadStatus?
  let isExpanded: Bool

  @Environment(\.galleryColors) private var colors

  private var sizeLabel: String {
    var label = model.totalBytes.humanReadableSize()
    if !model.localFileRelativeDirPathOverride.isEmpty {
      label = "{ext_files_dir}/\(model.localFileRelativeDirPathOverride)"
    }
    guard let status = downloadStatus else { return label }
    let inProgress = status.status == .inProgress
    let isPartial = status.status == .partiallyDownloaded
    if inProgress || isPartial {
      var totalBytes = status.totalBytes
      if totalBytes == 0 { totalBytes = model.totalBytes }
      var s = "\(status.receivedBytes.humanReadableSize(extraDecimalForGbAndAbove: true)) of \(totalBytes.humanReadableSize())"
      if status.bytesPerSecond > 0 {
        s += " · \(status.bytesPerSecond.humanReadableSize()) / s"
      }
      if isPartial { s += " (resuming...)" }
      return s
    }
    if status.status == .unzipping { return "Unzipping..." }
    return label
  }

  var body: some View {
    HStack(spacing: 4) {
      StatusIcon(task: task, model: model, downloadStatus: downloadStatus)

      if let status = downloadStatus, status.status == .failed {
        Text(status.errorMessage)
          .font(AppTypography.labelSmall)
          .foregroundStyle(colors.error)
          .lineLimit(1)
      } else {
        let lines = sizeLabel.split(separator: "\n").map(String.init)
        VStack(alignment: isExpanded ? .center : .leading, spacing: 0) {
          ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            Text(line)
              .font(AppTypography.bodyMedium)
              .foregroundStyle(colors.onSurfaceVariant)
              .lineLimit(1)
              .monospacedDigit()
          }
        }
      }
    }
  }
}
