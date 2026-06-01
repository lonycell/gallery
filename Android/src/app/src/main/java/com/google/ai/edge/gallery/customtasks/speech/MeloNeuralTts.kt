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

private const val TAG = "AGMeloNeuralTts"

/**
 * The model name of the downloadable MeloTTS Korean neural voice. This must match the model
 * registered in the "Text to Speech" task (`TtsTask`).
 */
const val MELO_TTS_MODEL_NAME = "MeloTTS (ko)"

// Layout of the extracted MeloTTS model (a sherpa-onnx VITS model). MeloTTS models ship as a
// directory containing the ONNX graph, a phoneme `tokens.txt`, a `lexicon.txt`, and a `dict/`
// directory (used by the text frontend). Unlike the espeak-based KSS voice, MeloTTS uses
// lexicon + dictDir rather than an `espeak-ng-data` dir.
//
// NOTE: these names are the conventional sherpa-onnx MeloTTS layout (e.g. `vits-melo-tts-zh_en`).
// When a converted Korean archive is hosted (see TtsTask's TODO), confirm the extracted top-level
// directory name matches [MELO_TTS_DIR] and adjust if needed.
const val MELO_TTS_DIR = "vits-melo-tts-ko"
const val MELO_TTS_ONNX = "model.onnx"
const val MELO_TTS_TOKENS = "tokens.txt"
const val MELO_TTS_LEXICON = "lexicon.txt"
const val MELO_TTS_DICT_DIR = "dict"

/**
 * Approximate number of entries in the MeloTTS `.tar.bz2` archive, used only to render an unpack
 * progress percentage (a tar stream doesn't expose a total up front). The `dict/` directory holds
 * many files; this is a rough estimate and can be refined once the real archive is known.
 */
const val MELO_TTS_ARCHIVE_ENTRY_COUNT = 600

/** The outcome of attempting to prepare/load the MeloTTS Korean neural voice. */
sealed interface MeloTtsLoadResult {
  /** Engine is ready. */
  data class Success(val tts: OfflineTts) : MeloTtsLoadResult

  /** The model archive hasn't been downloaded yet. */
  data object NotDownloaded : MeloTtsLoadResult

  /** Preparation failed (unpack or initialization). [message] is user-facing; [recoverable] means
   * deleting the extracted files and retrying may help. */
  data class Failure(val message: String, val recoverable: Boolean) : MeloTtsLoadResult
}

/**
 * Loads the downloadable MeloTTS Korean neural voice (shared with the Text to Speech task) as a
 * `sherpa-onnx` [OfflineTts]. MeloTTS is a high-quality multilingual TTS by MyShell.ai; in
 * sherpa-onnx it runs as a VITS model (model.onnx + tokens.txt + lexicon.txt + dict/).
 *
 * Mirrors [KoreanNeuralTts]: the model is downloaded as a single `.tar.bz2`, unpacked once, and
 * wired into the engine. Distinguishes "not downloaded" from real failures so the UI can recover.
 * Must be called off the main thread (unpack + init are not instant).
 *
 * @param onUnpackProgress optional callback (0..100) reporting unpack progress. Only invoked when an
 *   extraction actually runs (skipped if already unpacked).
 * @param warmUp if true, runs a tiny synthesis after init so the first real reply is snappy.
 */
object MeloNeuralTts {
  fun load(
    context: Context,
    model: Model,
    onUnpackProgress: ((percent: Int) -> Unit)? = null,
    warmUp: Boolean = true,
  ): MeloTtsLoadResult {
    return try {
      val archiveFile = File(model.getPath(context = context))
      val baseDir =
        archiveFile.parentFile
          ?: return MeloTtsLoadResult.Failure("저장 위치를 찾을 수 없습니다.", recoverable = false)
      val extractedRoot = File(baseDir, MELO_TTS_DIR)
      val onnxFile = File(extractedRoot, MELO_TTS_ONNX)
      val tokensFile = File(extractedRoot, MELO_TTS_TOKENS)
      val lexiconFile = File(extractedRoot, MELO_TTS_LEXICON)
      val dictDir = File(extractedRoot, MELO_TTS_DICT_DIR)

      // The dict/ directory is part of MeloTTS's text frontend but may be absent for some exports;
      // treat only the onnx + tokens + lexicon as strictly required.
      val alreadyExtracted =
        onnxFile.exists() && tokensFile.exists() && lexiconFile.exists()
      if (!alreadyExtracted) {
        if (!archiveFile.exists()) {
          return MeloTtsLoadResult.NotDownloaded
        }
        // Clean any partial extraction from a previous interrupted attempt before retrying.
        if (extractedRoot.exists()) {
          extractedRoot.deleteRecursively()
        }
        val ok =
          extractTarBz2(archive = archiveFile, destDir = baseDir) { processed ->
            if (onUnpackProgress != null) {
              val pct = (processed * 100 / MELO_TTS_ARCHIVE_ENTRY_COUNT).coerceIn(0, 100)
              onUnpackProgress(pct)
            }
          }
        if (!ok || !onnxFile.exists() || !tokensFile.exists() || !lexiconFile.exists()) {
          // The archive may be corrupt/incomplete; recoverable by deleting it and re-downloading.
          return MeloTtsLoadResult.Failure(
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
                  lexicon = lexiconFile.absolutePath,
                  tokens = tokensFile.absolutePath,
                  // dictDir is part of the MeloTTS frontend; pass it only when present.
                  dictDir = if (dictDir.isDirectory) dictDir.absolutePath else "",
                ),
              numThreads = 2,
              debug = false,
              provider = "cpu",
            )
        )
      val engine = OfflineTts(config = config)

      // Warm up: the first synthesis pays a one-time cost; generating a tiny phrase now makes the
      // first real reply feel instant. The audio is discarded; failures here are non-fatal.
      if (warmUp) {
        try {
          engine.generate(text = "안녕", sid = 0, speed = 1.0f)
        } catch (e: Throwable) {
          Log.w(TAG, "Warm-up synthesis failed (non-fatal)", e)
        }
      }

      MeloTtsLoadResult.Success(engine)
    } catch (e: Throwable) {
      Log.w(TAG, "Failed to load MeloTTS neural voice", e)
      MeloTtsLoadResult.Failure(e.message ?: "음성 초기화에 실패했습니다.", recoverable = true)
    }
  }

  /**
   * Deletes the extracted MeloTTS files (not the downloaded archive) so a fresh extraction can be
   * attempted. Used for error recovery.
   */
  fun clearExtracted(context: Context, model: Model) {
    try {
      val baseDir = File(model.getPath(context = context)).parentFile ?: return
      File(baseDir, MELO_TTS_DIR).deleteRecursively()
    } catch (e: Throwable) {
      Log.w(TAG, "Failed to clear extracted MeloTTS files", e)
    }
  }
}
