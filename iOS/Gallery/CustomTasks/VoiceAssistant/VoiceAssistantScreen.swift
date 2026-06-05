// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Port of customtasks/voiceassistant/VoiceAssistantScreen.kt
//
// This is the standalone Voice Assistant screen reached via the home-screen task card.
// The companion voice-chat experience on the app's main page lives in UI/MainPage/MainPage.swift.

import SwiftUI

/// The main screen for the Voice Assistant custom task (standalone, from home task card).
struct VoiceAssistantScreen: View {

    let task: Task
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel

    // NOTE: In the full wiring the VoiceAssistantViewModel is provided at the parent
    // nav-graph scope. Here we create a local one for standalone task use.
    // When AppContainer vends a shared VoiceAssistantViewModel, use @EnvironmentObject instead.
    @StateObject private var viewModel: VoiceAssistantViewModel

    init(task: Task, modelManagerViewModel: ModelManagerViewModel) {
        self.task = task
        self.modelManagerViewModel = modelManagerViewModel
        // Create a local ViewModel for standalone use.
        // NOTE: Replace with @EnvironmentObject injection when AppContainer is wired.
        let repo = CharacterRepository()
        let historyStore = ChatHistoryStore()
        let entryParams = VoiceAssistantEntryParams()
        let promptSource = SampleVoiceAssistantPromptSource(characterRepository: repo)
        _viewModel = StateObject(wrappedValue: VoiceAssistantViewModel(
            promptSource: promptSource,
            entryParams: entryParams,
            chatHistoryStore: historyStore,
            characterRepository: repo
        ))
    }

    var body: some View {
        let uiState = viewModel.uiState
        let mmState = modelManagerViewModel.uiState
        let model = mmState.selectedModel

        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x05060E), Color(hex: 0x0B1026), Color(hex: 0x030308)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if !mmState.isModelInitialized(model) {
                ProgressView()
                    .tint(Color(hex: 0x7C4DFF))
                    .scaleEffect(1.4)
            } else {
                VStack(spacing: 0) {
                    Spacer().frame(height: 16)

                    // Title + status
                    Text(uiState.topicTitle.isEmpty ? task.label : uiState.topicTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    Text(statusLabel(uiState))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer().frame(height: 12)

                    // Voice orb
                    VoiceOrb(isListening: uiState.isListening,
                             isThinking: uiState.isThinking,
                             isSpeaking: uiState.isSpeaking)

                    Spacer().frame(height: 12)

                    // Conversation area
                    Group {
                        if uiState.messages.isEmpty {
                            VoiceEmptyState(starters: uiState.starters) { starter in
                                viewModel.sendStarter(starter, model: model)
                            }
                        } else {
                            VoiceTranscript(messages: uiState.messages)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Partial transcript
                    if uiState.isListening, !uiState.partialTranscript.isEmpty {
                        Text(uiState.partialTranscript)
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: 0x34E1C4))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 4)
                    }
                    if !uiState.error.isEmpty {
                        Text(uiState.error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 4)
                    }

                    Spacer().frame(height: 12)

                    // Mic button
                    MicButton(isListening: uiState.isListening) {
                        if uiState.isListening {
                            viewModel.stopListening()
                        } else {
                            viewModel.startListening()
                        }
                    }
                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle(task.label)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.setActiveModel(model)
        }
        .onChange(of: model.name) { _ in
            viewModel.setActiveModel(model)
        }
        .onDisappear { viewModel.onDisappear() }
    }
}

// MARK: - Status label helper

private func statusLabel(_ state: VoiceAssistantUiState) -> String {
    switch true {
    case state.isListening: return "듣고 있어요…"
    case state.isThinking:  return "생각 중…"
    case state.isSpeaking:  return "말하는 중…"
    default:                return "마이크를 누르고 말해보세요"
    }
}

// MARK: - VoiceOrb

private struct VoiceOrb: View {
    let isListening: Bool
    let isThinking: Bool
    let isSpeaking: Bool

    @State private var pulse: CGFloat = 0.92
    @State private var angle: Double = 0

    private var active: Bool { isListening || isSpeaking || isThinking }
    private var coreColor: Color {
        if isListening { return Color(hex: 0x34E1C4) }
        if isThinking  { return Color(hex: 0x9B7BFF) }
        if isSpeaking  { return Color(hex: 0x4D8DFF) }
        return Color(hex: 0x5C6BC0)
    }

    var body: some View {
        ZStack {
            // Outer halo (rotating sweep gradient simulated with a tinted circle).
            Circle()
                .fill(coreColor.opacity(0.25))
                .frame(width: 200, height: 200)
                .scaleEffect(pulse)
                .rotationEffect(.degrees(angle))
            // Glowing core.
            Circle()
                .fill(RadialGradient(
                    colors: [coreColor.opacity(0.95), coreColor.opacity(0.25)],
                    center: .center, startRadius: 0, endRadius: 60))
                .frame(width: 120, height: 120)
                .scaleEffect(pulse)
        }
        .frame(width: 200, height: 200)
        .onAppear { startAnimation() }
        .onChange(of: active) { _ in startAnimation() }
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: isListening ? 0.6 : 1.4).repeatForever(autoreverses: true)) {
            pulse = active ? 1.12 : 1.0
        }
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            angle = 360
        }
    }
}

// MARK: - MicButton

private struct MicButton: View {
    let isListening: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isListening ? Color.red : Color(hex: 0x7C4DFF))
                    .frame(width: 72, height: 72)
                Image(systemName: isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - VoiceEmptyState

private struct VoiceEmptyState: View {
    let starters: [String]
    let onStarter: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("이렇게 말해보세요…")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            ForEach(starters, id: \.self) { starter in
                Button(action: { onStarter(starter) }) {
                    Text(starter)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }
}

// MARK: - VoiceTranscript

private struct VoiceTranscript: View {
    let messages: [VoiceMessage]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        VoiceChatBubbleView(message: message)
                            .id(messages.endIndex)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _ in
                proxy.scrollTo(messages.endIndex, anchor: .bottom)
            }
        }
    }
}

private struct VoiceChatBubbleView: View {
    let message: VoiceMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            let isUser = message.role == .user
            Text(message.text.isEmpty && message.isStreaming ? "…" : message.text)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser
                    ? AnyView(LinearGradient(colors: [Color(hex: 0x7C4DFF), Color(hex: 0xE15BD0)],
                                             startPoint: .leading, endPoint: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: 18)))
                    : AnyView(Color.white.opacity(0.14).clipShape(RoundedRectangle(cornerRadius: 18)))
                )
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

// Color(hex:) is defined in UI/Theme/Color.swift — no re-declaration needed.
