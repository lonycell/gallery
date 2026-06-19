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

// Port of customtasks/examplecustomtask/ExampleCustomTask.kt
//
// An example CustomTask that demonstrates how to display the content of a
// text-based model file. Mirrors the Android class closely.

import Foundation
import SwiftUI

/// Example CustomTask. Mirrors `ExampleCustomTask`.
final class ExampleCustomTask: CustomTask {

    private let _task: Task

    init() {
        _task = Task(
            id: "example_custom_task",
            label: "Model Viewer",
            category: CategoryInfo(id: "example", label: "Example"),
            icon: .system("textformat"),
            description: "This example task demonstrates a custom task that reads and displays the content of a model file (with text content for demonstration purpose). The \"models\" listed below are configured in different ways in terms of how the model file is provided (pushed to device manually, vs downloaded from internet).",
            docUrl: "https://github.com/google-ai-edge/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/common/CustomTask.kt",
            sourceCodeUrl: "https://github.com/google-ai-edge/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/examplecustomtask/ExampleCustomTask.kt",
            models: [
                Model(
                    name: "Local model",
                    info: "Expects to read the model file `model.txt` manually pushed to `{documents}/example_task/`.",
                    configs: EXAMPLE_CUSTOM_TASK_CONFIGS,
                    bestForTaskIds: ["example_custom_task"],
                    // NOTE: On Android `localFileRelativeDirPathOverride = "example_task/"` resolved
                    // to the external files directory. On iOS we use the Documents directory.
                    localFileRelativeDirPathOverride: "example_task/"
                ),
                Model(
                    name: "Remote model",
                    info: "Downloads the model file (a README.md file for demonstration purpose) from internet.",
                    configs: EXAMPLE_CUSTOM_TASK_CONFIGS,
                    url: "https://raw.githubusercontent.com/google-ai-edge/gallery/refs/heads/main/README.md",
                    sizeInBytes: 3798,
                    downloadFileName: "README.md"
                ),
            ]
        )
    }

    var task: Task { _task }

    func initializeModelFn(model: Model, systemInstruction: Contents?, onDone: @escaping (String) -> Void) {
        model.instance = nil
        _Concurrency.Task.detached {
            do {
                // Resolve file path.
                // NOTE: On Android `model.getPath(context)` returned a path under the
                // external files dir or the download dir. On iOS we use the Documents
                // directory for manual pushes and the app's downloads folder otherwise.
                let filePath: URL
                if model.localFileRelativeDirPathOverride.isEmpty {
                    // Remote model — downloaded to app's documents/downloads area.
                    let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    filePath = docsDir.appendingPathComponent(model.downloadFileName)
                } else {
                    // Local model — look for model.txt in Documents/<localFileRelativeDirPathOverride>.
                    let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let overrideDir = docsDir.appendingPathComponent(model.localFileRelativeDirPathOverride)
                    filePath = overrideDir.appendingPathComponent("model.txt")
                }

                var content = try String(contentsOf: filePath, encoding: .utf8)

                // Cap at maxCharCount from config.
                let maxCharCount = model.getIntConfigValue(key: EXAMPLE_CUSTOM_TASK_CONFIG_KEY_MAX_CHAR_COUNT)
                if maxCharCount > 0 {
                    content = String(content.prefix(maxCharCount))
                }

                model.instance = ExampleCustomTaskModelInstance(content: content)

                // Simulate initialization time.
                try await _Concurrency.Task<Never, Never>.sleep(nanoseconds: 1_500_000_000)

                await MainActor.run { onDone("") }
            } catch {
                await MainActor.run { onDone(error.localizedDescription) }
            }
        }
    }

    func cleanUpModelFn(model: Model, onDone: @escaping () -> Void) {
        // Release resources (trivially nil the instance for this example).
        model.instance = nil
        onDone()
    }

    @MainActor func mainScreen(data: Any) -> AnyView {
        guard let customTaskData = data as? CustomTaskData else {
            return AnyView(EmptyView())
        }
        return AnyView(
            ExampleCustomTaskScreen(modelManagerViewModel: customTaskData.modelManagerViewModel)
        )
    }
}

// MARK: - Model config helper
private extension Model {
    func getIntConfigValue(key: ConfigKey) -> Int {
        let val = configValues[key.label]
        return convertValueToTargetType(value: val ?? 0, valueType: .int) as? Int ?? 0
    }
}
