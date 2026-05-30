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
import com.k2fsa.sherpa.onnx.OfflineTts
import com.k2fsa.sherpa.onnx.OfflineTtsConfig
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig
import java.io.File

private const val TAG = "AGKoreanNeuralTts"

/**
 * The model name of the downloadable Korean neural TTS voice. This must match the model registered
 * in the "Text to Speech" task (`TtsTask`).
 */
const val KOREAN_TTS_MODEL_NAME = "VITS-KSS (ko)"

private const val KOREAN_TTS_DIR = "vits-mimic3-ko_KO-kss_low"
private const val KOREAN_TTS_ONNX = "ko_KO-kss_low.onnx"

/**
 * Loads the downloadable Korean VITS voice (shared with the Text to Speech task) as a `sherpa-onnx`
 * [OfflineTts] engine, for callers that want higher-quality, device-independent Korean speech than
 * the system TextToSpeech engine.
 *
 * The voice ships as a `.tar.bz2` bundle (it carries an `espeak-ng-data` directory). This helper
 * assumes the archive has already been downloaded through the app's standard mechanism and, if
 * needed, extracts it before constructing the engine.
 *
 * @return an [OfflineTts] ready to synthesize Korean, or `null` if the model hasn't been downloaded
 *   yet (or extraction/initialization failed). A `null` result is the caller's cue to fall back to
 *   the system TextToSpeech engine.
 */
object KoreanNeuralTts {
  fun tryLoad(context: Context, model: Model): OfflineTts? {
    return try {
      val archiveFile = File(model.getPath(context = context))
      val baseDir = archiveFile.parentFile ?: return null
      val extractedRoot = File(baseDir, KOREAN_TTS_DIR)
      val onnxFile = File(extractedRoot, KOREAN_TTS_ONNX)
      val tokensFile = File(extractedRoot, "tokens.txt")
      val dataDir = File(extractedRoot, "espeak-ng-data")

      if (!(onnxFile.exists() && tokensFile.exists() && dataDir.isDirectory)) {
        if (!archiveFile.exists()) {
          // Not downloaded yet.
          return null
        }
        val ok = extractTarBz2(archive = archiveFile, destDir = baseDir)
        if (!ok || !onnxFile.exists() || !tokensFile.exists() || !dataDir.isDirectory) {
          return null
        }
      }

      val config =
        OfflineTtsConfig(
          model =
            OfflineTtsModelConfig(
              vits =
                OfflineTtsVitsModelConfig(
                  model = onnxFile.absolutePath,
                  tokens = tokensFile.absolutePath,
                  dataDir = dataDir.absolutePath,
                ),
              numThreads = 2,
              debug = false,
              provider = "cpu",
            )
        )
      OfflineTts(config = config)
    } catch (e: Throwable) {
      Log.w(TAG, "Failed to load Korean neural TTS", e)
      null
    }
  }
}
