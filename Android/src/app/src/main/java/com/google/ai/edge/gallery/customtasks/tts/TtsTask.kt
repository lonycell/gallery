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

package com.google.ai.edge.gallery.customtasks.tts

import android.content.Context
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.RecordVoiceOver
import androidx.compose.runtime.Composable
import com.google.ai.edge.gallery.customtasks.common.CustomTask
import com.google.ai.edge.gallery.customtasks.common.CustomTaskData
import com.google.ai.edge.gallery.customtasks.speech.SpeechCategory
import com.google.ai.edge.gallery.data.Config
import com.google.ai.edge.gallery.data.ConfigKey
import com.google.ai.edge.gallery.data.Model
import com.google.ai.edge.gallery.data.ModelDataFile
import com.google.ai.edge.gallery.data.NumberSliderConfig
import com.google.ai.edge.gallery.data.Task
import com.google.ai.edge.gallery.data.ValueType
import com.google.ai.edge.litertlm.Contents
import com.k2fsa.sherpa.onnx.OfflineTts
import com.k2fsa.sherpa.onnx.OfflineTtsConfig
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig
import java.io.File
import javax.inject.Inject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** Wraps an initialized `sherpa-onnx` [OfflineTts] engine so it can be stored on [Model.instance]. */
class TtsModelInstance(val tts: OfflineTts)

/** Config key controlling the synthesis speed (1.0 = normal). */
val TTS_CONFIG_KEY_SPEED = ConfigKey(id = "tts_speed", label = "Speed")

private val TTS_CONFIGS: List<Config> =
  listOf(
    NumberSliderConfig(
      key = TTS_CONFIG_KEY_SPEED,
      sliderMin = 0.5f,
      sliderMax = 2.0f,
      defaultValue = 1.0f,
      valueType = ValueType.FLOAT,
      // Speed is applied per-generation, so it doesn't require re-initializing the engine.
      needReinitialization = false,
    )
  )

const val TTS_MODEL_VITS_LJSPEECH = "VITS-LJSpeech (en)"

private const val VITS_LJS_BASE_URL = "https://huggingface.co/csukuangfj/vits-ljs/resolve/main"

/**
 * A custom task that performs on-device text-to-speech using `sherpa-onnx` VITS models.
 *
 * The model files are downloaded from HuggingFace through the app's standard download mechanism
 * (the main `.onnx` file via [Model.url], and the `tokens.txt` / `lexicon.txt` files via
 * [Model.extraDataFiles]). On initialization, the downloaded files are wired into an
 * [OfflineTts] engine, which the [TtsScreen] uses to synthesize speech.
 */
class TtsTask @Inject constructor() : CustomTask {
  override val task: Task =
    Task(
      id = "speech_tts",
      label = "Text to Speech",
      category = SpeechCategory,
      icon = Icons.Outlined.RecordVoiceOver,
      description =
        "Synthesize natural speech from text fully on-device using downloadable " +
          "[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) VITS models. Type some text, " +
          "pick a model, and tap **Speak**.",
      shortDescription = "On-device text to speech",
      docUrl = "https://k2-fsa.github.io/sherpa/onnx/tts/index.html",
      sourceCodeUrl =
        "https://github.com/google-ai-edge/gallery/blob/main/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/tts",
      models =
        mutableListOf(
          Model(
            name = TTS_MODEL_VITS_LJSPEECH,
            info =
              "A single-speaker English VITS voice (LJSpeech) exported for sherpa-onnx. Uses a " +
                "lexicon for pronunciation, so no extra data files are required.",
            learnMoreUrl = "https://huggingface.co/csukuangfj/vits-ljs",
            url = "$VITS_LJS_BASE_URL/vits-ljs.int8.onnx",
            downloadFileName = "vits-ljs.int8.onnx",
            sizeInBytes = 37423560L,
            extraDataFiles =
              listOf(
                ModelDataFile(
                  name = "tokens",
                  url = "$VITS_LJS_BASE_URL/tokens.txt",
                  downloadFileName = "tokens.txt",
                  sizeInBytes = 1084L,
                ),
                ModelDataFile(
                  name = "lexicon",
                  url = "$VITS_LJS_BASE_URL/lexicon.txt",
                  downloadFileName = "lexicon.txt",
                  sizeInBytes = 3708181L,
                ),
              ),
            configs = TTS_CONFIGS,
          )
        ),
    )

  override fun initializeModelFn(
    context: Context,
    coroutineScope: CoroutineScope,
    model: Model,
    systemInstruction: Contents?,
    onDone: (error: String) -> Unit,
  ) {
    coroutineScope.launch(Dispatchers.IO) {
      cleanUp(model)
      try {
        val modelPath = model.getPath(context = context)
        val tokensPath = model.getPath(context = context, fileName = "tokens.txt")
        val lexiconPath = model.getPath(context = context, fileName = "lexicon.txt")

        for (path in listOf(modelPath, tokensPath, lexiconPath)) {
          if (!File(path).exists()) {
            onDone("Missing model file: $path")
            return@launch
          }
        }

        val config =
          OfflineTtsConfig(
            model =
              OfflineTtsModelConfig(
                vits =
                  OfflineTtsVitsModelConfig(
                    model = modelPath,
                    lexicon = lexiconPath,
                    tokens = tokensPath,
                  ),
                numThreads = 2,
                debug = false,
                provider = "cpu",
              )
          )
        model.instance = TtsModelInstance(tts = OfflineTts(config = config))
        onDone("")
      } catch (e: Throwable) {
        onDone(e.message ?: "Failed to initialize the TTS model")
      }
    }
  }

  override fun cleanUpModelFn(
    context: Context,
    coroutineScope: CoroutineScope,
    model: Model,
    onDone: () -> Unit,
  ) {
    cleanUp(model)
    onDone()
  }

  private fun cleanUp(model: Model) {
    (model.instance as? TtsModelInstance)?.let {
      try {
        it.tts.release()
      } catch (_: Throwable) {}
    }
    model.instance = null
  }

  @Composable
  override fun MainScreen(data: Any) {
    val customTaskData = data as CustomTaskData
    TtsScreen(modelManagerViewModel = customTaskData.modelManagerViewModel)
  }
}
