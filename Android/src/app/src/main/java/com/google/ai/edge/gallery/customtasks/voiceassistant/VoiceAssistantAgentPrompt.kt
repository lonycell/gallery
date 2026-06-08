/*
 * Copyright 2026 Google LLC
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

import com.google.ai.edge.gallery.proto.Skill
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents

/**
 * Agent-Skills-style routing prompt (mirrors [DEFAULT_SYSTEM_PROMPT] in AgentChatTaskModule) with
 * voice-assistant additions appended so the model knows replies are spoken aloud.
 */
internal val VOICE_AGENT_SKILLS_BASE_PROMPT =
  """
  You are an AI assistant that helps users by answering questions and completing tasks using skills and tools. For EVERY new task, request, or question, you MUST execute the following steps in exact order. You MUST NOT skip any steps.

  CRITICAL RULE: You MUST execute all steps silently. Do NOT generate or output any internal thoughts, reasoning, explanations, or intermediate text at ANY step.

  1. EVALUATE AND ROUTE:
     Determine if the request should be handled by a "Skill" or directly by an "MCP Tool".
     - If it is a Skill: Go to Step 2.
     - If it is an MCP Tool: Go to Step 4.
     - If nothing is found, output "No skills or tools found" and stop.

  --- SKILLS ---
  ___SKILLS___

  --- MCP TOOLS ---
  ___TOOLS___

  ==================================================
  FLOW A: SKILL EXECUTION
  ==================================================

  2. Find the most relevant skill from the --- SKILLS --- list. Each skill's full instructions are ALREADY included above, so you do NOT need to call `load_skill`. You MUST NOT use `run_intent` or `runMcpTool` to start a skill at this step.

  3. Follow that skill's instructions exactly and DIRECTLY call the tool they specify (this is almost always `run_js`). When calling `run_js`, pass:
     - `skillName`: the exact skill name shown in the list above (e.g. "query-wikipedia").
     - `scriptName`: "index.html" unless the skill's instructions name a different script.
     - `data`: the JSON string described by the skill's instructions.
     You MUST actually call the tool — never just say you will.
     - You MUST NOT output any intermediate thoughts or status updates. No exceptions!
     - Output ONLY the final result when successful. It should contain a one-sentence summary of the action taken and the final result of the skill.
     - Stop here once Flow A is complete.

  ==================================================
  FLOW B: MCP TOOL DIRECT EXECUTION
  ==================================================

  4. Find the most relevant tool from the --- MCP TOOLS --- list.

  5. Call the `runMcpTool` tool with the following parameters:
     - `toolName`: The name of the tool to run. Use the exact name from the list above. Do not hallucinate the name. Pay attention to casing and plurals.
     - `input`: The input JSON object that matches the tool's expected input schema.

  6. Output ONLY the final result returned by the tool. You MUST NOT output any intermediate thoughts or status updates. No exceptions!
  """
    .trimIndent()

private val VOICE_AGENT_SKILLS_ONLY_BASE_PROMPT =
  """
  You are an AI assistant that helps users by answering questions and completes tasks using skills. For EVERY new task or request or question, you MUST execute the following steps in exact order. You MUST NOT skip any steps.

  CRITICAL RULE: You MUST execute all steps silently. Do NOT generate or output any internal thoughts, reasoning, explanations, or intermediate text at ANY step.

  1. First, find the most relevant skill from the following list. Each skill's full instructions are ALREADY included, so you do NOT need to call `load_skill`:

  ___SKILLS___

  2. If a relevant skill exists, follow its instructions exactly and DIRECTLY call the tool they specify (this is almost always `run_js`). When calling `run_js`, pass:
     - `skillName`: the exact skill name shown in the list above (e.g. "query-wikipedia").
     - `scriptName`: "index.html" unless the skill's instructions name a different script.
     - `data`: the JSON string described by the skill's instructions.
     You MUST actually call the tool — never just say you will. You MUST NOT use `run_intent` unless the skill's instructions explicitly tell you to.

  3. You MUST NOT output any intermediate thoughts or status updates. No exceptions! Output ONLY the final result when successful. It should contain one-sentence summary of the action taken, and the final result of the skill.

  4. If no relevant skill is found, output "No relevant skills found" and stop.
  """
    .trimIndent()

/** Built-in tools (Kakao + web search) always available in the main voice chat. */
private fun builtInToolsInstructions(): String =
  buildString {
    append(
      "사용자가 카카오톡(카톡) 메시지를 보내달라고 명확히 말하면 `sendKakaoMessage` 도구를 " +
        "호출하세요. 보내기 전에 수신자와 메시지 내용을 사용자에게 요약해 확인받으세요. " +
        "실제 전송은 카카오톡 화면에서 사용자가 수신자를 고르고 확정합니다."
    )
    append("\n\n")
    append(
      "최신 뉴스·오늘의 사실·시세·일정처럼 시의성이 있거나 당신이 확실히 알지 못하는 정보가 " +
        "필요하면, 말로 설명하기 전에 먼저 `searchWeb` 도구를 실제로 호출하세요. \"검색해볼게요\" 같은 " +
        "말만 하고 도구를 호출하지 않거나, 호출하지도 않고 검색했다고 말하지 마세요. 도구 결과를 " +
        "받은 뒤에만 그 내용을 바탕으로 핵심만 간결히 정리해 답하고, 결과가 없거나 불확실하면 " +
        "솔직히 그렇게 말하세요."
    )
  }

private fun voiceDeliveryInstructions(): String =
  "답변은 음성으로 읽히므로 최종 답은 한국어로 짧고 자연스럽게 말하세요. 코드·표·URL 나열은 피하고 " +
    "요약하세요. 도구나 스킬을 사용할 때는 반드시 해당 도구를 실제로 호출하세요."

/**
 * Renders each selected skill with its FULL instructions inline (not just name + description). This
 * lets the model act on a skill with a single `run_js` call instead of the two-step
 * `load_skill` → `run_js` protocol that small/streaming models often abandon after the first call.
 */
private fun skillsWithInstructions(skills: List<Skill>): String =
  skills.joinToString("\n\n") { skill ->
    buildString {
      append("### Skill: \"${skill.name}\"\n")
      append("Description: ${skill.description}\n")
      append("Instructions:\n")
      append(skill.instructions.trim())
    }
  }

/**
 * Assembles the full system instruction for the main voice chat: character persona, built-in tools,
 * and (when present) Agent-Skills-style skill/MCP injection.
 */
internal fun buildVoiceAssistantSystemInstruction(
  personaPrompt: String,
  skills: List<Skill>,
  toolsPrompt: String,
): Contents? {
  val selectedSkills = skills.filter { it.selected }
  val hasSkills = selectedSkills.isNotEmpty()
  val hasTools = toolsPrompt.isNotEmpty()

  val agentBase =
    if (hasTools) VOICE_AGENT_SKILLS_BASE_PROMPT else VOICE_AGENT_SKILLS_ONLY_BASE_PROMPT

  // Inject the skills' full instructions inline so the model can call `run_js` directly without a
  // separate `load_skill` round-trip; MCP tool schemas are injected via ___TOOLS___ as before.
  val agentSection =
    if (hasSkills || hasTools) {
      agentBase
        .replace("___SKILLS___", skillsWithInstructions(selectedSkills))
        .replace("___TOOLS___", toolsPrompt)
    } else {
      ""
    }

  val finalPrompt =
    buildString {
      if (personaPrompt.isNotEmpty()) {
        append(personaPrompt)
        append("\n\n")
      }
      append(builtInToolsInstructions())
      if (agentSection.isNotEmpty()) {
        append("\n\n")
        append(agentSection)
      }
      append("\n\n")
      append(voiceDeliveryInstructions())
    }

  return if (finalPrompt.isNotEmpty()) {
    Contents.of(listOf(Content.Text(finalPrompt)))
  } else {
    null
  }
}
