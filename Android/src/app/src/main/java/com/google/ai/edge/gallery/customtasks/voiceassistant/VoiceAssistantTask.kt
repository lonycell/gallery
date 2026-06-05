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

import android.content.Context
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.GraphicEq
import androidx.compose.runtime.Composable
import com.google.ai.edge.gallery.customtasks.agentchat.AgentTools
import com.google.ai.edge.gallery.customtasks.common.CustomTask
import com.google.ai.edge.gallery.customtasks.voiceassistant.buildVoiceAssistantSystemInstruction
import com.google.ai.edge.gallery.customtasks.common.CustomTaskData
import com.google.ai.edge.gallery.customtasks.kakao.KakaoShareTools
import com.google.ai.edge.gallery.customtasks.websearch.WebSearchTools
import com.google.ai.edge.gallery.customtasks.speech.SpeechCategory
import com.google.ai.edge.gallery.customtasks.voiceassistant.prompts.VoiceAssistantPromptSource
import com.google.ai.edge.gallery.data.Model
import com.google.ai.edge.gallery.data.Task
import com.google.ai.edge.gallery.ui.llmchat.LlmChatModelHelper
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.ToolProvider
import com.google.ai.edge.litertlm.tool
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * The task id of the Voice Assistant. Exposed so the model manager can share the same downloadable
 * LLMs (the ones offered for chat) with this task.
 */
const val VOICE_ASSISTANT_TASK_ID = "speech_voice_assistant"

/**
 * A custom task that hosts a futuristic, hands-free Voice Assistant.
 *
 * The user speaks (Android [android.speech.SpeechRecognizer] or the optional neural recognizer),
 * the on-device LLM replies through [LlmChatModelHelper], the reply is shown on screen as it streams
 * in, and it is simultaneously read aloud (Android [android.speech.tts.TextToSpeech] or the optional
 * neural voice).
 *
 * The Voice Assistant does not ship its own model. Instead, it shares the same downloadable chat
 * LLMs from the app's allowlist (Gemma 3, Gemma 4, Qwen, …): the model manager adds every LLM that
 * is offered for `llm_chat` to this task too, so users can download and switch between them with the
 * standard model selector. See `ModelManagerViewModel.loadModelAllowlist`.
 *
 * An optional entry topic/problem (see [VoiceAssistantEntryParams]) selects an appropriate system
 * prompt from the [VoiceAssistantPromptSource]; with no topic, a general assistant prompt is used.
 */
class VoiceAssistantTask(
  private val promptSource: VoiceAssistantPromptSource,
  private val entryParams: VoiceAssistantEntryParams,
  private val characterRepository: com.google.ai.edge.gallery.character.CharacterRepository,
  private val chatHistoryStore: ChatHistoryStore,
) : CustomTask {

  // Shared tool/skill/MCP surface (same implementation Agent Skills uses). Its lateinit view models
  // (skill/MCP managers, context, taskId) are assigned by VoiceAssistantScreen before init runs.
  val agentTools = AgentTools()

  override val task: Task =
    Task(
      id = VOICE_ASSISTANT_TASK_ID,
      label = "음성 어시스턴트",
      category = SpeechCategory,
      icon = Icons.Outlined.GraphicEq,
      description =
        "온디바이스 AI와 손을 쓰지 않고 음성으로 대화하세요. 자연스럽게 말하면 답변이 실시간으로 " +
          "화면에 나타나고 동시에 음성으로 읽어줍니다. 특정 **주제나 문제**에 집중한 상태로 들어올 " +
          "수도 있으며, 이 경우 어시스턴트가 그 주제에 맞는 지시문을 불러와 대화를 이끕니다. 기본 " +
          "언어는 한국어입니다.",
      shortDescription = "음성으로 AI와 대화",
      sourceCodeUrl =
        "https://github.com/google-ai-edge/gallery/blob/main/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/voiceassistant",
      newFeature = true,
      // Populated by the model manager with the same LLMs offered for chat.
      models = mutableListOf(),
    )

  override fun initializeModelFn(
    context: Context,
    coroutineScope: CoroutineScope,
    model: Model,
    systemInstruction: Contents?,
    onDone: (error: String) -> Unit,
  ) {
    coroutineScope.launch(Dispatchers.IO) {
      // Resolve the entry topic (if any) into a system prompt. We don't consume the topic here so
      // the screen/ViewModel can also read it to show the topic title and starter chips.
      val topic = entryParams.topic.value
      val prompt =
        try {
          promptSource.getPromptForTopic(topic)
        } catch (e: Exception) {
          null
        }
      val basePrompt = prompt?.systemPrompt ?: ""

      // Load skills + MCP servers (the screen assigns agentTools' view models before this runs;
      // guard in case it hasn't). When either skills are selected or MCP tools are connected, we
      // advertise them in the system prompt and enable function calling.
      val toolsPrompt =
        try {
          agentTools.mcpManagerViewModel.loadMcpServers()
          agentTools.mcpManagerViewModel.getToolsPrompt()
        } catch (e: Exception) {
          ""
        }
      val selectedSkills =
        try {
          agentTools.skillManagerViewModel.loadSkills()
          agentTools.skillManagerViewModel.getSelectedSkills()
        } catch (e: Exception) {
          emptyList()
        }
      val hasTools = toolsPrompt.isNotEmpty()
      val hasSkills = selectedSkills.any { it.selected }

      // Agent-Skills-style system prompt injection (routing + skill/MCP lists), layered on the
      // character persona and built-in Kakao/web-search tools.
      val instruction: Contents? =
        buildVoiceAssistantSystemInstruction(
          personaPrompt = basePrompt,
          skills = selectedSkills,
          toolsPrompt = toolsPrompt,
        )

      // The KakaoTalk share tool is always offered; skills/MCP are added only when present. Function
      // calling is therefore always enabled.
      val toolSets = mutableListOf<ToolProvider>()
      toolSets.add(tool(KakaoShareTools(context = context.applicationContext)))
      // Built-in internet search is always available; it reports progress via the shared agentTools.
      toolSets.add(tool(WebSearchTools(agentTools = agentTools)))
      if (hasTools || hasSkills) {
        toolSets.add(tool(agentTools))
      }

      // Restore this character's prior conversation into the LLM context so it "remembers" the chat
      // (the screen restores the on-screen messages from the same store). Newest messages last.
      val history =
        chatHistoryStore.load(characterRepository.selectedCharacter().id).mapNotNull { message ->
          when (message.role) {
            ChatMessage.Role.USER -> Message.user(message.text)
            ChatMessage.Role.ASSISTANT -> Message.model(message.text)
          }
        }

      LlmChatModelHelper.initialize(
        context = context,
        model = model,
        taskId = task.id,
        supportImage = false,
        supportAudio = false,
        onDone = onDone,
        systemInstruction = instruction,
        tools = toolSets,
        enableConversationConstrainedDecoding = true,
        // Seed this character's prior conversation directly at creation, so the model "remembers"
        // the chat without a second resetConversation pass (which would rebuild the vocab FST and
        // visibly slow down entering the chat).
        initialMessages = history,
      )
    }
  }

  override fun cleanUpModelFn(
    context: Context,
    coroutineScope: CoroutineScope,
    model: Model,
    onDone: () -> Unit,
  ) {
    LlmChatModelHelper.cleanUp(model = model, onDone = onDone)
  }

  @Composable
  override fun MainScreen(data: Any) {
    val customTaskData = data as CustomTaskData
    VoiceAssistantScreen(
      task = task,
      modelManagerViewModel = customTaskData.modelManagerViewModel,
      agentTools = agentTools,
    )
  }
}
