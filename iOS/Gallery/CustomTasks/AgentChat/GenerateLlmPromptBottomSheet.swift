// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/GenerateLlmPromptBottomSheet.kt

import SwiftUI

private let PROMPT_TEMPLATE = """
# Task: Custom HTML/JS Implementation
Generate a single, self-contained HTML file that implements a specific feature or logic as described below.

## 1. Requirement
The implementation must fulfill the following:
> ___requirement___

## 2. Technical Specifications
* **Structure:** A complete, valid HTML5 document.
* **Head (Dependencies):** If third-party JS libraries (e.g., Three.js, D3, Lodash, GSAP) are required, include them via CDN using `<script src="..." defer>` tags inside the `<head>`. Do not put implementation logic here.
* **Body (Implementation):** Place the actual logic implementation inside a single `<script>` tag at the very end of the `<body>`.
* **Global Interface:** Within the body script, you must expose an `async` function to the global `window` object named: `window['ai_edge_gallery_get_result']`.

## 3. Data Interface & Serialization
* **Parameter 1 (`data`):** A **JSON-stringified string**.
    * Once parsed, the input object follows this schema: `___input_data_schema___`
* **Parameter 2 (`secret`):** A **string** representing a sensitive token or API key (e.g., Bearer token, private key). The implementation should use this if the requirement involves authenticated API calls or encrypted operations.
* **Output (return value):** The function must return a **JSON-stringified string** with the following exact structure:
    ```json
    {
      "result": "___output_data_schema___",
      "image": { "base64": "data:image/png;base64,..." },
      "error": "Error message string or null"
    }
    ```
    **CRITICAL RULES:**
    1. **Dual Output:** The `"result"` and `"image"` fields can and should coexist in the same response if the requirement involves returning both data/text and a visual asset.
    2. **Result Serialization:** The value for `"result"` must be a JSON-stringified representation of the output data. Set to `null` only if no data is produced.
    3. **Image Serialization:** The `"image.base64"` field must contain a full Data URI. Set the entire `"image"` object to `null` only if no image is produced.

## 4. Error Handling
* Wrap the entire function logic in a `try/catch` block.
* If an error occurs, the function should return a JSON string where `result` is `null` and `error` contains the error message.

## 5. Response Constraints
* Return the **raw HTML code only**.
* Do not provide any introductory text, markdown backticks, or concluding remarks.
* Start the response immediately with `<!DOCTYPE html>`.
* Put the output code into a Markdown code block so I can easily copy.
"""

struct GenerateLlmPromptBottomSheet: View {
    let curDescription: String
    @Binding var requirements: String
    @Binding var inputData: String
    @Binding var outputData: String
    let onDismiss: () -> Void
    let onGenerated: (String) -> Void

    @Environment(\.galleryColors) var colors

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(Str.generateLlmPromptTitle).font(AppTypography.titleLarge).padding(.horizontal, 16).padding(.top, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        LabeledTextField(label: Str.describeRequirements, text: $requirements, minLines: 3)
                        LabeledTextField(label: Str.describeInputData, text: $inputData, minLines: 7,
                                         supportText: Str.describeInputDataSupportText)
                        LabeledTextField(label: Str.describeOutputData, text: $outputData, minLines: 5)
                    }
                    .padding(16)
                }

                HStack {
                    Spacer()
                    Button(Str.generateAndCopy) {
                        let prompt = PROMPT_TEMPLATE
                            .replacingOccurrences(of: "___requirement___", with: requirements)
                            .replacingOccurrences(of: "___input_data_schema___", with: inputData)
                            .replacingOccurrences(of: "___output_data_schema___", with: outputData)
                        UIPasteboard.general.string = prompt
                        onGenerated(prompt)
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if requirements.trimmingCharacters(in: .whitespaces).isEmpty {
                requirements = curDescription
            }
        }
    }
}

private struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    let minLines: Int
    var supportText: String? = nil
    @Environment(\.galleryColors) var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(AppTypography.labelMedium)
            TextField("", text: $text, axis: .vertical).textFieldStyle(.roundedBorder)
                .lineLimit(minLines...20)
            if let s = supportText {
                Text(s).font(AppTypography.bodySmall).foregroundColor(colors.onSurfaceVariant)
            }
        }
    }
}

private extension Str {
    static let generateLlmPromptTitle = "Generate LLM Prompt"
    static let describeRequirements = "Describe requirements"
    static let describeInputData = "Describe input data"
    static let describeInputDataSupportText = "Describe the fields the JS function receives as input."
    static let describeOutputData = "Describe output data"
    static let generateAndCopy = "Generate and copy"
}
