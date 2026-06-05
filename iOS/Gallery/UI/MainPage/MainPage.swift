// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Port of ui/mainpage/MainPage.kt
//
// The app's main screen: a futuristic voice-call style companion chat.
// This is the NavHost start destination (.mainPage route).

import SwiftUI
import Combine

// MARK: - Shared palette (matches subscription paywall)

private let ScrimBase    = Color(hex: 0x140A2B)
private let AccentPurple = Color(hex: 0x7C4DFF)
private let AccentPink   = Color(hex: 0xE15BD0)
private let ListeningColor = Color(hex: 0x34E1C4)
private let ThinkingColor  = Color(hex: 0x9B7BFF)
private let SpeakingColor  = Color(hex: 0x4D8DFF)

// MARK: - MainPage

/// The app's main screen: a character voice-chat UI.
///
/// The user talks to (and texts with) the selected companion character. Speech recognition,
/// the on-device LLM and TTS are all owned by `VoiceAssistantViewModel`; this screen owns
/// only the presentation. Model download/selection and settings live in
/// `VoiceChatSettingsScreen`, reached via the gear icon.
///
/// - Parameters:
///   - modelManagerViewModel: Central model state (injected from app container).
///   - viewModel:             Shared `VoiceAssistantViewModel` (owned at the voice nav-graph scope).
///   - characterViewModel:    Selected character state.
///   - onOpenSettings:        Navigate to `VoiceChatSettingsScreen`.
///   - onOpenCharacters:      Navigate to the character picker screen.
struct MainPage: View {
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    @ObservedObject var viewModel: VoiceAssistantViewModel
    @ObservedObject var characterViewModel: CharacterViewModel
    let onOpenSettings: () -> Void
    let onOpenCharacters: () -> Void

    var body: some View {
        let charState = characterViewModel.state
        let selectedCharacter = characterViewModel.characterById(charState.selectedId)
            ?? characterViewModel.characters.first!
        let voiceTask = modelManagerViewModel.getTaskById(VOICE_ASSISTANT_TASK_ID)
        let voiceCustomTask = modelManagerViewModel.getCustomTaskByTaskId(VOICE_ASSISTANT_TASK_ID)
            as? VoiceAssistantTask

        if voiceTask == nil || voiceCustomTask == nil {
            // Tasks not loaded yet — show the character hero while we wait.
            ZStack {
                ScrimBase.ignoresSafeArea()
                Image(selectedCharacter.imageName)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }
        } else {
            VoiceChatContent(
                voiceTask: voiceTask!,
                selectedCharacter: selectedCharacter,
                modelManagerViewModel: modelManagerViewModel,
                viewModel: viewModel,
                characterViewModel: characterViewModel,
                onOpenSettings: onOpenSettings,
                onOpenCharacters: onOpenCharacters
            )
        }
    }
}

// MARK: - VoiceChatContent

private struct VoiceChatContent: View {
    let voiceTask: Task
    let selectedCharacter: Character
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    @ObservedObject var viewModel: VoiceAssistantViewModel
    @ObservedObject var characterViewModel: CharacterViewModel
    let onOpenSettings: () -> Void
    let onOpenCharacters: () -> Void

    @State private var inputText = ""
    @State private var emotionCue: EmotionCue? = nil
    @State private var lastCapabilityKey: (Int, Int) = (0, 0)

    private var mmState: ModelManagerUiState { modelManagerViewModel.uiState }
    private var uiState: VoiceAssistantUiState { viewModel.uiState }
    private var charState: CharacterState { characterViewModel.state }

    private var selectedModel: Model { mmState.selectedModel }
    private var modelReady: Bool {
        !selectedModel.name.isEmpty && mmState.isModelInitialized(selectedModel)
    }
    private var targetModel: Model? {
        let dlStatus = mmState.modelDownloadStatus
        func downloaded(_ name: String) -> Bool { dlStatus[name]?.status == .succeeded }
        if !selectedModel.name.isEmpty,
           voiceTask.models.contains(where: { $0.name == selectedModel.name }),
           downloaded(selectedModel.name) { return selectedModel }
        return voiceTask.models.first { downloaded($0.name) }
    }
    private var modelDownloaded: Bool { targetModel != nil }

    var body: some View {
        ZStack {
            // Hero: full-bleed character portrait.
            ScrimBase.ignoresSafeArea()
            Image(selectedCharacter.imageName)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            // Gradient scrim fading from face area to dark chat area.
            LinearGradient(
                stops: [
                    .init(color: ScrimBase.opacity(0.20), location: 0),
                    .init(color: ScrimBase.opacity(0.60), location: 0.42),
                    .init(color: ScrimBase.opacity(0.95), location: 0.70),
                    .init(color: ScrimBase,               location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            // Double-tap background to let the character keep talking.
            .onTapGesture(count: 2) { continueTalking() }

            VStack(spacing: 0) {
                // Top bar.
                topBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                // Upper spacer — keeps character face visible.
                Spacer()

                // Conversation transcript (lower half, bottom-anchored).
                conversationArea
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.height * 0.38)

                // Partial transcript.
                if uiState.isListening, !uiState.partialTranscript.isEmpty {
                    Text(uiState.partialTranscript)
                        .font(.system(size: 15))
                        .foregroundColor(ListeningColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 6)
                        .transition(.opacity)
                }
                // Error line.
                if !uiState.error.isEmpty {
                    Text(uiState.error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 4)
                }
                // Tool-activity chip.
                if !uiState.toolActivity.isEmpty {
                    ToolActivityChip(label: uiState.toolActivity)
                }

                // Bottom controls.
                if uiState.inputMode == .call {
                    CallControls(
                        isListening: uiState.isListening,
                        isThinking: uiState.isThinking,
                        isSpeaking: uiState.isSpeaking,
                        onEndCall: { viewModel.setInputMode(.standard) }
                    )
                    .padding(.bottom, 20)
                    .padding(.top, 6)
                } else {
                    InputBar(
                        enabled: modelReady,
                        disabledPlaceholder: modelDownloaded ? "잠시만요, 준비 중이에요…" : "설정에서 모델 받기",
                        isListening: uiState.isListening,
                        isThinking: uiState.isThinking,
                        isSpeaking: uiState.isSpeaking,
                        onSendText: { text in targetModel.map { viewModel.sendStarter(text, model: $0) } },
                        onMicClick: toggleMic,
                        onMicLongClick: enterCallMode
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.top, 4)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0) }

            // Floating emoji emotion overlay (non-interactive, on top of everything).
            EmotionOverlay(cue: emotionCue)
                .allowsHitTesting(false)

            // MCP permission dialog (rare in voice flow, but must be handled).
            if let req = viewModel.mcpPermissionRequest {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture { viewModel.resolveMcpPermission(.deny) }
                McpPermissionDialog(request: req, onResult: { viewModel.resolveMcpPermission($0) })
            }
        }
        // Headless wiring (model/TTS/STT status feeds, idempotent).
        .background(
            VoiceChatPlumbing(
                modelManagerViewModel: modelManagerViewModel,
                viewModel: viewModel
            )
        )
        // Initialize / re-initialize the model when target model or character changes.
        .task(id: "\(targetModel?.name ?? "")|\(charState.selectedId)") {
            guard let m = targetModel else { return }
            if selectedModel.name != m.name { modelManagerViewModel.selectModel(m) }
            let sig = "\(m.name)|\(charState.selectedId)"
            let changed = characterViewModel.needsModelInit(signature: sig)
            if changed || !mmState.isModelInitialized(m) {
                modelManagerViewModel.initializeModel(context: nil, task: voiceTask, model: m, force: true)
            }
        }
        // Switch conversation when character changes.
        .onChange(of: charState.selectedId) { id in
            viewModel.setConversation(id)
        }
        .onAppear { viewModel.setConversation(charState.selectedId) }
        // Apply assigned / default TTS voice when voices list changes.
        .onChange(of: uiState.voices.count) { _ in applyCharacterVoice() }
        .onChange(of: charState.selectedId) { _ in applyCharacterVoice() }
        .onAppear { applyCharacterVoice() }
        // Re-initialize when tool counts change.
        .onChange(of: uiState.mcpToolCount + uiState.skillCount) { _ in
            let key = (uiState.mcpToolCount, uiState.skillCount)
            guard key != lastCapabilityKey,
                  !selectedModel.name.isEmpty,
                  mmState.isModelInitialized(selectedModel) else {
                lastCapabilityKey = key; return
            }
            lastCapabilityKey = key
            modelManagerViewModel.initializeModel(context: nil, task: voiceTask, model: selectedModel, force: true)
        }
        // Greeting on first enter from "start chat" button.
        .task(id: "\(modelReady)|\(charState.selectedId)") {
            guard modelReady, characterViewModel.isGreetingPending(characterId: charState.selectedId) else { return }
            try? await Task.sleep(nanoseconds: 250_000_000) // let history load
            characterViewModel.clearGreeting()
            if uiState.messages.isEmpty { targetModel.map { viewModel.greet($0) } }
        }
        // Collect emotion cues.
        .onReceive(viewModel.emotionCues) { cue in emotionCue = cue }
        .onDisappear { viewModel.onDisappear() }
    }

    // MARK: - Sub-views

    @ViewBuilder private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedCharacter.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text(statusLabel(uiState, modelReady: modelReady, modelDownloaded: modelDownloaded))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            FrostedCircleButton(action: onOpenCharacters) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 17))
                    .foregroundColor(.white)
            }
            Spacer().frame(width: 10)
            FrostedCircleButton(action: onOpenSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17))
                    .foregroundColor(.white)
            }
        }
    }

    @ViewBuilder private var conversationArea: some View {
        if modelReady, uiState.messages.isEmpty {
            GreetingHint(characterName: selectedCharacter.name)
        } else if modelReady {
            Transcript(
                messages: uiState.messages,
                avatarName: selectedCharacter.imageName,
                onDeleteBefore: { viewModel.deleteMessagesBefore(index: $0) },
                onRegenerate: { viewModel.regenerate(assistantIndex: $0) },
                onNewChat: { viewModel.clearConversation() },
                onContinue: continueTalking
            )
        } else if modelDownloaded {
            PreparingHint(characterName: selectedCharacter.name)
        } else {
            NotReadyHint(onOpenSettings: onOpenSettings)
        }
    }

    // MARK: - Actions

    private func toggleMic() {
        if uiState.isListening {
            viewModel.stopListening()
        } else {
            // NOTE: iOS permission is requested automatically by SFSpeechRecognizer /
            // AVAudioEngine on first use. The SFSpeechRecognizer authorization prompt
            // is shown the first time `startListening()` is called.
            viewModel.startListening()
        }
    }

    private func enterCallMode() {
        guard modelReady else { return }
        viewModel.setInputMode(.call)
    }

    private func continueTalking() {
        guard modelReady, !uiState.isThinking else { return }
        targetModel.map { viewModel.continueTalking($0) }
    }

    private func applyCharacterVoice() {
        let assigned = charState.voiceByCharacter[charState.selectedId] ?? ""
        let effective = assigned.isEmpty ? charState.defaultVoiceId : assigned
        let target = effective.isEmpty ? (uiState.voices.first?.id ?? "") : effective
        if !target.isEmpty { viewModel.selectVoice(id: target) }
    }
}

// MARK: - Status label helper

private func statusLabel(_ state: VoiceAssistantUiState, modelReady: Bool, modelDownloaded: Bool) -> String {
    if !modelReady && modelDownloaded { return "모델을 불러오는 중이에요…" }
    if !modelReady { return "설정에서 AI 모델을 준비해 주세요" }
    if !state.toolActivity.isEmpty { return state.toolActivity }
    if state.isListening { return "듣고 있어요…" }
    if state.isThinking  { return "생각 중…" }
    if state.isSpeaking  { return "말하는 중…" }
    return "마이크를 누르거나 메시지를 입력하세요"
}

// MARK: - FrostedCircleButton

private struct FrostedCircleButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white.opacity(0.16)).frame(width: 40, height: 40)
                content()
            }
        }
    }
}

// MARK: - NotReadyHint / PreparingHint / GreetingHint

private struct NotReadyHint: View {
    let onOpenSettings: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Text("대화를 시작하려면 AI 모델이 필요해요")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("설정에서 모델을 한 번만 내려받으면 오프라인으로 대화할 수 있습니다.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button(action: onOpenSettings) {
                Text("설정 열기")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(LinearGradient(colors: [AccentPurple, AccentPink],
                                              startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PreparingHint: View {
    let characterName: String
    var body: some View {
        VStack(spacing: 18) {
            ProgressView().tint(.white).scaleEffect(1.3)
            Text("\(characterName)를 깨우는 중이에요…")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("모델을 처음 불러올 때는 시간이 조금 걸려요.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GreetingHint: View {
    let characterName: String
    var body: some View {
        VStack(spacing: 8) {
            Text("안녕! 나는 \(characterName)야. 편하게 말 걸어줘 😊")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("마이크를 눌러 음성으로, 또는 아래에 메시지를 입력해 대화를 시작하세요.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

// MARK: - Transcript

private struct Transcript: View {
    let messages: [VoiceMessage]
    let avatarName: String
    let onDeleteBefore: (Int) -> Void
    let onRegenerate: (Int) -> Void
    let onNewChat: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10, pinnedViews: []) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                        VoiceChatBubble(
                            message: message,
                            avatarName: avatarName,
                            canDeleteBefore: index > 0,
                            onDeleteBefore: { onDeleteBefore(index) },
                            onRegenerate: { onRegenerate(index) },
                            onNewChat: onNewChat,
                            onContinue: onContinue
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onTapGesture(count: 2) { onContinue() }
            .onChange(of: messages.count) { _ in
                withAnimation { proxy.scrollTo(messages.count - 1, anchor: .bottom) }
            }
        }
    }
}

// MARK: - VoiceChatBubble

private struct VoiceChatBubble: View {
    let message: VoiceMessage
    let avatarName: String
    let canDeleteBefore: Bool
    let onDeleteBefore: () -> Void
    let onRegenerate: () -> Void
    let onNewChat: () -> Void
    let onContinue: () -> Void

    @State private var menuOpen = false

    private var isUser: Bool { message.role == .user }
    private var isTyping: Bool { !isUser && message.isStreaming && message.text.isEmpty }

    var body: some View {
        if message.text.isEmpty && !isTyping { EmptyView() } else {
            HStack(alignment: .bottom, spacing: 0) {
                if isUser { Spacer(minLength: 40) }
                if !isUser {
                    Image(avatarName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                    Spacer().frame(width: 8)
                }
                Group {
                    if isTyping {
                        TypingDots()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    } else {
                        Text(message.text)
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .lineSpacing(4)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }
                .background(
                    isUser
                    ? AnyView(LinearGradient(colors: [AccentPurple, AccentPink],
                                             startPoint: .leading, endPoint: .trailing))
                    : AnyView(Color.white.opacity(0.14))
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
                .contextMenu {
                    Button("메시지 복사") {
                        UIPasteboard.general.string = message.text
                    }
                    if !isUser {
                        Button("다시 답하기") { onRegenerate() }
                    }
                    Button("이전 대화 삭제", role: canDeleteBefore ? nil : .destructive) {
                        if canDeleteBefore { onDeleteBefore() }
                    }
                    .disabled(!canDeleteBefore)
                    Button("새 대화 시작", role: .destructive) { onNewChat() }
                }
                if !isUser { Spacer(minLength: 40) }
            }
        }
    }
}

// MARK: - TypingDots

private struct TypingDots: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(0.3 + 0.7 * dotAlpha(i)))
                    .frame(width: 7, height: 7)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private func dotAlpha(_ i: Int) -> Double {
        let t = (phase + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
        return t < 0.5 ? t * 2 : 2 - t * 2
    }
}

// MARK: - ToolActivityChip

private struct ToolActivityChip: View {
    let label: String
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7).tint(ListeningColor)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.16))
        .clipShape(Capsule())
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }
}

// MARK: - InputBar

private struct InputBar: View {
    let enabled: Bool
    let disabledPlaceholder: String
    let isListening: Bool
    let isThinking: Bool
    let isSpeaking: Bool
    let onSendText: (String) -> Void
    let onMicClick: () -> Void
    let onMicLongClick: () -> Void

    @State private var text = ""
    private var canSend: Bool { enabled && !text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            // Text field pill.
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(enabled ? "메시지 입력…" : disabledPlaceholder)
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    TextField("", text: $text)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .disabled(!enabled)
                        .submitLabel(.send)
                        .onSubmit { if canSend { send() } }
                }
                .padding(.leading, 18)
                .padding(.trailing, 6)
                .padding(.vertical, 12)

                if canSend {
                    Button(action: send) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [AccentPurple, AccentPink],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: 40, height: 40)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing, 6)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .background(Color.white.opacity(0.14))
            .clipShape(Capsule())

            // Mic orb.
            MicOrb(
                enabled: enabled,
                isListening: isListening,
                isThinking: isThinking,
                isSpeaking: isSpeaking,
                onClick: onMicClick,
                onLongClick: onMicLongClick
            )
        }
        .animation(.easeInOut(duration: 0.18), value: canSend)
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        onSendText(t)
        text = ""
    }
}

// MARK: - MicOrb

private struct MicOrb: View {
    let enabled: Bool
    let isListening: Bool
    let isThinking: Bool
    let isSpeaking: Bool
    let onClick: () -> Void
    let onLongClick: () -> Void

    @State private var pulse: CGFloat = 0.9
    @GestureState private var pressing = false

    private var active: Bool { isListening || isThinking || isSpeaking }
    private var coreColor: Color {
        if isListening { return ListeningColor }
        if isThinking  { return ThinkingColor }
        if isSpeaking  { return SpeakingColor }
        return AccentPurple
    }
    private let coreSize: CGFloat = 60
    private var haloSize: CGFloat { coreSize * 1.27 }

    var body: some View {
        ZStack {
            // Glow halo.
            Circle()
                .fill(RadialGradient(
                    colors: [coreColor.opacity(0.95), coreColor.opacity(0.45), coreColor.opacity(0)],
                    center: .center, startRadius: 0, endRadius: haloSize / 2))
                .frame(width: haloSize, height: haloSize)
                .scaleEffect(pulse)
                .opacity(enabled ? 0.6 : 0.22)
                .blur(radius: coreSize * 0.12)

            // Core button.
            ZStack {
                Circle()
                    .fill(enabled
                          ? AnyShapeStyle(RadialGradient(colors: [coreColor, coreColor.opacity(0.65)],
                                                         center: .center, startRadius: 0, endRadius: coreSize / 2))
                          : AnyShapeStyle(Color.white.opacity(0.25)))
                    .frame(width: coreSize, height: coreSize)
                Image(systemName: isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: coreSize * 0.44))
                    .foregroundColor(.white)
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.7)
                    .onEnded { _ in if enabled { onLongClick() } }
                    .simultaneously(with: TapGesture().onEnded { if enabled { onClick() } })
            )
        }
        .frame(width: haloSize, height: haloSize)
        .onAppear { startPulse() }
        .onChange(of: active) { _ in startPulse() }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: isListening ? 0.55 : 1.3).repeatForever(autoreverses: true)) {
            pulse = active ? 1.18 : 1.04
        }
    }
}

// MARK: - CallControls

private struct CallControls: View {
    let isListening: Bool
    let isThinking: Bool
    let isSpeaking: Bool
    let onEndCall: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(callStatusLabel(isListening: isListening, isThinking: isThinking, isSpeaking: isSpeaking))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
            CallButton(
                isListening: isListening,
                isThinking: isThinking,
                isSpeaking: isSpeaking,
                onClick: onEndCall
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private func callStatusLabel(isListening: Bool, isThinking: Bool, isSpeaking: Bool) -> String {
    if isListening { return "듣고 있어요…" }
    if isThinking  { return "생각 중…" }
    if isSpeaking  { return "말하는 중…" }
    return "연결됨 · 말하면 들을게요"
}

private struct CallButton: View {
    let isListening: Bool
    let isThinking: Bool
    let isSpeaking: Bool
    let onClick: () -> Void

    @State private var pulse: CGFloat = 0.92
    @State private var ripple: CGFloat = 0

    private var active: Bool { isListening || isThinking || isSpeaking }
    private var glowColor: Color {
        if isListening { return ListeningColor }
        if isThinking  { return ThinkingColor }
        if isSpeaking  { return SpeakingColor }
        return AccentPurple
    }

    var body: some View {
        let haloSize: CGFloat = 132
        let coreSize: CGFloat = 88
        ZStack {
            // Expanding ripple.
            Circle()
                .fill(glowColor.opacity(0.5))
                .frame(width: haloSize, height: haloSize)
                .scaleEffect(0.6 + 0.5 * ripple)
                .opacity((active ? 0.5 : 0.25) * (1 - Double(ripple)))
            // Glow halo.
            Circle()
                .fill(RadialGradient(colors: [glowColor.opacity(0.9), glowColor.opacity(0.4), glowColor.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: haloSize / 2))
                .frame(width: haloSize, height: haloSize)
                .scaleEffect(pulse)
                .opacity(0.6)
            // Red hang-up core.
            Button(action: onClick) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: 0xF0555A), Color(hex: 0xD1383D)],
                                             center: .center, startRadius: 0, endRadius: coreSize / 2))
                        .frame(width: coreSize, height: coreSize)
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 34))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: haloSize, height: haloSize)
        .onAppear { startAnimation() }
        .onChange(of: active) { _ in startAnimation() }
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: isListening ? 0.6 : 1.4).repeatForever(autoreverses: true)) {
            pulse = active ? 1.16 : 1.04
        }
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            ripple = 1
        }
    }
}

// MARK: - McpPermissionDialog stub

/// Minimal dialog for MCP tool-call permission requests.
/// NOTE: Replace with a real McpToolCallPermissionDialog from the AgentChat module.
private struct McpPermissionDialog: View {
    let request: McpToolCallPermissionRequest
    let onResult: (PermissionResult) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(Str.mcpToolCallPermissionTitle)
                .font(.headline)
            Text("\(Str.mcpToolNameLabel): \(request.toolName)")
                .font(.subheadline)
            if !request.argument.isEmpty {
                Text(request.argument)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                Button(Str.mcpToolDontAllow) { onResult(.deny) }
                Button(Str.mcpToolAllowOnce) { onResult(.allow) }
                    .buttonStyle(.borderedProminent)
                Button(Str.mcpToolAlwaysAllow) { onResult(.alwaysAllow) }
            }
        }
        .padding(24)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 32)
    }
}

// MARK: - ModelManagerViewModel convenience stubs
// NOTE: `selectModel` and `initializeModel` are expected to be defined on
// ModelManagerViewModel. If missing, add them in ModelManagerViewModel.swift.
// The stubs below are no-ops so MainPage compiles; replace with real forwarding calls.

private extension ModelManagerViewModel {
    /// `context:` overload forwarding to the real `initializeModel(task:model:force:)`.
    /// (`selectModel(_:)` is provided by the base view model.)
    func initializeModel(context: Any?, task: Task, model: Model, force: Bool) {
        initializeModel(task: task, model: model, force: force)
    }
}

// Color(hex:) is defined in UI/Theme/Color.swift — no re-declaration needed.
