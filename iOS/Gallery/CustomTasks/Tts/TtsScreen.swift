// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/tts/TtsScreen.kt

import SwiftUI

/// The main screen for the Text to Speech custom task.
struct TtsScreen: View {
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  @StateObject private var viewModel = TtsViewModel()

  @State private var text: String = "Hello! This is on-device text to speech."
  @State private var sid: Int = 0

  @ViewBuilder
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
    } else if let instance = model.instance as? TtsModelInstance {
      let numSpeakers = instance.numSpeakers
      // Clamp sid when switching models.
      let clampedSid = min(sid, max(0, numSpeakers - 1))
      let speed = model.getFloatConfigValue(TTS_CONFIG_KEY_SPEED, default: 1.0)

      VStack(alignment: .leading, spacing: 12) {
      // Text input
      TextEditor(text: $text)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 120)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .font(AppTypography.bodyLarge)

      // Speaker picker (multi-speaker models only)
      if numSpeakers > 1 {
        let speakerLabel: (Int) -> String = { i in
          instance.speakerNames.indices.contains(i)
            ? instance.speakerNames[i]
            : "음성 \(i + 1)"
        }
        Picker("음성 (\(numSpeakers)개 중 선택)", selection: $sid) {
          ForEach(0..<numSpeakers, id: \.self) { i in
            Text(speakerLabel(i)).tag(i)
          }
        }
        .pickerStyle(.menu)
      }

      // Speed hint
      Text("속도: \(String(format: "%.1f", speed))x (상단 설정 메뉴에서 변경)")
        .font(AppTypography.bodySmall)
        .foregroundStyle(.secondary)

      // Error
      if !viewModel.uiState.error.isEmpty {
        Text(viewModel.uiState.error)
          .foregroundStyle(.red)
          .font(AppTypography.bodySmall)
      }

      // Action buttons
      HStack(spacing: 12) {
        Button {
          viewModel.speak(
            instance: instance,
            text: text,
            speed: speed,
            sid: clampedSid
          )
        } label: {
          if viewModel.uiState.isSynthesizing {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(.white)
          } else {
            Label("말하기", systemImage: "speaker.wave.2")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.uiState.isSynthesizing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .frame(maxWidth: .infinity)

        Button {
          viewModel.stop()
        } label: {
          Label("정지", systemImage: "stop.fill")
        }
        .buttonStyle(.bordered)
      }
    }
      .padding(16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .onChange(of: model.name) { _ in sid = 0 }
    } else {
      Text("모델 초기화 중 오류가 발생했습니다.")
        .foregroundStyle(.red)
        .padding()
    }
  }
}
