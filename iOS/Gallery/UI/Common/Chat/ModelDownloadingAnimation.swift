/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/ModelDownloadingAnimation.kt

import SwiftUI

struct ModelDownloadingAnimation: View {
  let model: Model
  let task: Task
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel

  @Environment(\.galleryColors) private var colors

  private var downloadStatus: ModelDownloadStatus? {
    modelManagerViewModel.uiState.modelDownloadStatus[model.name]
  }

  var body: some View {
    let status = downloadStatus

    if let s = status, s.status == .failed {
      // Error message
      HStack {
        Text(s.errorMessage)
          .font(.caption)
          .foregroundColor(colors.error)
          .lineLimit(nil)
          .fixedSize(horizontal: false, vertical: true)
      }
    } else {
      VStack(alignment: .center, spacing: 32) {
        // Rotational loader (large)
        ProgressView()
          .progressViewStyle(.circular)
          .scaleEffect(4)
          .frame(width: 160, height: 160)

        // Download stats label
        if let s = status {
          let label = downloadStatsLabel(status: s)
          if !label.isEmpty {
            Text(label)
              .font(.caption)
              .foregroundColor(colors.onSurfaceVariant)
              .multilineTextAlignment(.center)
              .padding(.bottom, 4)
          }
        }
      }
      .padding(.top, 32)
    }
  }

  private func downloadStatsLabel(status: ModelDownloadStatus) -> String {
    let inProgress = status.status == .inProgress
    let isPartial = status.status == .partiallyDownloaded
    if inProgress || isPartial {
      var totalBytes = status.totalBytes
      if totalBytes == 0 { totalBytes = model.totalBytes }
      var label = "\(readableFileSize(status.receivedBytes)) / \(readableFileSize(totalBytes))"
      if status.bytesPerSecond > 0 {
        label += " · \(readableFileSize(status.bytesPerSecond))/s"
        if status.remainingMs >= 0 {
          label += " · \(formatToHourMinSecond(status.remainingMs))남음"
        }
      }
      if isPartial { label += " (재개 중...)" }
      return label
    } else if status.status == .unzipping {
      return "압축 해제 중..."
    }
    return ""
  }
}

private func formatToHourMinSecond(_ ms: Int64) -> String {
  let totalSec = Int(ms / 1000)
  let h = totalSec / 3600
  let m = (totalSec % 3600) / 60
  let s = totalSec % 60
  if h > 0 { return "\(h)시간 \(m)분 \(s)초" }
  if m > 0 { return "\(m)분 \(s)초" }
  return "\(s)초"
}
