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

// Port of customtasks/exampleagent/ExampleAgentViewModel.kt
//
// TEMPLATE: a minimal ViewModel that runs LLM inference (with tools) and streams
// the reply. Tool calls happen transparently inside LlmModelHelper.runInference —
// the ViewModel does not call tools directly.

import Foundation
import Combine

/// A single chat turn. Mirrors `ExampleMessage`.
struct ExampleMessage: Identifiable {
    let id = UUID()
    let fromUser: Bool
    var text: String
    var streaming: Bool = false
}

/// UI state for the example agent screen. Mirrors `ExampleAgentUiState`.
struct ExampleAgentUiState {
    var messages: [ExampleMessage] = []
    var generating: Bool = false
    var error: String = ""
}

/// TEMPLATE: minimal ViewModel for the example agent. Mirrors `ExampleAgentViewModel`.
@MainActor
final class ExampleAgentViewModel: ObservableObject {
    @Published var uiState = ExampleAgentUiState()

    func send(model: Model, input: String) {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !uiState.generating else { return }

        uiState.messages.append(ExampleMessage(fromUser: true, text: input))
        uiState.messages.append(ExampleMessage(fromUser: false, text: "", streaming: true))
        uiState.generating = true
        uiState.error = ""

        var builder = ""

        // NOTE: Route through LlmModelHelper (AppContainer.sharedLlmHelper).
        // Because the model was initialized with ExampleAgentTools (via ExampleAgentTask),
        // the real runtime invokes @Tool functions automatically and continues
        // generating — the ViewModel just accumulates text deltas.
        AppContainer.sharedLlmHelper?.runInference(
            model: model,
            input: input,
            resultListener: { [weak self] partial, done, _ in
                _Concurrency.Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !partial.hasPrefix("<ctrl") {
                        builder += partial
                        self.updateAssistant(text: builder, streaming: !done)
                    }
                    if done {
                        self.uiState.generating = false
                    }
                }
            },
            cleanUpListener: {},
            onError: { [weak self] message in
                _Concurrency.Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.uiState.generating = false
                    self.uiState.error = message.isEmpty ? "Error" : message
                    self.updateAssistant(text: builder, streaming: false)
                }
            }
        )
    }

    private func updateAssistant(text: String, streaming: Bool) {
        guard let idx = uiState.messages.indices.last(where: { !uiState.messages[$0].fromUser }) else { return }
        uiState.messages[idx].text = text
        uiState.messages[idx].streaming = streaming
    }
}
