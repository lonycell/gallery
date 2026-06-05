/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Port of customtasks/mobileactions/MobileActionsScreen.kt

import SwiftUI

// Prompt templates shown as chips above the text input.
private struct PromptTemplateItem: Identifiable {
    let id = UUID()
    let label: String
    let prompt: String
}

private let promptTemplates: [PromptTemplateItem] = [
    PromptTemplateItem(label: "💡 켜기",           prompt: "Turn on flashlight"),
    PromptTemplateItem(label: "💡 끄기",           prompt: "Turn off flashlight"),
    PromptTemplateItem(label: "연락처 추가",        prompt: "Create contact John Smith with email address js@example.com and phone number 123 456 7890."),
    PromptTemplateItem(label: "이메일 보내기",      prompt: "Send an email to js@example.com with subject \"Meeting\" and body \"Hi John, let's meet at 3pm tomorrow.\""),
    PromptTemplateItem(label: "일정 만들기",        prompt: "Create a calendar event at 2:30pm tomorrow for \"team meeting\""),
    PromptTemplateItem(label: "지도에서 위치 보기", prompt: "Show Googleplex on map"),
    PromptTemplateItem(label: "Wi-Fi 설정 열기",   prompt: "Open WIFI settings"),
]

private struct SampleActionItem: Identifiable {
    let id = UUID()
    let label: String
    let systemImage: String
}

private let sampleActionItems: [SampleActionItem] = [
    SampleActionItem(label: "플래시라이트 켜기/끄기", systemImage: "flashlight.on.fill"),
    SampleActionItem(label: "연락처 추가",            systemImage: "person.badge.plus"),
    SampleActionItem(label: "이메일 보내기",          systemImage: "envelope"),
    SampleActionItem(label: "일정 만들기",            systemImage: "calendar.badge.plus"),
    SampleActionItem(label: "지도에서 위치 보기",     systemImage: "map"),
    SampleActionItem(label: "Wi-Fi 설정 열기",        systemImage: "wifi"),
]

// Tab identifiers
private enum ResponseTab: String, CaseIterable {
    case modelResponse = "Model Response"
    case functionCalled = "Function Called"

    var systemImage: String {
        switch self {
        case .modelResponse:  return "doc.text"
        case .functionCalled: return "function"
        }
    }
}

/// Main screen for the Mobile Actions feature.
/// Mirrors `MobileActionsScreen` + `MainUi` composables.
struct MobileActionsScreen: View {
    let task: Task
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    var bottomPadding: CGFloat = 0
    var setAppBarControlsDisabled: (Bool) -> Void = { _ in }
    /// Observable list of actions recognized by the model. Mirrors `curActions: SnapshotStateList`.
    @Binding var curActions: [Action]
    var onProcessingStarted: () -> Void = {}

    @StateObject private var viewModel = MobileActionsViewModel()
    @Environment(\.galleryColors) private var colors
    @Environment(\.customColors) private var customColors

    @State private var selectedTab: ResponseTab = .modelResponse
    @State private var inputText: String = ""
    @State private var showErrorDialog: Bool = false
    @State private var errorDialogContent: String = ""
    @State private var errorMessage: String = ""
    @State private var doneGeneratingResponse: Bool = false

    var body: some View {
        let modelManagerState = modelManagerViewModel.uiState
        let model = modelManagerState.selectedModel

        VStack(spacing: 0) {
            if !modelManagerState.isModelInitialized(model) {
                // Loading indicator before model is initialized.
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                Spacer()
            } else {
                mainContent(model: model)
            }
        }
        .background(colors.surface)
        .alert(Str.error, isPresented: $showErrorDialog) {
            Button(Str.cancel, role: .cancel) {
                showErrorDialog = false
                errorDialogContent = ""
            }
            Button(Str.reset) {
                showErrorDialog = false
                errorDialogContent = ""
                viewModel.reset()
            }
        } message: {
            Text(errorDialogContent)
        }
        .onDisappear { viewModel.cleanUp() }
    }

    // MARK: - Main content

    @ViewBuilder
    private func mainContent(model: Model) -> some View {
        VStack(spacing: 0) {
            if viewModel.uiState.showWelcomeMessage {
                welcomeView
            } else {
                responseArea
            }

            inputArea(model: model)
        }
        .padding(.bottom, bottomPadding)
    }

    // MARK: - Welcome view

    private var welcomeView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 40)

                Text("Mobile Actions")
                    .font(AppTypography.headlineLarge)
                    .foregroundColor(taskIconColor)

                Text("Perform various device actions through Function Gemma")
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(taskIconColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("지원 액션")
                        .font(AppTypography.labelLarge)
                        .foregroundColor(colors.onSurfaceVariant)
                        .opacity(0.7)
                        .padding(.top, 32)

                    ForEach(sampleActionItems) { item in
                        Label(item.label, systemImage: item.systemImage)
                            .font(AppTypography.labelLarge)
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Response area

    private var responseArea: some View {
        VStack(spacing: 0) {
            // User prompt header.
            Text(viewModel.uiState.userPrompt)
                .font(AppTypography.bodyLarge)
                .foregroundColor(colors.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(colors.surfaceContainer)

            if viewModel.uiState.processing {
                // Loading indicator while processing.
                HStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                }
                .padding(16)
                Spacer()
            } else {
                // Tab bar (Model Response / Function Called).
                Picker("Tab", selection: $selectedTab) {
                    ForEach(ResponseTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Tab content.
                ScrollView {
                    switch selectedTab {
                    case .modelResponse:
                        modelResponseContent
                    case .functionCalled:
                        functionCalledContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut, value: selectedTab)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var modelResponseContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarkdownText(text: viewModel.uiState.modelResponse)
                .padding(16)

            if viewModel.uiState.noFunctionRecognized {
                Text("인식된 함수 호출이 없습니다.")
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(customColors.warningTextColor)
                    .padding(16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var functionCalledContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            let details = viewModel.uiState.functionCallDetails
            ForEach(Array(details.enumerated()), id: \.offset) { index, detail in
                MarkdownText(text: detail)
                    .padding(16)
                if index < details.count - 1 {
                    Divider().padding(.horizontal, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Input area

    private func inputArea(model: Model) -> some View {
        VStack(spacing: 8) {
            // Prompt chips row.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Spacer(minLength: 12)
                    ForEach(promptTemplates) { item in
                        Button(item.label) {
                            guard !viewModel.uiState.processing else { return }
                            send(text: item.prompt, model: model)
                        }
                        .font(AppTypography.labelLarge)
                        .foregroundColor(colors.onSurfaceVariant)
                        .padding(12)
                        .background(colors.surfaceContainerLow)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colors.outlineVariant, lineWidth: 1)
                        )
                        .opacity(viewModel.uiState.processing ? 0.5 : 1)
                    }
                    Spacer(minLength: 12)
                }
            }

            // Text input row.
            HStack(spacing: 8) {
                TextField(Str.chatTextinputPlaceholder, text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(viewModel.uiState.processing)

                Button {
                    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    inputText = ""
                    send(text: text, model: model)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(viewModel.uiState.processing ? colors.onSurfaceVariant.opacity(0.3) : taskIconColor)
                }
                .disabled(viewModel.uiState.processing)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Send action

    private func send(text: String, model: Model) {
        selectedTab = .modelResponse
        onProcessingStarted()
        doneGeneratingResponse = false

        viewModel.processUserPrompt(
            model: model,
            userPrompt: text,
            onProcessDone: {
                doneGeneratingResponse = true

                if !self.curActions.isEmpty {
                    var errors: [String] = []
                    for action in self.curActions {
                        let err = self.viewModel.performAction(action)
                        if err.isEmpty {
                            let formatted = self.genFormattedFunctionCall(action: action)
                            self.viewModel.addFunctionCallDetails(formatted)
                        } else {
                            errors.append(err)
                        }
                    }
                    if !errors.isEmpty {
                        self.errorMessage = errors.joined(separator: "; ")
                    }
                } else {
                    self.viewModel.setNoFunctionRecognized(true)
                }
            },
            onError: { error in
                doneGeneratingResponse = true
                errorDialogContent = error
                showErrorDialog = true
            }
        )
    }

    // MARK: - Helpers

    private var taskIconColor: Color {
        customColors.taskIconColors.first ?? colors.primary
    }

    private func genFormattedFunctionCall(action: Action) -> String {
        let fnName = action.functionCallDetails.functionName
        var content = "**\(Str.functionName)**:\n- \(fnName)"
        if !action.functionCallDetails.parameters.isEmpty {
            let paramLabel = action.functionCallDetails.parameters.count == 1 ? "Parameter" : "Parameters"
            let strParams = action.functionCallDetails.parameters
                .map { "- \($0.0): \"\($0.1)\"" }
                .joined(separator: "\n")
            content += "\n\n**\(paramLabel)**:\n\(strParams)"
        }
        return content
    }
}

// NOTE: MarkdownText is provided by the app foundation in UI/Common/MarkdownText.swift.
// It is used directly above — no local shim needed.
