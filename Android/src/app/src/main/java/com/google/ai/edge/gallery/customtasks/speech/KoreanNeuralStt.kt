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

package com.google.ai.edge.gallery.customtasks.speech

import android.content.Context
import android.util.Log
import com.google.ai.edge.gallery.data.Model
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineSenseVoiceModelConfig
import java.io.File

private const val TAG = "AGKoreanNeuralStt"

/**
 * The model name of the downloadable neural speech-recognition voice used by the Voice Assistant.
 * This must match the SenseVoice model registered in the "Speech to Text" task (`SttTask`).
 */
const val NEURAL_STT_MODEL_NAME = "SenseVoice (multilingual)"

private const val NEURAL_STT_TOKENS = "tokens.txt"

/** The outcome of attempting to prepare/load the neural speech recognizer. */
sealed interface NeuralSttLoadResult {
  /** Recognizer is ready. */
  data class Success(val recognizer: OfflineRecognizer) : NeuralSttLoadResult

  /** The model files haven't been downloaded yet. */
  data object NotDownloaded : NeuralSttLoadResult

  /** Initialization failed. [message] is user-facing; [recoverable] hints whether retry may help. */
  data class Failure(val message: String, val recoverable: Boolean) : NeuralSttLoadResult
}

/**
 * Loads the downloadable multilingual SenseVoice recognizer (shared with the Speech to Text task)
 * as a `sherpa-onnx` [OfflineRecognizer], for callers (e.g. the Voice Assistant) that want fully
 * on-device, device-independent speech recognition instead of the system [android.speech.SpeechRecognizer].
 *
 * SenseVoice ships as a single `.onnx` plus `tokens.txt` (no archive to unpack), so preparation is
 * just file checks + engine construction. Must be called off the main thread.
 *
 * @param languageHint a sherpa language code ("ko", "en", "ja", "zh", "yue") or "auto"/empty to
 *   auto-detect.
 */
object KoreanNeuralStt {
  fun load(
    context: Context,
    model: Model,
    languageHint: String = "auto",
  ): NeuralSttLoadResult {
    return try {
      val modelPath = model.getPath(context = context)
      val tokensPath = model.getPath(context = context, fileName = NEURAL_STT_TOKENS)
      if (!File(modelPath).exists() || !File(tokensPath).exists()) {
        return NeuralSttLoadResult.NotDownloaded
      }

      val config =
        OfflineRecognizerConfig(
          featConfig = FeatureConfig(sampleRate = SPEECH_SAMPLE_RATE, featureDim = 80),
          modelConfig =
            OfflineModelConfig(
              senseVoice =
                OfflineSenseVoiceModelConfig(
                  model = modelPath,
                  language = if (languageHint == "auto") "" else languageHint,
                  useInverseTextNormalization = true,
                ),
              tokens = tokensPath,
              numThreads = 2,
              debug = false,
            ),
        )
      NeuralSttLoadResult.Success(OfflineRecognizer(config = config))
    } catch (e: Throwable) {
      Log.w(TAG, "Failed to load neural STT", e)
      NeuralSttLoadResult.Failure(e.message ?: "음성 인식 초기화에 실패했습니다.", recoverable = true)
    }
  }
}
