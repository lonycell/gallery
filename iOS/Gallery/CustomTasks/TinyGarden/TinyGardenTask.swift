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

// Port of customtasks/tinygarden/TinyGardenTask.kt

import Foundation
import SwiftUI

private let SYSTEM_PROMPT = """
You are an assistant helping the user play a game about gardening.

The environment is a 3x3 grid of garden plots. The plots are numbered 1 through 9.

**Garden Plot Layout**:

- Row 1: Plots 1, 2, 3 (top row)
- Row 2: Plots 4, 5, 6 (middle row)
- Row 3: Plots 7, 8, 9 (bottom row)

Help the user plant seeds, water plots, and harvest flowers.

There are 4 kinds of seeds you can plant:

1. sunflower
2. daisy
3. rose
4. special (edge gallery, special, secret)

Plot Array: For each action, identify all individual plot numbers (1-9) or implied plots (e.g., 'top row' -> 1, 2, 3) and collect them into the `plots` list.

Tips:

- "top row" has plots 1, 2, 3.
- "middle row" has plots 4, 5, 6.
- "bottom row" has plots 7, 8, 9.
- "left column" has plots 1, 4, 7.
- "middle column" has plots 2, 5, 8.
- "right column" has plots 3, 6, 9.
"""

/// Returns the system prompt, optionally augmented with the user's last action context.
/// Mirrors `getTinyGardenSystemPrompt(prevSeed:prevPlots:prevAction:)` on Android.
func getTinyGardenSystemPrompt(prevSeed: String = "", prevPlots: String = "", prevAction: String = "") -> String {
    var parts = [SYSTEM_PROMPT]
    if !prevSeed.isEmpty || !prevPlots.isEmpty || !prevAction.isEmpty {
        parts.append("Here is the info about user's last action:")
    }
    if !prevSeed.isEmpty   { parts.append("- seed: \(prevSeed)") }
    if !prevPlots.isEmpty  { parts.append("- plots: \(prevPlots)") }
    if !prevAction.isEmpty { parts.append("- action: \(prevAction)") }
    return parts.joined(separator: "\n")
}

/// Custom task for the Tiny Garden game. Mirrors `TinyGardenTask`.
final class TinyGardenTask: CustomTask {

    private let _task: Task

    // Async stream of commands emitted by TinyGardenToolSet.
    // Mirrors `Channel<TinyGardenCommand>` + `commandFlow` on Android.
    private var commandContinuation: AsyncStream<TinyGardenCommand>.Continuation?
    private let commandStream: AsyncStream<TinyGardenCommand>

    private let toolSet: TinyGardenToolSet
    private var tools: [ToolProvider] { [toolSet] }

    // Retained view model so it outlives the mainScreen() call.
    private var viewModel: TinyGardenViewModel?

    init() {
        var continuation: AsyncStream<TinyGardenCommand>.Continuation?
        commandStream = AsyncStream<TinyGardenCommand> { cont in continuation = cont }
        commandContinuation = continuation

        toolSet = TinyGardenToolSet { command in
            continuation?.yield(command)
        }

        _task = Task(
            id: BuiltInTaskId.LLM_TINY_GARDEN,
            label: "Tiny Garden",
            category: Category.LLM,
            icon: .system("leaf"),
            description: "Use natural language to plant, water, and harvest in this fully offline mini-game.\n\nNote: This is powered by the experimental FunctionGemma model optimized for latency. Due to its compact size (270M), it works well on simple instructions but responses may vary to more complex interactions.",
            shortDescription: "Use natural language to plant",
            docUrl: "https://github.com/google-ai-edge/LiteRT-LM/blob/main/kotlin/README.md",
            sourceCodeUrl: "https://github.com/google-ai-edge/gallery/blob/main/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/tinygarden",
            models: [],
            handleModelConfigChangesInTask: true,
            experimental: true,
            defaultSystemPrompt: SYSTEM_PROMPT,
            agentName: Str.chatAgentAgentName
        )
    }

    var task: Task { _task }

    func initializeModelFn(model: Model, systemInstruction: Contents?, onDone: @escaping (String) -> Void) {
        // Drain any pending commands from a previous session.
        // (AsyncStream has no tryReceive; we rely on the stream being re-created per-task-init.)
        if let helper = AppContainer.sharedLlmHelper {
            helper.initialize(
                model: model,
                taskId: BuiltInTaskId.LLM_TINY_GARDEN,
                supportImage: false,
                supportAudio: false,
                systemInstruction: getTinyGardenSystemPrompt(),
                tools: tools,
                enableConversationConstrainedDecoding: true,
                onDone: onDone
            )
        } else {
            onDone("LlmModelHelper not available")
        }
    }

    func cleanUpModelFn(model: Model, onDone: @escaping () -> Void) {
        AppContainer.sharedLlmHelper?.cleanUp(model: model, onDone: onDone) ?? { onDone() }()
    }

    @MainActor func mainScreen(data: Any) -> AnyView {
        guard let customTaskData = data as? CustomTaskData,
              let store = AppContainer.sharedDataStore else {
            return AnyView(EmptyView())
        }
        // Create (or reuse) the VM so it persists across recompositions.
        if viewModel == nil {
            viewModel = TinyGardenViewModel(dataStoreRepository: store)
        }
        let vm = viewModel!
        return AnyView(
            TinyGardenScreen(
                task: _task,
                modelManagerViewModel: customTaskData.modelManagerViewModel,
                tools: tools,
                bottomPadding: customTaskData.bottomPadding,
                setAppBarControlsDisabled: customTaskData.setAppBarControlsDisabled,
                setTopBarVisible: customTaskData.setTopBarVisible,
                commandFlow: commandStream,
                viewModel: vm
            )
        )
    }
}

// NOTE: AppContainer.sharedLlmHelper and AppContainer.sharedDataStore are declared
// in MobileActionsTask.swift and shared across all custom task modules.
