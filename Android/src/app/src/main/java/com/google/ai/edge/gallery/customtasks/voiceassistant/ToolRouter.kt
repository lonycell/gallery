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

package com.google.ai.edge.gallery.customtasks.voiceassistant

/**
 * A tool/function call decided by a [ToolRouter] for a single user turn.
 *
 * @param name the tool/function name to invoke (e.g. "web_search").
 * @param args the call arguments as a name→value map.
 */
data class ToolCall(val name: String, val args: Map<String, String> = emptyMap())

/**
 * Decides which tools (if any) a user turn needs, independently of the conversational model.
 *
 * This is the seam for the planned "2-model" design (see docs/TOOL_ROUTER_PLAN.md): a small
 * function-calling specialist (e.g. FunctionGemma) decides tool calls, the app executes them, and a
 * general chat model phrases the reply. Phase 1 only introduces the seam — [NoopRouter] is the
 * default and changes nothing; a real [ToolRouter] is wired in a later phase.
 */
interface ToolRouter {
  /**
   * Returns the tool calls needed for [userText], or an empty list when no tool is needed.
   * [availableTools] is the set of tool names the router may choose from.
   */
  suspend fun route(userText: String, availableTools: List<String>): List<ToolCall>
}

/** The default router: never requests a tool, so the chat flow behaves exactly as before. */
object NoopRouter : ToolRouter {
  override suspend fun route(userText: String, availableTools: List<String>): List<ToolCall> =
    emptyList()
}

/**
 * Whether the model named [modelName] supports litert-lm function calling + constrained decoding.
 * Only a few model types ship the tool-calling vocabulary/template that constrained decoding needs;
 * enabling tools for others crashes the native runtime at conversation creation.
 *
 * Shared by (1) the chat-model gate in `VoiceAssistantTask` and (2) the "tool model" picker, which
 * may only offer models that can actually emit tool calls.
 *
 * Currently: Gemma family (incl. FunctionGemma) and Qwen3. NOT Qwen2/Qwen2.5, DeepSeek, Llama, Phi.
 */
fun modelSupportsFunctionCalling(modelName: String): Boolean {
  val n = modelName.lowercase()
  return n.contains("gemma") || n.contains("qwen3")
}
