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

// Port of customtasks/exampleagent/ExampleAgentTools.kt
//
// TEMPLATE: a set of local function-calling tools.
//
// NOTE: Android used @Tool / @ToolParam / ToolSet annotations from litertlm for
// reflection-based registration. iOS represents tools as JSON function-spec
// dictionaries. The class below mirrors the same three tool functions and
// exposes the JSON specs consumed by ExampleAgentTask for LlmModelHelper.

import Foundation

/// TEMPLATE: local tool set for the ExampleAgent.
/// Mirrors `ExampleAgentTools`.
///
/// Guidelines (same as Android):
/// - Keep tools fast and side-effect-light.
/// - Validate inputs; return a structured error instead of throwing.
/// - Use `onToolCalled` to surface activity to the UI.
final class ExampleAgentTools {
    private let onToolCalled: (String) -> Void

    init(onToolCalled: @escaping (String) -> Void = { _ in }) {
        self.onToolCalled = onToolCalled
    }

    // MARK: - Tool functions

    /// Returns the current local date and time.
    func getCurrentDateTime() -> [String: String] {
        onToolCalled("Reading the current time")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let formatted = formatter.string(from: Date())
        return ["result": formatted, "status": "succeeded"]
    }

    /// Performs a basic arithmetic operation on two numbers.
    func calculate(operation: String, a: Double, b: Double) -> [String: Any] {
        onToolCalled("Calculating \(a) \(operation) \(b)")
        let result: Double
        switch operation.trimmingCharacters(in: .whitespaces).lowercased() {
        case "add", "+":      result = a + b
        case "subtract", "-": result = a - b
        case "multiply", "*": result = a * b
        case "divide", "/":
            guard b != 0 else {
                return ["error": "Cannot divide by zero", "status": "failed"]
            }
            result = a / b
        default:
            return ["error": "Unknown operation: \"\(operation)\"", "status": "failed"]
        }
        return ["result": result, "status": "succeeded"]
    }

    /// Counts the number of words in the given text.
    func countWords(text: String) -> [String: Any] {
        onToolCalled("Counting words")
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
        return ["result": count, "status": "succeeded"]
    }

    // MARK: - JSON function specs
    //
    // NOTE: These mirror @Tool + @ToolParam annotations. The LlmModelHelper stub
    // ignores them; a real MediaPipe/LiteRT bridge would use them to build the
    // function-calling context for the model.

    static var functionSpecs: [[String: Any]] {
        [
            [
                "name": "getCurrentDateTime",
                "description": "Returns the current local date and time.",
                "parameters": ["type": "object", "properties": [:], "required": []],
            ],
            [
                "name": "calculate",
                "description": "Performs a basic arithmetic operation on two numbers and returns the result. Supported operations: add, subtract, multiply, divide.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "operation": ["type": "string",
                                      "description": "The operation: one of add, subtract, multiply, divide."],
                        "a": ["type": "number", "description": "The first operand."],
                        "b": ["type": "number", "description": "The second operand."],
                    ],
                    "required": ["operation", "a", "b"],
                ],
            ],
            [
                "name": "countWords",
                "description": "Counts the number of words in the given text.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string",
                                 "description": "The text whose words should be counted."],
                    ],
                    "required": ["text"],
                ],
            ],
        ]
    }

    // MARK: - Dispatch

    func dispatch(functionName: String, args: [String: Any]) -> String {
        var result: [String: Any]
        switch functionName {
        case "getCurrentDateTime":
            result = getCurrentDateTime()
        case "calculate":
            result = calculate(
                operation: args["operation"] as? String ?? "",
                a: args["a"] as? Double ?? 0,
                b: args["b"] as? Double ?? 0
            )
        case "countWords":
            result = countWords(text: args["text"] as? String ?? "")
        default:
            result = ["error": "Unknown function", "status": "failed"]
        }
        let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
