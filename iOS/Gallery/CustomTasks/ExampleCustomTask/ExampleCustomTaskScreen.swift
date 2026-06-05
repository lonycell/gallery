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

// Port of customtasks/examplecustomtask/ExampleCustomTaskScreen.kt

import SwiftUI

// MARK: - Model instance

/// Holds the text content read from the model file.
/// Mirrors `ExampleCustomTaskModelInstance`.
struct ExampleCustomTaskModelInstance {
    let content: String
}

// MARK: - Config keys

let EXAMPLE_CUSTOM_TASK_CONFIG_KEY_FONT_SIZE = ConfigKey(id: "font_size", label: "Font size")
let EXAMPLE_CUSTOM_TASK_CONFIG_KEY_MAX_CHAR_COUNT = ConfigKey(id: "max_char_count", label: "Max character count")

// MARK: - Configs

/// Configuration list for the example custom task models.
/// Mirrors `EXAMPLE_CUSTOM_TASK_CONFIGS`.
let EXAMPLE_CUSTOM_TASK_CONFIGS: [Config] = [
    NumberSliderConfig(
        key: EXAMPLE_CUSTOM_TASK_CONFIG_KEY_FONT_SIZE,
        sliderMin: 8, sliderMax: 24, defaultValue: 14,
        valueType: .int, needReinitialization: false
    ),
    NumberSliderConfig(
        key: EXAMPLE_CUSTOM_TASK_CONFIG_KEY_MAX_CHAR_COUNT,
        sliderMin: 100, sliderMax: 2000, defaultValue: 2000,
        valueType: .int, needReinitialization: true
    ),
]

// MARK: - Screen

/// Main screen for the example custom task. Mirrors `ExampleCustomTaskScreen`.
struct ExampleCustomTaskScreen: View {
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    @StateObject private var viewModel = ExampleCustomTaskViewModel()

    @Environment(\.galleryColors) private var colors

    private let colorOptions: [Color] = [.primary, .red, .green, .blue]

    var body: some View {
        let modelManagerState = modelManagerViewModel.uiState
        let model = modelManagerState.selectedModel

        Group {
            if modelManagerState.isModelInitialized(model),
               let instance = model.instance as? ExampleCustomTaskModelInstance {
                // Derive font size from model config. Reacts to configValuesUpdateTrigger.
                let fontSize: CGFloat = {
                    let val = model.configValues[EXAMPLE_CUSTOM_TASK_CONFIG_KEY_FONT_SIZE.label]
                    return CGFloat(convertValueToTargetType(value: val ?? 14, valueType: .int) as? Int ?? 14)
                }()

                VStack(alignment: .leading, spacing: 0) {
                    // Color picker row.
                    HStack(spacing: 8) {
                        Text("Text color: ")
                            .font(AppTypography.bodyMedium)
                        ForEach(colorOptions, id: \.self) { color in
                            ZStack {
                                Circle()
                                    .fill(color)
                                    .frame(width: 16, height: 16)
                                if color == viewModel.uiState.textColor {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(colors.onPrimary)
                                }
                            }
                            .onTapGesture { viewModel.updateTextColor(color: color) }
                        }
                    }
                    .padding(16)

                    Divider()

                    // Content.
                    ScrollView {
                        Text(instance.content)
                            .font(.system(size: fontSize))
                            .lineSpacing(fontSize * 0.3)
                            .foregroundColor(viewModel.uiState.textColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
                .onAppear {
                    viewModel.updateTextColor(color: colorOptions[0])
                }
            } else {
                // Loading spinner.
                ZStack {
                    colors.surface
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 24, height: 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(colors.surface)
    }
}
