/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/modelitem/DownloadModelPanel.kt

import SwiftUI

/// Displays the download/try button (and optional update button) for a model.
/// Mirrors `DownloadModelPanel` composable.
struct DownloadModelPanel: View {
  let model: Model
  let task: Task?
  let modelManagerViewModel: ModelManagerViewModel
  let downloadStatus: ModelDownloadStatusType?
  let downloadProgress: Float
  let isExpanded: Bool
  let onTryItClicked: () -> Void
  var tosViewModel: TosViewModel? = nil
  var downloadButtonBackgroundColor: Color? = nil

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  private func isDownloadButtonEnabled() -> Bool {
    let downloadFailed = downloadStatus == .failed
    let isLitertLm = model.runtimeType == .litertLm
    return !downloadFailed || isLitertLm
  }

  var body: some View {
    HStack(spacing: 8) {
      // Update button
      if model.updatable {
        Button {
          if let latest = model.latestModelFile {
            model.version = latest.commitHash
            model.downloadFileName = latest.fileName
          }
          model.updatable = false
          if let t = task { modelManagerViewModel.downloadModel(task: t, model: model) }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
              .foregroundStyle(colors.onSecondaryContainer)
            if isExpanded {
              Text(Str.update)
                .font(AppTypography.titleMedium)
                .foregroundStyle(colors.onSecondaryContainer)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
          }
          .padding(.horizontal, 12)
          .frame(height: 42)
        }
        .frame(maxWidth: isExpanded ? .infinity : nil)
        .background(colors.secondaryContainer, in: Capsule())
      }

      // Download / Try it button
      DownloadAndTryButton(
        task: task,
        model: model,
        enabled: isDownloadButtonEnabled(),
        downloadStatus: downloadStatus,
        downloadProgress: downloadProgress,
        modelManagerViewModel: modelManagerViewModel,
        onClicked: onTryItClicked,
        compact: !isExpanded,
        downloadButtonBackgroundColor: downloadButtonBackgroundColor ?? colors.surfaceContainer
      )
      .frame(maxWidth: isExpanded ? .infinity : nil)
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
  }
}

// MARK: - Helper

func calculateDownloadProgress(downloadStatus: ModelDownloadStatus?) -> Float {
  guard let ds = downloadStatus, ds.totalBytes > 0 else { return 0 }
  let progress = Float(ds.receivedBytes) / Float(ds.totalBytes)
  return progress.isNaN ? 0 : progress
}
