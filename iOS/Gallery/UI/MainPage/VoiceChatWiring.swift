// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Port of ui/mainpage/VoiceChatWiring.kt
//
// Shared, headless wiring for the Voice Chat experience.
// Both MainPage and VoiceChatSettingsScreen embed this to keep the shared
// VoiceAssistantViewModel working regardless of which screen is visible.
// All ViewModel calls here are idempotent, safe to call from both screens.

import SwiftUI

/// Attaches the tool/skill/MCP surface, keeps model + tool/skill counts in sync,
/// and feeds the download/preparation status of the optional neural STT/TTS models.
///
/// Renders no UI — download controls live in `VoiceChatSettingsScreen`.
struct VoiceChatPlumbing: View {
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    @ObservedObject var viewModel: VoiceAssistantViewModel

    // NOTE: SkillManagerViewModel and McpManagerViewModel are not yet ported to iOS.
    // When the AgentChat module is available, add them as @ObservedObject parameters
    // and wire `viewModel.setSkillCount` / `viewModel.setMcpToolCount` here.

    var body: some View {
        let mmState = modelManagerViewModel.uiState
        let model = mmState.selectedModel

        // Keep ViewModel pointed at the active model.
        Color.clear
            .onChange(of: model.name) { name in
                viewModel.setActiveModel(model)
            }
            .onAppear {
                viewModel.setActiveModel(model)
            }
            // Feed neural TTS download/preparation status.
            .onChange(of: mmState.modelDownloadStatus[KOREAN_TTS_MODEL_NAME]?.status) { _ in
                let ttsModel = modelManagerViewModel.getModelByName(KOREAN_TTS_MODEL_NAME)
                viewModel.onKoreanTtsStatus(
                    model: ttsModel,
                    downloadStatus: ttsModel.flatMap { mmState.modelDownloadStatus[$0.name] }
                )
            }
            .onChange(of: mmState.modelDownloadStatus[MELO_TTS_MODEL_NAME]?.status) { _ in
                let meloModel = modelManagerViewModel.getModelByName(MELO_TTS_MODEL_NAME)
                viewModel.onMeloTtsStatus(
                    model: meloModel,
                    downloadStatus: meloModel.flatMap { mmState.modelDownloadStatus[$0.name] }
                )
            }
            .onChange(of: mmState.modelDownloadStatus[NEURAL_STT_MODEL_NAME]?.status) { _ in
                let sttModel = modelManagerViewModel.getModelByName(NEURAL_STT_MODEL_NAME)
                viewModel.onNeuralSttStatus(
                    model: sttModel,
                    downloadStatus: sttModel.flatMap { mmState.modelDownloadStatus[$0.name] }
                )
            }
            .onChange(of: mmState.modelDownloadStatus[WHISPER_KO_STT_MODEL_NAME]?.status) { _ in
                let whisperModel = modelManagerViewModel.getModelByName(WHISPER_KO_STT_MODEL_NAME)
                viewModel.onWhisperSttStatus(
                    model: whisperModel,
                    downloadStatus: whisperModel.flatMap { mmState.modelDownloadStatus[$0.name] }
                )
            }
            .task {
                // Initial status feed on first appear.
                let ttsModel = modelManagerViewModel.getModelByName(KOREAN_TTS_MODEL_NAME)
                viewModel.onKoreanTtsStatus(
                    model: ttsModel,
                    downloadStatus: ttsModel.flatMap { mmState.modelDownloadStatus[$0.name] }
                )
                let meloModel = modelManagerViewModel.getModelByName(MELO_TTS_MODEL_NAME)
                viewModel.onMeloTtsStatus(
                    model: meloModel,
                    downloadStatus: meloModel.flatMap { mmState.modelDownloadStatus[$0.name] }
                )
                let sttModel = modelManagerViewModel.getModelByName(NEURAL_STT_MODEL_NAME)
                viewModel.onNeuralSttStatus(
                    model: sttModel,
                    downloadStatus: sttModel.flatMap { mmState.modelDownloadStatus[$0.name] }
                )
                let whisperModel = modelManagerViewModel.getModelByName(WHISPER_KO_STT_MODEL_NAME)
                viewModel.onWhisperSttStatus(
                    model: whisperModel,
                    downloadStatus: whisperModel.flatMap { mmState.modelDownloadStatus[$0.name] }
                )
            }
    }
}
