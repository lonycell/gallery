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

/** A tool the router may choose, described for the router prompt. */
data class ToolSpec(
  val name: String,
  val description: String,
  val params: List<String> = emptyList(),
)

/** The built-in tools the assistant can route to (expose-only; executed by [ToolExecutor]). */
fun defaultToolSpecs(): List<ToolSpec> =
  listOf(
    ToolSpec("web_search", "인터넷에서 최신 정보를 검색한다", listOf("query")),
    ToolSpec("kakao_share", "카카오톡으로 메시지를 공유한다", listOf("recipient", "message")),
  )

/** Builds the expose-only routing prompt: the tool model must reply with a single JSON object. */
fun buildRouterPrompt(userText: String, tools: List<ToolSpec>): String {
  val toolList =
    tools.joinToString("\n") { "- ${it.name}(${it.params.joinToString(", ")}): ${it.description}" }
  return """
    너는 도구 선택기다. 사용 가능한 도구:
    $toolList

    사용자 입력: "$userText"

    이 입력을 처리하는 데 도구가 필요하면 정확히 JSON 하나만 출력해라:
    {"tool":"<도구이름>","args":{"<인자>":"<값>"}}
    도구가 필요 없으면 정확히: {"tool":"none"}
    JSON 외에 다른 말은 절대 출력하지 마라.
  """
    .trimIndent()
}

/** Parses the tool model's text output into tool calls (tolerant of surrounding text). */
fun parseToolCalls(modelOutput: String): List<ToolCall> {
  val start = modelOutput.indexOf('{')
  val end = modelOutput.lastIndexOf('}')
  if (start < 0 || end <= start) return emptyList()
  return try {
    val obj = org.json.JSONObject(modelOutput.substring(start, end + 1))
    val tool = obj.optString("tool").trim()
    if (tool.isEmpty() || tool.equals("none", ignoreCase = true)) return emptyList()
    val argsObj = obj.optJSONObject("args")
    val args = mutableMapOf<String, String>()
    argsObj?.keys()?.forEach { key -> args[key] = argsObj.optString(key) }
    listOf(ToolCall(tool, args))
  } catch (e: Exception) {
    emptyList()
  }
}

/**
 * An expose-only router backed by a (small) tool LLM. [infer] runs one prompt on the tool model and
 * returns its full text output; this router builds the routing prompt, runs it, and parses the JSON
 * tool call. Works the same whether the tool model is FunctionGemma or a general Gemma — we never
 * use the runtime's auto-execution.
 */
class LlmToolRouter(
  private val tools: List<ToolSpec>,
  private val infer: suspend (prompt: String) -> String,
) : ToolRouter {
  override suspend fun route(userText: String, availableTools: List<String>): List<ToolCall> {
    val output =
      try {
        infer(buildRouterPrompt(userText, tools))
      } catch (e: Throwable) {
        return emptyList()
      }
    return parseToolCalls(output)
  }
}
