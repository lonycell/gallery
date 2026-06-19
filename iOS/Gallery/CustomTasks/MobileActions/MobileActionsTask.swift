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

// Port of customtasks/mobileactions/MobileActionsTask.kt

import Foundation
import SwiftUI

/// Builds the system instruction with the current date/time.
/// Mirrors `getSystemPrompt()` in Android.
func getMobileActionsSystemPrompt() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    let curDateTimeString = formatter.string(from: Date())
    let dayFormatter = DateFormatter()
    dayFormatter.dateFormat = "EEEE"
    let dayOfWeek = dayFormatter.string(from: Date())
    return [
        "You are a model that can do function calling with the following functions",
        "Current date and time given in YYYY-MM-DDTHH:MM:SS format: \(curDateTimeString)\nDay of week is \(dayOfWeek)",
    ].joined(separator: "\n")
}

/// A custom task that uses function calling to control various device functionalities.
/// Mirrors `MobileActionsTask`.
final class MobileActionsTask: CustomTask {

    /// Observable list of recognized actions passed to the screen.
    /// Mirrors `curActions: SnapshotStateList<Action>` on Android.
    var curActions: [Action] = []

    /// The tool set (JSON specs + dispatch) for function calling.
    private let toolSet: MobileActionsToolSet

    // NOTE: On Android `tools` was a `List<ToolProvider>` built via `tool(MobileActionsTools(…))`.
    // On iOS, ToolProvider = AnyObject and the real on-device runtime must be configured to
    // invoke `toolSet.dispatch(functionName:args:)` when the model emits a function-call token.
    // Route through LlmModelHelper — do NOT call inference directly.
    private var tools: [ToolProvider] { [toolSet] }

    // Backing Task metadata.
    private let _task: Task

    init() {
        // Use an indirect box so the closure can weakly capture `self` without
        // using `self` before all stored properties are initialized.
        final class Box { weak var task: MobileActionsTask? }
        let box = Box()

        toolSet = MobileActionsToolSet { action in
            box.task?.curActions.append(action)
        }

        _task = Task(
            id: BuiltInTaskId.LLM_MOBILE_ACTIONS,
            label: "Mobile Actions",
            category: Category.LLM,
            icon: .system("function"),
            description: "Perform various device actions through Function Gemma",
            shortDescription: "Leverage device mobile actions",
            docUrl: "https://github.com/google-ai-edge/LiteRT-LM/blob/main/kotlin/README.md",
            sourceCodeUrl: "https://github.com/google-ai-edge/gallery/blob/main/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/mobileactions",
            models: [],
            experimental: true,
            agentName: Str.chatAgentAgentName
        )
        box.task = self
    }

    var task: Task { _task }

    func initializeModelFn(model: Model, systemInstruction: Contents?, onDone: @escaping (String) -> Void) {
        curActions.removeAll()
        // NOTE: Pass tools so the runtime registers the function-calling specs.
        // StubLlmModelHelper ignores tools; the real backend will use them.
        if let helper = AppContainer.sharedLlmHelper {
            helper.initialize(
                model: model,
                taskId: BuiltInTaskId.LLM_MOBILE_ACTIONS,
                supportImage: false,
                supportAudio: false,
                systemInstruction: getMobileActionsSystemPrompt(),
                tools: tools,
                onDone: onDone
            )
        } else {
            onDone("LlmModelHelper not available")
        }
    }

    func cleanUpModelFn(model: Model, onDone: @escaping () -> Void) {
        curActions.removeAll()
        AppContainer.sharedLlmHelper?.cleanUp(model: model, onDone: onDone) ?? { onDone() }()
    }

    @MainActor func mainScreen(data: Any) -> AnyView {
        guard let customTaskData = data as? CustomTaskData else {
            return AnyView(EmptyView())
        }
        let taskRef = self
        let binding = Binding<[Action]>(
            get: { taskRef.curActions },
            set: { taskRef.curActions = $0 }
        )
        return AnyView(
            MobileActionsScreen(
                task: _task,
                modelManagerViewModel: customTaskData.modelManagerViewModel,
                bottomPadding: customTaskData.bottomPadding,
                setAppBarControlsDisabled: customTaskData.setAppBarControlsDisabled,
                curActions: binding,
                onProcessingStarted: { taskRef.curActions.removeAll() }
            )
        )
    }
}

// MARK: - AppContainer shared helper extension
// NOTE: AppContainer holds the canonical LlmModelHelper and DataStoreRepository
// singletons. Tasks reach them through these static properties, which are set by
// AppContainer.init() (analogous to Hilt's SingletonComponent scope on Android).
extension AppContainer {
    nonisolated(unsafe) static weak var sharedLlmHelper: LlmModelHelper?
    nonisolated(unsafe) static weak var sharedDataStore: DataStoreRepository?
}
