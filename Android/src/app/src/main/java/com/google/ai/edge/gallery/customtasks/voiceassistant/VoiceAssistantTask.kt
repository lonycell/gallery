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
import com.google.ai.edge.gallery.data.Accelerator
import com.google.ai.edge.gallery.data.Model
import com.google.ai.edge.gallery.data.RuntimeType
import com.google.ai.edge.gallery.data.Task
import com.google.ai.edge.gallery.data.createLlmChatConfigs
import com.google.ai.edge.gallery.ui.llmchat.LlmChatModelHelper
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

// The Voice Assistant runs on a small, general-purpose on-device LLM. We reuse the same model that
// ships in the app's allowlist ("Gemma3-1B-IT") so it downloads and initializes through the exact
// same LiteRT-LM path as the built-in chat tasks.
private const val VA_MODEL_NAME = "Gemma3-1B-IT"
private const val VA_MODEL_ID = "litert-community/Gemma3-1B-IT"
private const val VA_MODEL_FILE = "gemma3-1b-it-int4.litertlm"
private const val VA_MODEL_COMMIT = "42d538a932e8d5b12e6b3b455f5572560bd60b2c"
private const val VA_MODEL_SIZE_BYTES = 584417280L

/**
 * A custom task that hosts a futuristic, hands-free Voice Assistant.
 *
 * The user speaks (Android [android.speech.SpeechRecognizer]), the on-device LLM replies through
 * [LlmChatModelHelper], the reply is shown on screen as it streams in, and it is simultaneously
 * read aloud (Android [android.speech.tts.TextToSpeech]).
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
      id = "speech_voice_assistant",
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
      models = mutableListOf(buildVoiceAssistantModel()),
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

/**
 * Builds the [Model] for the Voice Assistant, mirroring how the app constructs LLM models from the
 * allowlist (HuggingFace resolve URL, LiteRT-LM runtime, standard LLM chat configs).
 */
private fun buildVoiceAssistantModel(): Model {
  val configs =
    createLlmChatConfigs(
      defaultMaxToken = 1024,
      defaultTopK = 64,
      defaultTopP = 0.95f,
      defaultTemperature = 1.0f,
      accelerators = listOf(Accelerator.GPU, Accelerator.CPU),
    )
  return Model(
    name = VA_MODEL_NAME,
    version = VA_MODEL_COMMIT,
    info =
      "A 4-bit quantized variant of google/Gemma-3-1B-IT running on-device via LiteRT-LM. Used " +
        "here to power the Voice Assistant.",
    url =
      "https://huggingface.co/$VA_MODEL_ID/resolve/$VA_MODEL_COMMIT/$VA_MODEL_FILE?download=true",
    sizeInBytes = VA_MODEL_SIZE_BYTES,
    downloadFileName = VA_MODEL_FILE,
    learnMoreUrl = "https://huggingface.co/$VA_MODEL_ID",
    minDeviceMemoryInGb = 6,
    configs = configs,
    showBenchmarkButton = false,
    showRunAgainButton = false,
    isLlm = true,
    llmMaxToken = 1024,
    accelerators = listOf(Accelerator.GPU, Accelerator.CPU),
    runtimeType = RuntimeType.LITERT_LM,
  )
}
