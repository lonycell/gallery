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
/** The outcome of attempting to prepare/load the Korean neural voice. */
sealed interface KoreanTtsLoadResult {
  /** Engine is ready. */
  data class Success(val tts: OfflineTts) : KoreanTtsLoadResult

  /** The model archive hasn't been downloaded yet. */
  data object NotDownloaded : KoreanTtsLoadResult

  /** Preparation failed (unpack or initialization). [message] is user-facing; [recoverable] means
   * deleting the extracted files and retrying may help. */
  data class Failure(val message: String, val recoverable: Boolean) : KoreanTtsLoadResult
}

object KoreanNeuralTts {
  /**
   * Prepares the Korean neural voice: unpacks the downloaded `.tar.bz2` (if not already unpacked)
   * and constructs the sherpa-onnx engine. Distinguishes "not downloaded" from real failures so the
   * UI can recover (retry, re-download, etc).
   *
   * This may take noticeable time (the archive is ~64MB and unpacks hundreds of files), so it must
   * be called off the main thread.
   */
  fun load(context: Context, model: Model): KoreanTtsLoadResult {
    return try {
      val archiveFile = File(model.getPath(context = context))
      val baseDir = archiveFile.parentFile
          ?: return KoreanTtsLoadResult.Failure("저장 위치를 찾을 수 없습니다.", recoverable = false)
      val extractedRoot = File(baseDir, KOREAN_TTS_DIR)
      val onnxFile = File(extractedRoot, KOREAN_TTS_ONNX)
      val tokensFile = File(extractedRoot, "tokens.txt")
      val dataDir = File(extractedRoot, "espeak-ng-data")

      val alreadyExtracted = onnxFile.exists() && tokensFile.exists() && dataDir.isDirectory
      if (!alreadyExtracted) {
        if (!archiveFile.exists()) {
          return KoreanTtsLoadResult.NotDownloaded
        }
        // Clean any partial extraction from a previous interrupted attempt before retrying.
        if (extractedRoot.exists()) {
          extractedRoot.deleteRecursively()
        }
        val ok = extractTarBz2(archive = archiveFile, destDir = baseDir)
        if (!ok || !onnxFile.exists() || !tokensFile.exists() || !dataDir.isDirectory) {
          // The archive may be corrupt/incomplete; recoverable by deleting it and re-downloading.
          return KoreanTtsLoadResult.Failure(
            "음성 데이터 압축 해제에 실패했습니다. 다시 시도해 주세요.",
            recoverable = true,
          )
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
      KoreanTtsLoadResult.Success(OfflineTts(config = config))
    } catch (e: Throwable) {
      Log.w(TAG, "Failed to load Korean neural TTS", e)
      KoreanTtsLoadResult.Failure(e.message ?: "음성 초기화에 실패했습니다.", recoverable = true)
    }
  }

  /**
   * Deletes the extracted neural-voice files (not the downloaded archive) so a fresh extraction can
   * be attempted. Used for error recovery.
   */
  fun clearExtracted(context: Context, model: Model) {
    try {
      val baseDir = File(model.getPath(context = context)).parentFile ?: return
      File(baseDir, KOREAN_TTS_DIR).deleteRecursively()
    } catch (e: Throwable) {
      Log.w(TAG, "Failed to clear extracted Korean TTS files", e)
    }
  }
}
