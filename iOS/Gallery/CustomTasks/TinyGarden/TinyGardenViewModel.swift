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

// Port of customtasks/tinygarden/TinyGardenViewModel.kt

import Foundation
import Combine

/// Lightweight message for the Tiny Garden conversation history.
/// Uses the same side concept as Android's `ChatMessage`.
enum TinyGardenMessageSide { case user, agent, system }

struct TinyGardenMessage: Identifiable {
    let id = UUID()
    let content: String
    let side: TinyGardenMessageSide
    let isWarning: Bool

    init(content: String, side: TinyGardenMessageSide, isWarning: Bool = false) {
        self.content = content
        self.side = side
        self.isWarning = isWarning
    }
}

/// UI state for the TinyGarden screen. Mirrors `TinyGardenUiState`.
struct TinyGardenUiState {
    var processing: Bool = false
    var resettingEngine: Bool = false
    var messages: [TinyGardenMessage] = []
    var numTurns: Int = 0
}

/// ViewModel for TinyGardenScreen. Mirrors `TinyGardenViewModel`.
@MainActor
final class TinyGardenViewModel: ObservableObject {
    @Published var uiState = TinyGardenUiState()

    let dataStoreRepository: DataStoreRepository

    private var isResettingConversation = false

    init(dataStoreRepository: DataStoreRepository) {
        self.dataStoreRepository = dataStoreRepository
    }

    // MARK: - State mutations

    func addMessage(_ message: TinyGardenMessage) {
        uiState.messages.append(message)
    }

    func clearMessages() {
        uiState.messages = []
    }

    func setProcessing(_ processing: Bool) { uiState.processing = processing }
    func setResettingEngine(_ resetting: Bool) { uiState.resettingEngine = resetting }
    func incrementNumTurns() { uiState.numTurns += 1 }
    func resetNumTurns() { uiState.numTurns = 0 }

    // MARK: - Inference

    /// Sends the user instruction to the model and reports back via callbacks.
    /// Mirrors `getCommand(model:instructionText:onDone:onError:)`.
    ///
    /// NOTE: The real on-device inference (litertlm) would use a blocking
    /// `conversation.sendMessage(Contents)` call on a background thread. Here
    /// we route through LlmModelHelper.runInference which is bridged by
    /// StubLlmModelHelper on iOS. The stub fires onDone with an empty response;
    /// actual tool dispatch happens inside the real runtime — the screen observes
    /// the commandFlow channel instead of the text response.
    func getCommand(
        model: Model,
        instructionText: String,
        onDone: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard model.instance != nil else {
            setProcessing(false)
            return
        }

        incrementNumTurns()
        addMessage(TinyGardenMessage(content: instructionText, side: .user))

        setProcessing(true)

        // NOTE: LlmModelHelper is accessed via AppContainer.sharedLlmHelper.
        // The stub delivers a placeholder response; a real backend would invoke
        // TinyGardenToolSet callbacks during generation.
        AppContainer.sharedLlmHelper?.runInference(
            model: model,
            input: instructionText,
            resultListener: { [weak self] partial, done, _ in
                _Concurrency.Task { @MainActor [weak self] in
                    if done {
                        self?.setProcessing(false)
                        onDone(partial)
                    }
                }
            },
            cleanUpListener: {},
            onError: { [weak self] error in
                _Concurrency.Task { @MainActor [weak self] in
                    self?.setProcessing(false)
                    onError(error)
                }
            }
        )
    }

    // MARK: - Engine reset

    func resetEngine(
        model: Model,
        tools: [ToolProvider],
        onError: @escaping (String) -> Void
    ) {
        resetNumTurns()
        _Concurrency.Task { @MainActor in
            setResettingEngine(true)
            AppContainer.sharedLlmHelper?.cleanUp(model: model) { [weak self] in
                AppContainer.sharedLlmHelper?.initialize(
                    model: model,
                    taskId: BuiltInTaskId.LLM_TINY_GARDEN,
                    supportImage: false,
                    supportAudio: false,
                    systemInstruction: getTinyGardenSystemPrompt(),
                    tools: tools,
                    enableConversationConstrainedDecoding: true,
                    onDone: { [weak self] error in
                        _Concurrency.Task { @MainActor [weak self] in
                            self?.setResettingEngine(false)
                            if !error.isEmpty { onError(error) }
                            self?.addMessage(TinyGardenMessage(
                                content: Str.enginResetMessage,
                                side: .system, isWarning: true))
                        }
                    }
                )
            }
        }
    }

    // MARK: - Conversation reset

    func resetConversation(
        model: Model,
        tools: [ToolProvider],
        prevSeed: String,
        prevPlots: String,
        prevAction: String
    ) {
        resetNumTurns()
        _Concurrency.Task { @MainActor in
            isResettingConversation = true
            let sysPrompt = getTinyGardenSystemPrompt(
                prevSeed: prevSeed, prevPlots: prevPlots, prevAction: prevAction)
            AppContainer.sharedLlmHelper?.resetConversation(
                model: model,
                supportImage: false,
                supportAudio: false,
                systemInstruction: sysPrompt,
                tools: tools,
                enableConversationConstrainedDecoding: true
            )
            isResettingConversation = false
            addMessage(TinyGardenMessage(
                content: Str.conversationResetMessage,
                side: .system, isWarning: true))
        }
    }
}
