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
import com.k2fsa.sherpa.onnx.OfflineWhisperModelConfig
import java.io.File

private const val TAG = "AGWhisperNeuralStt"

/**
 * The model name of the downloadable Whisper Korean recognizer used by the Voice Assistant. This
 * must match the multilingual Whisper model registered in the "Speech to Text" task (`SttTask`).
 * We use the `small` multilingual checkpoint: it gives notably better Korean than `base`, at the
 * cost of a larger download and slower (autoregressive) decoding on-device.
 */
const val WHISPER_KO_STT_MODEL_NAME = "Whisper small (multilingual)"

// File layout of the sherpa-onnx multilingual Whisper `small` model (int8). The encoder is the
// model's primary download file; the decoder + tokens come as extra data files. Shared with
// SttTask so the registration and this loader stay in sync.
const val WHISPER_SMALL_ENCODER = "small-encoder.int8.onnx"
const val WHISPER_SMALL_DECODER = "small-decoder.int8.onnx"
const val WHISPER_SMALL_TOKENS = "small-tokens.txt"

/**
 * Loads a downloadable multilingual Whisper recognizer (shared with the Speech to Text task) as a
 * `sherpa-onnx` [OfflineRecognizer], configured for a given spoken [language] (e.g. "ko").
 *
 * Unlike SenseVoice, Whisper ships as a split encoder/decoder (plus `tokens.txt`); there is no
 * archive to unpack, so preparation is just file checks + engine construction. Must be called off
 * the main thread.
 *
 * @param language a Whisper language code such as "ko"/"en"; empty enables Whisper auto-detection.
 */
object WhisperNeuralStt {
  fun load(
    context: Context,
    model: Model,
    encoderFileName: String = WHISPER_SMALL_ENCODER,
    decoderFileName: String = WHISPER_SMALL_DECODER,
    tokensFileName: String = WHISPER_SMALL_TOKENS,
    language: String = "ko",
  ): NeuralSttLoadResult {
    return try {
      // The encoder is the model's primary file; getPath() with no name returns it. We also accept
      // an explicit name in case a caller stored it differently.
      val encoderPath = model.getPath(context = context, fileName = encoderFileName)
      val encoder = if (File(encoderPath).exists()) encoderPath else model.getPath(context = context)
      val decoder = model.getPath(context = context, fileName = decoderFileName)
      val tokens = model.getPath(context = context, fileName = tokensFileName)
      if (!File(encoder).exists() || !File(decoder).exists() || !File(tokens).exists()) {
        return NeuralSttLoadResult.NotDownloaded
      }

      val config =
        OfflineRecognizerConfig(
          featConfig = FeatureConfig(sampleRate = SPEECH_SAMPLE_RATE, featureDim = 80),
          modelConfig =
            OfflineModelConfig(
              whisper =
                OfflineWhisperModelConfig(
                  encoder = encoder,
                  decoder = decoder,
                  language = language,
                  task = "transcribe",
                ),
              tokens = tokens,
              numThreads = 2,
              debug = false,
              modelType = "whisper",
            ),
        )
      NeuralSttLoadResult.Success(OfflineRecognizer(config = config))
    } catch (e: Throwable) {
      Log.w(TAG, "Failed to load Whisper STT", e)
      NeuralSttLoadResult.Failure(e.message ?: "음성 인식 초기화에 실패했습니다.", recoverable = true)
    }
  }
}
