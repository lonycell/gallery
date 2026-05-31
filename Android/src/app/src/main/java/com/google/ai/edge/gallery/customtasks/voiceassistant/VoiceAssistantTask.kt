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
import com.google.ai.edge.gallery.customtasks.common.CustomTask
import com.google.ai.edge.gallery.customtasks.common.CustomTaskData
import com.google.ai.edge.gallery.customtasks.speech.SpeechCategory
import com.google.ai.edge.gallery.customtasks.voiceassistant.prompts.VoiceAssistantPromptSource
import com.google.ai.edge.gallery.data.Model
import com.google.ai.edge.gallery.data.Task
import com.google.ai.edge.gallery.ui.llmchat.LlmChatModelHelper
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
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
) : CustomTask {

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
      val instruction: Contents? =
        prompt?.let { Contents.of(listOf(Content.Text(it.systemPrompt))) }

      LlmChatModelHelper.initialize(
        context = context,
        model = model,
        taskId = task.id,
        supportImage = false,
        supportAudio = false,
        onDone = onDone,
        systemInstruction = instruction,
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
    )
  }
}
