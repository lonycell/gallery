// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Port of ui/mainpage/VoiceChatSettingsScreen.kt
//
// The unified settings screen for the Voice Chat experience.
// Reached from the gear icon on MainPage. Accepts navigateUp + onOpenSubscription.

import SwiftUI

/// Settings screen for the voice-chat experience.
///
/// Everything that would otherwise clutter the chat lives here: LLM selection/download,
/// STT engine and TTS voice choices, tool/skill/MCP management, and the Pro subscription
/// entry. Shares the same `VoiceAssistantViewModel` as the chat (scoped to the parent
/// nav graph), so selections take effect immediately.
///
/// - Parameters:
///   - modelManagerViewModel: Central model state.
///   - viewModel:             Shared voice-assistant view model.
///   - characterViewModel:    Character state (for default voice assignment).
///   - onOpenSubscription:    Navigate to the subscription/paywall screen.
///   - navigateUp:            Pop back to `MainPage`.
struct VoiceChatSettingsScreen: View {
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    @ObservedObject var viewModel: VoiceAssistantViewModel
    @ObservedObject var characterViewModel: CharacterViewModel
    let onOpenSubscription: () -> Void
    let navigateUp: () -> Void

    @State private var showSkillSheet = false
    @State private var showMcpSheet   = false

    var body: some View {
        let mmState = modelManagerViewModel.uiState
        let uiState = viewModel.uiState
        let charState = characterViewModel.state

        let voiceTask = modelManagerViewModel.getTaskById(VOICE_ASSISTANT_TASK_ID)

        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16, pinnedViews: []) {

                    // --- LLM ---
                    SettingsSection(title: "AI 모델 (LLM)", subtitle: "대화에 사용할 온디바이스 모델") {
                        let llmModels = voiceTask?.models ?? []
                        if llmModels.isEmpty {
                            Text("사용 가능한 모델이 없습니다.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(llmModels, id: \.name) { model in
                                LlmModelRow(
                                    model: model,
                                    selected: mmState.selectedModel.name == model.name,
                                    downloadStatus: mmState.modelDownloadStatus[model.name],
                                    onSelect: { modelManagerViewModel.selectModel(model) },
                                    onDownload: {
                                        if let task = voiceTask {
                                            modelManagerViewModel.downloadModel(task: task, model: model)
                                        }
                                    }
                                )
                            }
                        }
                    }

                    // --- STT ---
                    SettingsSection(title: "음성 인식 (STT)", subtitle: "내 말을 텍스트로 바꾸는 엔진") {
                        let senseReady = uiState.neuralStt.stage == .ready
                        let whisperReady = uiState.whisperStt.stage == .ready
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ChoiceChip("시스템", selected: uiState.sttEngine == .system) {
                                    viewModel.selectSttEngine(.system)
                                }
                                if senseReady {
                                    ChoiceChip("SenseVoice", selected: uiState.sttEngine == .neural) {
                                        viewModel.selectSttEngine(.neural)
                                    }
                                }
                                if whisperReady {
                                    ChoiceChip("Whisper", selected: uiState.sttEngine == .whisper) {
                                        viewModel.selectSttEngine(.whisper)
                                    }
                                }
                            }
                        }
                        let neuralSttModel = modelManagerViewModel.getModelByName(NEURAL_STT_MODEL_NAME)
                        let whisperSttModel = modelManagerViewModel.getModelByName(WHISPER_KO_STT_MODEL_NAME)
                        if let m = neuralSttModel, !senseReady {
                            Spacer().frame(height: 10)
                            NeuralSttDownloadRow(
                                title: "SenseVoice (오프라인 인식)",
                                descNotInstalled: "인터넷 없이 기기에서 음성 인식 (약 239MB)",
                                state: uiState.neuralStt,
                                onDownload: { modelManagerViewModel.downloadModel(task: nil, model: m) },
                                onRetry: { viewModel.retryNeuralSttPreparation() }
                            )
                        }
                        if let m = whisperSttModel, !whisperReady {
                            Spacer().frame(height: 10)
                            NeuralSttDownloadRow(
                                title: "Whisper 한국어 인식",
                                descNotInstalled: "더 정확한 한국어 인식 (약 374MB)",
                                state: uiState.whisperStt,
                                onDownload: { modelManagerViewModel.downloadModel(task: nil, model: m) },
                                onRetry: { viewModel.retryWhisperSttPreparation() }
                            )
                        }
                    }

                    // --- TTS ---
                    SettingsSection(title: "음성 합성 (TTS)", subtitle: "AI의 답변을 읽어주는 목소리") {
                        Text("기본 목소리예요. 캐릭터 상세에서 따로 지정하지 않은 캐릭터는 이 목소리로 말해요.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if !uiState.voices.isEmpty {
                            Spacer().frame(height: 8)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(uiState.voices) { voice in
                                        ChoiceChip(
                                            voice.label,
                                            selected: voice.id == charState.defaultVoiceId,
                                            neural: voice.isNeural || voice.isCloud
                                        ) {
                                            characterViewModel.setDefaultVoice(voice.id)
                                        }
                                    }
                                }
                            }
                        }
                        if uiState.ttsReady {
                            Spacer().frame(height: 10)
                            Text("발화 방식")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            Spacer().frame(height: 6)
                            HStack(spacing: 8) {
                                ChoiceChip("전체 발화", selected: uiState.speakMode == .afterComplete) {
                                    viewModel.setSpeakMode(.afterComplete)
                                }
                                ChoiceChip("실시간 발화", selected: uiState.speakMode == .streaming) {
                                    viewModel.setSpeakMode(.streaming)
                                }
                            }
                        }
                        let koreanTtsModel = modelManagerViewModel.getModelByName(KOREAN_TTS_MODEL_NAME)
                        let meloTtsModel   = modelManagerViewModel.getModelByName(MELO_TTS_MODEL_NAME)
                        if let m = koreanTtsModel, uiState.neuralVoice.stage != .ready {
                            Spacer().frame(height: 10)
                            NeuralVoiceDownloadRow(
                                title: "고품질 한국어 음성 (KSS)",
                                descNotInstalled: "더 자연스러운 음성 (약 64MB)",
                                state: uiState.neuralVoice,
                                onDownload: { modelManagerViewModel.downloadModel(task: nil, model: m) },
                                onRetry: { viewModel.retryNeuralPreparation() }
                            )
                        }
                        if let m = meloTtsModel, !m.url.isEmpty, uiState.meloVoice.stage != .ready {
                            Spacer().frame(height: 10)
                            NeuralVoiceDownloadRow(
                                title: "MeloTTS 한국어 음성",
                                descNotInstalled: "MeloTTS의 자연스러운 한국어 음성",
                                state: uiState.meloVoice,
                                onDownload: { modelManagerViewModel.downloadModel(task: nil, model: m) },
                                onRetry: { viewModel.retryMeloPreparation() }
                            )
                        }
                    }

                    // --- Tools / Skills / Agents ---
                    SettingsSection(title: "도구 · 스킬 · 에이전트", subtitle: "AI가 할 수 있는 일을 확장하세요") {
                        Text("스킬 \(uiState.skillCount)개 · 도구 \(uiState.mcpToolCount)개 사용 가능")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer().frame(height: 8)
                        HStack(spacing: 8) {
                            Button("스킬 관리") { showSkillSheet = true }
                                .buttonStyle(.bordered)
                            Button("MCP 도구") { showMcpSheet = true }
                                .buttonStyle(.bordered)
                        }
                    }

                    // --- Subscription ---
                    SettingsSection(title: "구독", subtitle: "더 많은 기능을 잠금 해제") {
                        Button(action: onOpenSubscription) {
                            HStack {
                                Image(systemName: "star.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pro 구독")
                                        .font(.callout).fontWeight(.bold)
                                    Text("모든 기능과 캐릭터를 잠금 해제")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.accentColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .navigationTitle(Str.voiceSettingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: navigateUp) {
                        Image(systemName: "chevron.left")
                    }
                }
            }
        }
        // Headless wiring (idempotent, keeps engines in sync while on this screen).
        .background(
            VoiceChatPlumbing(
                modelManagerViewModel: modelManagerViewModel,
                viewModel: viewModel
            )
        )
        // NOTE: Skill + MCP bottom sheets require AgentChat module (not yet ported).
        // Replace with real SkillManagerBottomSheet / McpManagerBottomSheet when available.
        .sheet(isPresented: $showSkillSheet) {
            SkillPlaceholderSheet(isPresented: $showSkillSheet)
        }
        .sheet(isPresented: $showMcpSheet) {
            McpPlaceholderSheet(isPresented: $showMcpSheet)
        }
    }
}

// MARK: - SettingsSection

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline).fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - ChoiceChip

private struct ChoiceChip: View {
    let label: String
    let selected: Bool
    var neural: Bool = false
    let action: () -> Void

    init(_ label: String, selected: Bool, neural: Bool = false, action: @escaping () -> Void) {
        self.label = label; self.selected = selected
        self.neural = neural; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if neural {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                }
                Text(label)
                    .font(.callout)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? Color.accentColor : Color(.secondarySystemBackground))
            .foregroundColor(selected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - LlmModelRow

private struct LlmModelRow: View {
    let model: Model
    let selected: Bool
    let downloadStatus: ModelDownloadStatus?
    let onSelect: () -> Void
    let onDownload: () -> Void

    var body: some View {
        let st = downloadStatus?.status
        let downloaded  = st == .succeeded
        let unzipping   = st == .unzipping
        let downloading = st == .inProgress || st == .partiallyDownloaded || unzipping
        let total   = downloadStatus?.totalBytes ?? 0
        let recv    = downloadStatus?.receivedBytes ?? 0
        let percent = total > 0 ? Int(recv * 100 / total) : -1

        let sizeBytes: Int64 = model.totalBytes > 0 ? model.totalBytes :
                               model.sizeInBytes > 0 ? model.sizeInBytes : total
        let sizeLabel = sizeBytes > 0 ? humanReadableSize(sizeBytes) : ""

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName.isEmpty ? model.name : model.displayName)
                        .font(.subheadline)
                        .fontWeight(selected ? .bold : .regular)
                    Text({
                        if selected { return sizeLabel.isEmpty ? "사용 중" : "사용 중 · \(sizeLabel)" }
                        if downloaded { return sizeLabel.isEmpty ? "탭하여 선택" : "탭하여 선택 · \(sizeLabel)" }
                        if unzipping { return "압축 해제 중…" }
                        if downloading {
                            return percent >= 0 && percent <= 100
                            ? "다운로드 중 \(percent)% · \(humanReadableSize(recv)) / \(humanReadableSize(total))"
                            : "다운로드 중…"
                        }
                        return sizeLabel.isEmpty ? "다운로드 필요" : "다운로드 필요 · \(sizeLabel)"
                    }())
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                } else if !downloading, !downloaded {
                    Button(action: onDownload) {
                        Image(systemName: "arrow.down.circle")
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if downloaded { onSelect() } }

            if downloading {
                if percent >= 0, percent <= 100 {
                    ProgressView(value: Float(percent) / 100)
                } else {
                    ProgressView()
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Neural download rows

private struct NeuralVoiceDownloadRow: View {
    let title: String
    let descNotInstalled: String
    let state: NeuralVoiceState
    let onDownload: () -> Void
    let onRetry: () -> Void

    var body: some View {
        DownloadRowScaffold(
            title: title,
            subtitle: {
                switch state.stage {
                case .notInstalled: return descNotInstalled
                case .downloading:
                    return state.downloadPercent >= 0 ? "다운로드 중 \(state.downloadPercent)%" : "다운로드 중…"
                case .preparing:
                    return state.unpackPercent >= 0 ? "준비 중 \(state.unpackPercent)%" : "준비 중…"
                case .error: return state.error.isEmpty ? "오류가 발생했습니다." : state.error
                case .ready: return "사용 준비 완료"
                }
            }(),
            isError: state.stage == .error,
            showDownload: state.stage == .notInstalled,
            showSpinner: state.stage == .downloading || state.stage == .preparing,
            showRetry: state.stage == .error,
            progressPercent: state.stage == .downloading ? state.downloadPercent :
                             state.stage == .preparing  ? state.unpackPercent : -1,
            showProgressBar: state.stage == .downloading || state.stage == .preparing,
            onDownload: onDownload, onRetry: onRetry
        )
    }
}

private struct NeuralSttDownloadRow: View {
    let title: String
    let descNotInstalled: String
    let state: NeuralSttState
    let onDownload: () -> Void
    let onRetry: () -> Void

    var body: some View {
        DownloadRowScaffold(
            title: title,
            subtitle: {
                switch state.stage {
                case .notInstalled: return descNotInstalled
                case .downloading:
                    return state.downloadPercent >= 0 ? "다운로드 중 \(state.downloadPercent)%" : "다운로드 중…"
                case .preparing: return "준비 중…"
                case .error: return state.error.isEmpty ? "오류가 발생했습니다." : state.error
                case .ready: return "사용 준비 완료"
                }
            }(),
            isError: state.stage == .error,
            showDownload: state.stage == .notInstalled,
            showSpinner: state.stage == .downloading || state.stage == .preparing,
            showRetry: state.stage == .error,
            progressPercent: state.stage == .downloading ? state.downloadPercent : -1,
            showProgressBar: state.stage == .downloading || state.stage == .preparing,
            onDownload: onDownload, onRetry: onRetry
        )
    }
}

private struct DownloadRowScaffold: View {
    let title: String
    let subtitle: String
    let isError: Bool
    let showDownload: Bool
    let showSpinner: Bool
    let showRetry: Bool
    let progressPercent: Int
    let showProgressBar: Bool
    let onDownload: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).fontWeight(.semibold)
                    Text(subtitle).font(.caption)
                        .foregroundColor(isError ? .red : .secondary)
                }
                Spacer()
                if showDownload {
                    Button("받기") { onDownload() }.buttonStyle(.bordered)
                } else if showSpinner {
                    ProgressView().scaleEffect(0.85)
                } else if showRetry {
                    Button("재시도") { onRetry() }.buttonStyle(.bordered)
                }
            }
            if showProgressBar {
                if progressPercent >= 0, progressPercent <= 100 {
                    ProgressView(value: Float(progressPercent) / 100)
                } else {
                    ProgressView()
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - ModelManagerViewModel convenience stubs
// NOTE: Forward to real implementations in ModelManagerViewModel.swift when ported.

private extension ModelManagerViewModel {
    /// Optional-task overload; forwards to the real `downloadModel(task:model:)` when a task exists.
    /// (`selectModel(_:)` and `initializeModel(task:model:force:)` come from the base view model.)
    func downloadModel(task: Task?, model: Model) {
        if let task { downloadModel(task: task, model: model) }
    }

    /// `context:` overload forwarding to the real `initializeModel(task:model:force:)`.
    func initializeModel(context: Any?, task: Task, model: Model, force: Bool) {
        initializeModel(task: task, model: model, force: force)
    }
}

// MARK: - Human readable size helper

private func humanReadableSize(_ bytes: Int64) -> String {
    let mb = Double(bytes) / 1_000_000
    if mb >= 1000 { return String(format: "%.1f GB", mb / 1000) }
    if mb >= 1    { return String(format: "%.0f MB", mb) }
    return String(format: "%.0f KB", Double(bytes) / 1_000)
}

// MARK: - Placeholder bottom sheets (stubs until AgentChat is ported)

private struct SkillPlaceholderSheet: View {
    @Binding var isPresented: Bool
    var body: some View {
        NavigationView {
            VStack { Text("스킬 관리는 AgentChat 모듈이 포팅되면 사용할 수 있습니다.").padding() }
            .navigationTitle("스킬 관리")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("닫기") { isPresented = false } } }
        }
    }
}

private struct McpPlaceholderSheet: View {
    @Binding var isPresented: Bool
    var body: some View {
        NavigationView {
            VStack { Text("MCP 도구 관리는 AgentChat 모듈이 포팅되면 사용할 수 있습니다.").padding() }
            .navigationTitle("MCP 도구")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("닫기") { isPresented = false } } }
        }
    }
}
