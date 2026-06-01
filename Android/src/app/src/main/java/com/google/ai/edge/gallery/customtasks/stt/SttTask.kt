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

package com.google.ai.edge.gallery.customtasks.stt

import android.content.Context
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Transcribe
import androidx.compose.runtime.Composable
import com.google.ai.edge.gallery.customtasks.common.CustomTask
import com.google.ai.edge.gallery.customtasks.common.CustomTaskData
import com.google.ai.edge.gallery.customtasks.speech.NEURAL_STT_MODEL_NAME
import com.google.ai.edge.gallery.customtasks.speech.SPEECH_SAMPLE_RATE
import com.google.ai.edge.gallery.customtasks.speech.SpeechCategory
import com.google.ai.edge.gallery.customtasks.speech.WHISPER_KO_STT_MODEL_NAME
import com.google.ai.edge.gallery.customtasks.speech.WHISPER_SMALL_DECODER
import com.google.ai.edge.gallery.customtasks.speech.WHISPER_SMALL_ENCODER
import com.google.ai.edge.gallery.customtasks.speech.WHISPER_SMALL_TOKENS
import com.google.ai.edge.gallery.data.Config
import com.google.ai.edge.gallery.data.ConfigKey
import com.google.ai.edge.gallery.data.Model
import com.google.ai.edge.gallery.data.ModelDataFile
import com.google.ai.edge.gallery.data.SegmentedButtonConfig
import com.google.ai.edge.gallery.data.Task
import com.google.ai.edge.litertlm.Contents
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineSenseVoiceModelConfig
import com.k2fsa.sherpa.onnx.OfflineWhisperModelConfig
import java.io.File
import javax.inject.Inject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** Wraps an initialized `sherpa-onnx` [OfflineRecognizer] for storage on [Model.instance]. */
class SttModelInstance(val recognizer: OfflineRecognizer)

/** Config key letting the user hint the spoken language for the multilingual SenseVoice model. */
val STT_CONFIG_KEY_LANGUAGE = ConfigKey(id = "stt_language", label = "Language")

/** "auto" lets the model detect the language; the rest map to sherpa-onnx language codes. */
private val SENSE_VOICE_LANGUAGES = listOf("auto", "en", "ko", "ja", "zh", "yue")

private val SENSE_VOICE_CONFIGS: List<Config> =
  listOf(
    SegmentedButtonConfig(
      key = STT_CONFIG_KEY_LANGUAGE,
      defaultValue = "auto",
      options = SENSE_VOICE_LANGUAGES,
    )
  )

// Multilingual Whisper takes a single spoken-language hint; "auto" lets Whisper detect it. Default
// to Korean since these entries are added for good Korean recognition.
private val WHISPER_LANGUAGES = listOf("ko", "auto", "en", "ja", "zh")

private val WHISPER_KO_CONFIGS: List<Config> =
  listOf(
    SegmentedButtonConfig(
      key = STT_CONFIG_KEY_LANGUAGE,
      defaultValue = "ko",
      options = WHISPER_LANGUAGES,
    )
  )

// Shared with the Voice Assistant (which can reuse this downloaded recognizer for neural STT).
const val STT_MODEL_SENSE_VOICE = NEURAL_STT_MODEL_NAME
const val STT_MODEL_WHISPER_TINY_EN = "Whisper-tiny (en)"
const val STT_MODEL_WHISPER_BASE_KO = "Whisper base (multilingual)"
// The small multilingual model is also offered to the Voice Assistant for high-quality Korean.
const val STT_MODEL_WHISPER_SMALL_KO = WHISPER_KO_STT_MODEL_NAME

private const val SENSE_VOICE_BASE_URL =
  "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main"
private const val WHISPER_BASE_URL =
  "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main"
// Multilingual Whisper checkpoints (base / small) converted for sherpa-onnx. Each ships as a split
// encoder/decoder (int8) plus a tokens file. They support Korean via the language hint.
private const val WHISPER_BASE_ML_URL =
  "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/main"
private const val WHISPER_SMALL_ML_URL =
  "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/main"
private const val WHISPER_BASE_ENCODER = "base-encoder.int8.onnx"
private const val WHISPER_BASE_DECODER = "base-decoder.int8.onnx"
private const val WHISPER_BASE_TOKENS = "base-tokens.txt"

/**
 * A custom task that transcribes recorded microphone audio to text fully on-device using
 * `sherpa-onnx` ASR models.
 *
 * Downloadable models are offered:
 * - **SenseVoice**: a multilingual model (Chinese, English, Japanese, Korean, Cantonese) shipped as
 *   a single `.onnx` file plus `tokens.txt`.
 * - **Whisper tiny (en)**: a lightweight English model split into encoder/decoder files.
 * - **Whisper base / small (multilingual)**: OpenAI Whisper checkpoints with strong Korean support
 *   (language defaults to Korean, configurable). The `small` model is also offered to the Voice
 *   Assistant for high-quality on-device Korean recognition.
 *
 * Model files are fetched through the app's standard download mechanism and wired into an
 * [OfflineRecognizer] on initialization. The [SttScreen] records audio and feeds it to the
 * recognizer.
 */
class SttTask @Inject constructor() : CustomTask {
  override val task: Task =
    Task(
      id = "speech_stt",
      label = "Speech to Text",
      category = SpeechCategory,
      icon = Icons.Outlined.Transcribe,
      description =
        "Transcribe your voice to text fully on-device using downloadable " +
          "[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) speech recognition models. " +
          "Pick a model, tap **Record**, speak, then tap **Stop** to transcribe.",
      shortDescription = "On-device speech to text",
      docUrl = "https://k2-fsa.github.io/sherpa/onnx/pretrained_models/index.html",
      sourceCodeUrl =
        "https://github.com/google-ai-edge/gallery/blob/main/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/stt",
      models =
        mutableListOf(
          Model(
            name = STT_MODEL_SENSE_VOICE,
            info =
              "Multilingual speech recognition (zh/en/ja/ko/yue). Set the spoken language in the " +
                "config menu, or leave it on \"auto\" to auto-detect.",
            learnMoreUrl =
              "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17",
            url = "$SENSE_VOICE_BASE_URL/model.int8.onnx",
            downloadFileName = "model.int8.onnx",
            sizeInBytes = 239233841L,
            extraDataFiles =
              listOf(
                ModelDataFile(
                  name = "tokens",
                  url = "$SENSE_VOICE_BASE_URL/tokens.txt",
                  downloadFileName = "tokens.txt",
                  sizeInBytes = 315894L,
                )
              ),
            configs = SENSE_VOICE_CONFIGS,
          ),
          Model(
            name = STT_MODEL_WHISPER_TINY_EN,
            info = "Lightweight English-only speech recognition based on OpenAI Whisper tiny.en.",
            learnMoreUrl = "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en",
            url = "$WHISPER_BASE_URL/tiny.en-encoder.int8.onnx",
            downloadFileName = "tiny.en-encoder.int8.onnx",
            sizeInBytes = 12937772L,
            extraDataFiles =
              listOf(
                ModelDataFile(
                  name = "decoder",
                  url = "$WHISPER_BASE_URL/tiny.en-decoder.int8.onnx",
                  downloadFileName = "tiny.en-decoder.int8.onnx",
                  sizeInBytes = 89853865L,
                ),
                ModelDataFile(
                  name = "tokens",
                  url = "$WHISPER_BASE_URL/tiny.en-tokens.txt",
                  downloadFileName = "tiny.en-tokens.txt",
                  sizeInBytes = 835554L,
                ),
              ),
          ),
          Model(
            name = STT_MODEL_WHISPER_BASE_KO,
            info =
              "Multilingual speech recognition (OpenAI Whisper base). Good Korean support; smaller " +
                "and faster than Whisper small. Set the spoken language in the config menu " +
                "(defaults to Korean), or pick \"auto\" to auto-detect.",
            learnMoreUrl = "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base",
            url = "$WHISPER_BASE_ML_URL/$WHISPER_BASE_ENCODER",
            downloadFileName = WHISPER_BASE_ENCODER,
            sizeInBytes = 29120534L,
            extraDataFiles =
              listOf(
                ModelDataFile(
                  name = "decoder",
                  url = "$WHISPER_BASE_ML_URL/$WHISPER_BASE_DECODER",
                  downloadFileName = WHISPER_BASE_DECODER,
                  sizeInBytes = 130672026L,
                ),
                ModelDataFile(
                  name = "tokens",
                  url = "$WHISPER_BASE_ML_URL/$WHISPER_BASE_TOKENS",
                  downloadFileName = WHISPER_BASE_TOKENS,
                  sizeInBytes = 816730L,
                ),
              ),
            configs = WHISPER_KO_CONFIGS,
          ),
          Model(
            name = STT_MODEL_WHISPER_SMALL_KO,
            info =
              "Multilingual speech recognition (OpenAI Whisper small). Stronger Korean accuracy " +
                "than base, but a larger download and slower on-device decoding. Set the spoken " +
                "language in the config menu (defaults to Korean), or pick \"auto\". Also offered " +
                "in the Voice Assistant.",
            learnMoreUrl = "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small",
            url = "$WHISPER_SMALL_ML_URL/$WHISPER_SMALL_ENCODER",
            downloadFileName = WHISPER_SMALL_ENCODER,
            sizeInBytes = 112442483L,
            extraDataFiles =
              listOf(
                ModelDataFile(
                  name = "decoder",
                  url = "$WHISPER_SMALL_ML_URL/$WHISPER_SMALL_DECODER",
                  downloadFileName = WHISPER_SMALL_DECODER,
                  sizeInBytes = 262226114L,
                ),
                ModelDataFile(
                  name = "tokens",
                  url = "$WHISPER_SMALL_ML_URL/$WHISPER_SMALL_TOKENS",
                  downloadFileName = WHISPER_SMALL_TOKENS,
                  sizeInBytes = 816730L,
                ),
              ),
            configs = WHISPER_KO_CONFIGS,
          ),
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
        val config = buildRecognizerConfig(context = context, model = model)
        model.instance = SttModelInstance(recognizer = OfflineRecognizer(config = config))
        onDone("")
      } catch (e: Throwable) {
        onDone(e.message ?: "Failed to initialize the speech recognition model")
      }
    }
  }

  private fun buildRecognizerConfig(context: Context, model: Model): OfflineRecognizerConfig {
    val featConfig = FeatureConfig(sampleRate = SPEECH_SAMPLE_RATE, featureDim = 80)

    val modelConfig: OfflineModelConfig =
      when (model.name) {
        STT_MODEL_WHISPER_TINY_EN -> {
          val encoder = model.getPath(context = context)
          val decoder = model.getPath(context = context, fileName = "tiny.en-decoder.int8.onnx")
          val tokens = model.getPath(context = context, fileName = "tiny.en-tokens.txt")
          requireFilesExist(encoder, decoder, tokens)
          OfflineModelConfig(
            whisper = OfflineWhisperModelConfig(encoder = encoder, decoder = decoder),
            tokens = tokens,
            numThreads = 2,
            debug = false,
            modelType = "whisper",
          )
        }
        STT_MODEL_WHISPER_BASE_KO ->
          buildWhisperConfig(context, model, WHISPER_BASE_DECODER, WHISPER_BASE_TOKENS)
        STT_MODEL_WHISPER_SMALL_KO ->
          buildWhisperConfig(context, model, WHISPER_SMALL_DECODER, WHISPER_SMALL_TOKENS)
        else -> {
          // SenseVoice (default).
          val modelPath = model.getPath(context = context)
          val tokens = model.getPath(context = context, fileName = "tokens.txt")
          requireFilesExist(modelPath, tokens)
          val languageHint = model.getStringConfigValue(STT_CONFIG_KEY_LANGUAGE, defaultValue = "auto")
          OfflineModelConfig(
            senseVoice =
              OfflineSenseVoiceModelConfig(
                model = modelPath,
                // An empty language means auto-detect.
                language = if (languageHint == "auto") "" else languageHint,
                useInverseTextNormalization = true,
              ),
            tokens = tokens,
            numThreads = 2,
            debug = false,
          )
        }
      }

    return OfflineRecognizerConfig(featConfig = featConfig, modelConfig = modelConfig)
  }

  /**
   * Builds the recognizer config for a multilingual Whisper model (base/small). The encoder is the
   * model's primary download file; [decoderFile] and [tokensFile] are its extra data files. The
   * spoken language comes from the user's config (defaults to Korean; "auto" → Whisper detects).
   */
  private fun buildWhisperConfig(
    context: Context,
    model: Model,
    decoderFile: String,
    tokensFile: String,
  ): OfflineModelConfig {
    val encoder = model.getPath(context = context)
    val decoder = model.getPath(context = context, fileName = decoderFile)
    val tokens = model.getPath(context = context, fileName = tokensFile)
    requireFilesExist(encoder, decoder, tokens)
    val languageHint = model.getStringConfigValue(STT_CONFIG_KEY_LANGUAGE, defaultValue = "ko")
    return OfflineModelConfig(
      whisper =
        OfflineWhisperModelConfig(
          encoder = encoder,
          decoder = decoder,
          // An empty language enables Whisper's built-in language detection.
          language = if (languageHint == "auto") "" else languageHint,
          task = "transcribe",
        ),
      tokens = tokens,
      numThreads = 2,
      debug = false,
      modelType = "whisper",
    )
  }

  private fun requireFilesExist(vararg paths: String) {
    for (path in paths) {
      if (!File(path).exists()) {
        throw IllegalStateException("Missing model file: $path")
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
    (model.instance as? SttModelInstance)?.let {
      try {
        it.recognizer.release()
      } catch (_: Throwable) {}
    }
    model.instance = null
  }

  @Composable
  override fun MainScreen(data: Any) {
    val customTaskData = data as CustomTaskData
    SttScreen(modelManagerViewModel = customTaskData.modelManagerViewModel)
  }
}
