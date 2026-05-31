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
package com.google.ai.edge.gallery.customtasks.exampleagent

import android.util.Log
import com.google.ai.edge.litertlm.Tool
import com.google.ai.edge.litertlm.ToolParam
import com.google.ai.edge.litertlm.ToolSet
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

private const val TAG = "AGExampleAgentTools"

/**
 * TEMPLATE: a set of local function-calling tools.
 *
 * This is the simplest way to give an on-device LLM new abilities: expose plain Kotlin functions
 * annotated with [@Tool][Tool]. When the model decides a function is needed, the LiteRT-LM runtime
 * calls it for you and feeds the returned value back into the conversation.
 *
 * How it works:
 * - The class implements [ToolSet].
 * - Each callable function is annotated with `@Tool(description = ...)`. The description is what the
 *   model reads to decide *when* to call it — keep it clear and specific.
 * - Each parameter is annotated with `@ToolParam(description = ...)`. Use simple types
 *   (String, Int, Double, Boolean).
 * - The function returns a `Map<String, ...>` (or any serializable value). The map is sent back to
 *   the model as the tool result; include a `result`/`error` + `status` so the model can reason
 *   about success/failure.
 * - Wrap an instance with `com.google.ai.edge.litertlm.tool(...)` and pass it to
 *   `LlmChatModelHelper.initialize(tools = listOf(tool(ExampleAgentTools(...))), ...)`.
 *
 * Guidelines:
 * - Keep tools fast and side-effect-light, or do heavy work off the calling thread. Tool functions
 *   are invoked by the runtime synchronously during generation.
 * - Validate inputs and return a structured error instead of throwing.
 * - Use the [onToolCalled] callback to surface activity to your UI (progress, undo, analytics).
 *
 * To add your own tool: copy one of the functions below, rename it, write a precise description, and
 * implement the body. That's it — the model can now call it.
 *
 * @param onToolCalled Optional callback invoked whenever a tool runs, with a short human-readable
 *   label. Use it to drive a "tool activity" indicator in your UI.
 */
class ExampleAgentTools(private val onToolCalled: (label: String) -> Unit = {}) : ToolSet {

  /** A no-argument tool. */
  @Tool(description = "Returns the current local date and time.")
  fun getCurrentDateTime(): Map<String, String> {
    onToolCalled("Reading the current time")
    @Suppress("JavaTimeDefaultTimeZone") val now = LocalDateTime.now()
    val formatted = now.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"))
    Log.d(TAG, "getCurrentDateTime -> $formatted")
    return mapOf("result" to formatted, "status" to "succeeded")
  }

  /** A tool with typed parameters that returns a computed value (and a structured error). */
  @Tool(
    description =
      "Performs a basic arithmetic operation on two numbers and returns the result. " +
        "Supported operations: add, subtract, multiply, divide."
  )
  fun calculate(
    @ToolParam(description = "The operation: one of add, subtract, multiply, divide.")
    operation: String,
    @ToolParam(description = "The first operand.") a: Double,
    @ToolParam(description = "The second operand.") b: Double,
  ): Map<String, Any> {
    onToolCalled("Calculating $a $operation $b")
    val result =
      when (operation.trim().lowercase()) {
        "add",
        "+" -> a + b
        "subtract",
        "-" -> a - b
        "multiply",
        "*" -> a * b
        "divide",
        "/" -> {
          if (b == 0.0) {
            return mapOf("error" to "Cannot divide by zero", "status" to "failed")
          }
          a / b
        }
        else ->
          return mapOf(
            "error" to "Unknown operation: \"$operation\"",
            "status" to "failed",
          )
      }
    Log.d(TAG, "calculate($operation, $a, $b) -> $result")
    return mapOf("result" to result, "status" to "succeeded")
  }

  /**
   * A tool that does real work but stays self-contained for the template. Replace the body with a
   * call into your repository / Android API / network client as needed.
   */
  @Tool(description = "Counts the number of words in the given text.")
  fun countWords(
    @ToolParam(description = "The text whose words should be counted.") text: String
  ): Map<String, Any> {
    onToolCalled("Counting words")
    val count = text.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.size
    return mapOf("result" to count, "status" to "succeeded")
  }
}
