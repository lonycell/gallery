/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/ModelDownloadStatusInfoPanel.kt

import SwiftUI

struct ModelDownloadStatusInfoPanel: View {
  let model: Model
  let task: Task
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel

  @Environment(\.galleryColors) private var colors

  private var downloadStatus: ModelDownloadStatus? {
    modelManagerViewModel.uiState.modelDownloadStatus[model.name]
  }

  private var isDownloading: Bool {
    let s = downloadStatus?.status
    return s == .inProgress || s == .partiallyDownloaded || s == .unzipping
  }

  var body: some View {
    VStack(spacing: 0) {
      // Animation region (upper)
      Spacer()
      if isDownloading {
        ModelDownloadingAnimation(
          model: model,
          task: task,
          modelManagerViewModel: modelManagerViewModel
        )
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
      }
      Spacer()

      // Download button / progress
      // NOTE: Mirrors DownloadAndTryButton. The integrator (UI/Common/ModelPage) provides
      // the full button; here we offer a simple download trigger.
      VStack(spacing: 8) {
        if let s = downloadStatus {
          switch s.status {
          case .inProgress, .partiallyDownloaded, .unzipping:
            ProgressView(value: s.totalBytes > 0 ? Double(s.receivedBytes) / Double(s.totalBytes) : nil)
              .progressViewStyle(.linear)
              .padding(.horizontal, 32)
          case .failed:
            Text(s.errorMessage)
              .font(.caption)
              .foregroundColor(colors.error)
              .multilineTextAlignment(.center)
              .padding(.horizontal, 32)
            Button("재시도") {
              modelManagerViewModel.downloadModel(task: task, model: model)
            }
            .buttonStyle(.borderedProminent)
          default:
            Button("다운로드 및 체험하기") {
              modelManagerViewModel.downloadModel(task: task, model: model)
            }
            .buttonStyle(.borderedProminent)
          }
        } else {
          Button("다운로드 및 체험하기") {
            _Concurrency.Task { await modelManagerViewModel.downloadModel(task: task, model: model) }
          }
          .buttonStyle(.borderedProminent)
        }
      }
      .padding(.horizontal, 32)
      .padding(.top, 4)
      .padding(.bottom, 16)

      // Info text when downloading
      Spacer()
      if isDownloading {
        Text("다른 앱으로 전환하거나 화면을 잠가도 됩니다.\n다운로드는 백그라운드에서 계속됩니다.\n완료되면 알림을 보내드립니다.")
          .font(.body)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)
          .transition(.opacity.combined(with: .scale(scale: 0.9)))
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.easeInOut, value: isDownloading)
  }
}
