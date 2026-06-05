// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/stt/SttScreen.kt

import SwiftUI

/// The main screen for the Speech to Text custom task.
struct SttScreen: View {
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  @StateObject private var viewModel = SttViewModel()

  var body: some View {
    let mmState = modelManagerViewModel.uiState
    let model = mmState.selectedModel

    if !mmState.isModelInitialized(model) {
      HStack {
        Spacer()
        ProgressView()
          .progressViewStyle(.circular)
        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      return
    }

    guard let instance = model.instance as? SttModelInstance else {
      Text("모델 초기화 중 오류가 발생했습니다.")
        .foregroundStyle(.red)
        .padding()
      return
    }

    VStack(alignment: .center, spacing: 16) {
      // Transcript display
      ScrollView {
        if viewModel.uiState.transcript.isEmpty {
          Text("여기에 변환된 텍스트가 표시됩니다.")
            .font(AppTypography.bodyMedium)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
          Text(viewModel.uiState.transcript)
            .font(AppTypography.bodyLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      // Error label
      if !viewModel.uiState.error.isEmpty {
        Text(viewModel.uiState.error)
          .font(AppTypography.bodySmall)
          .foregroundStyle(.red)
      }

      // Status hint
      let statusText: String = {
        if viewModel.uiState.isRecording { return "녹음 중… 정지를 탭해 변환하세요" }
        if viewModel.uiState.isTranscribing { return "변환 중…" }
        return "녹음을 탭하고 말을 시작하세요"
      }()
      Text(statusText)
        .font(AppTypography.bodySmall)
        .foregroundStyle(.secondary)

      // Record / Stop button
      if viewModel.uiState.isRecording {
        Button {
          viewModel.stopAndTranscribe(instance: instance)
        } label: {
          Label("정지 및 변환", systemImage: "stop.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
      } else {
        Button {
          viewModel.requestMicrophonePermission {
            viewModel.startRecording()
          } onDenied: {
            viewModel.uiState.error = "마이크 권한이 필요합니다."
          }
        } label: {
          Group {
            if viewModel.uiState.isTranscribing {
              ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
            } else {
              Label("녹음", systemImage: "mic")
            }
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.uiState.isTranscribing)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
