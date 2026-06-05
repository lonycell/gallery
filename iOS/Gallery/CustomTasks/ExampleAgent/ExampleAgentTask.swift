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

// Port of customtasks/exampleagent/ExampleAgentTask.kt
//
// TEMPLATE: wires an on-device LLM to ExampleAgentTools (date/time, calculator,
// word count). Use as a starting point for your own tools, skills, agents,
// and MCP integrations.

import Foundation
import SwiftUI

/// The task id of the example agent. Mirrors `EXAMPLE_AGENT_TASK_ID`.
let EXAMPLE_AGENT_TASK_ID = "example_agent"

/// TEMPLATE custom task. Mirrors `ExampleAgentTask`.
final class ExampleAgentTask: CustomTask {

    // The functions the model can call. `onToolCalled` is a progress hook.
    private let tools: ExampleAgentTools

    private let _task: Task

    init() {
        tools = ExampleAgentTools(onToolCalled: { label in
            // NOTE: Surface `label` to the UI for a "tool activity" indicator.
            // Bind into ExampleAgentViewModel or a shared state object as needed.
        })

        _task = Task(
            id: EXAMPLE_AGENT_TASK_ID,
            label: "Example Agent",
            category: Category.EXPERIMENTAL,
            icon: .system("point.3.connected.trianglepath.dotted"),
            description: "A template task that connects an on-device LLM to local function-calling tools (date/time, calculator, word count). Use it as a starting point for your own tools, skills, agents, and MCP integrations.",
            shortDescription: "Tool-calling agent template",
            docUrl: "https://github.com/google-ai-edge/gallery/blob/main/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/exampleagent/README.md",
            sourceCodeUrl: "https://github.com/google-ai-edge/gallery/blob/main/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/exampleagent",
            models: [],
            modelNames: ["Gemma3-1B-IT"],
            experimental: true
        )
    }

    var task: Task { _task }

    func initializeModelFn(model: Model, systemInstruction: Contents?, onDone: @escaping (String) -> Void) {
        // A short system prompt nudges the model to use tools. Mirrors Android ExampleAgentTask.
        let systemPrompt =
            "You are a helpful assistant with access to tools. When a request needs the current time, " +
            "arithmetic, or a word count, CALL THE MATCHING TOOL instead of guessing. Keep replies short."

        // NOTE: LlmModelHelper.initialize is the bridge point for on-device inference.
        // Pass `tools` so the runtime can register the function-calling context.
        // The real backend (MediaPipe/LiteRT) will invoke ExampleAgentTools.dispatch()
        // when the model emits a function-call token.
        if let helper = AppContainer.sharedLlmHelper {
            helper.initialize(
                model: model,
                taskId: EXAMPLE_AGENT_TASK_ID,
                supportImage: false,
                supportAudio: false,
                systemInstruction: systemPrompt,
                // NOTE: `tools` is ExampleAgentTools which conforms to AnyObject (class).
                // Cast to [ToolProvider] (AnyObject) for the LlmModelHelper protocol.
                tools: [tools as AnyObject],
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
        guard let customTaskData = data as? CustomTaskData else {
            return AnyView(EmptyView())
        }
        return AnyView(
            ExampleAgentScreen(
                task: _task,
                modelManagerViewModel: customTaskData.modelManagerViewModel
            )
        )
    }
}
