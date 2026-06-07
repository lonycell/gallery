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

import com.google.ai.edge.gallery.customtasks.agentchat.AgentTools
import com.google.ai.edge.gallery.customtasks.kakao.KakaoShareTools
import com.google.ai.edge.gallery.customtasks.websearch.WebSearchTools
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Executes a [ToolCall] decided by a [ToolRouter] (the "expose-only" path), by invoking the real tool
 * implementations directly — *not* through the litert engine's auto-execution. Returns a short result
 * string to feed back into the conversational model.
 *
 * This is the app side of the 2-model design (docs/TOOL_ROUTER_PLAN.md): the tool model only *names*
 * the call; we run it here and hand the result to the chat model to phrase in character.
 */
class ToolExecutor(
  private val webSearch: WebSearchTools,
  private val kakao: KakaoShareTools,
  private val agentTools: AgentTools? = null,
) {
  /** Runs [call] off the main thread and returns a compact, human/LLM-readable result string. */
  suspend fun execute(call: ToolCall): String =
    withContext(Dispatchers.IO) {
      try {
        val result: Map<String, *> =
          when (call.name) {
            "web_search" -> webSearch.searchWeb(call.args["query"].orEmpty())
            "kakao_share" ->
              kakao.sendKakaoMessage(
                call.args["recipient"].orEmpty(),
                call.args["message"].orEmpty(),
              )
            "mcp_tool" ->
              agentTools?.runMcpTool(call.args["toolName"].orEmpty(), call.args["input"].orEmpty())
                ?: mapOf("error" to "도구를 사용할 수 없습니다.")
            else -> mapOf("error" to "알 수 없는 도구: ${call.name}")
          }
        // Prefer the meaningful field; fall back to the whole map.
        (result["results"]
            ?: result["result"]
            ?: result["note"]
            ?: result["error"]
            ?: result.toString())
          .toString()
      } catch (e: Throwable) {
        "도구 실행에 실패했어요: ${e.message}"
      }
    }
}
