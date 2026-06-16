/*
 * Copyright 2026 Google LLC
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

package com.google.ai.edge.gallery.customtasks.dashchat

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Speech-to-text bridge for the Dash Chat web page, mirroring [DashChatLlmBridge]. Wraps the system
 * [SpeechRecognizer] so a hosted page can dictate exactly like the native chat does.
 *
 * Exposed to the page as `window.AiEdgeStt`:
 * - `AiEdgeStt.isAvailable(): Boolean`
 * - `AiEdgeStt.start(requestId)` — streams interim text via `window.aiEdgeSttOnPartial`, finishes
 *   with `window.aiEdgeSttOnResult`; errors via `window.aiEdgeSttOnError`.
 * - `AiEdgeStt.stop(requestId)` — stop listening and finalize the current utterance.
 * - `AiEdgeStt.cancel(requestId)` — abort without a final result.
 *
 * The [SpeechRecognizer] is created and driven on the main thread (required by the platform); JS
 * results are posted back on the WebView's thread.
 *
 * @param scope a main-thread coroutine scope tied to the hosting screen (cancelled on leave).
 */
class DashChatSttBridge(
  private val context: Context,
  private val scope: CoroutineScope,
  private val webViewProvider: () -> WebView?,
) {
  private var recognizer: SpeechRecognizer? = null
  @Volatile private var currentRequestId: String? = null

  @JavascriptInterface
  fun isAvailable(): Boolean = SpeechRecognizer.isRecognitionAvailable(context)

  @JavascriptInterface
  fun start(requestId: String) {
    scope.launch(Dispatchers.Main) {
      if (
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) !=
          PackageManager.PERMISSION_GRANTED
      ) {
        emitError(requestId, "마이크 권한이 필요해요. 앱 설정에서 권한을 허용해 주세요.")
        return@launch
      }
      if (!SpeechRecognizer.isRecognitionAvailable(context)) {
        emitError(requestId, "이 기기에서는 음성 인식을 사용할 수 없어요.")
        return@launch
      }

      // Fresh recognizer per utterance keeps state clean.
      recognizer?.destroy()
      val sr = SpeechRecognizer.createSpeechRecognizer(context)
      recognizer = sr
      currentRequestId = requestId
      sr.setRecognitionListener(
        object : RecognitionListener {
          override fun onPartialResults(partial: Bundle?) {
            val text = firstResult(partial) ?: return
            if (currentRequestId == requestId && text.isNotEmpty()) {
              emit("window.aiEdgeSttOnPartial", requestId, text)
            }
          }

          override fun onResults(results: Bundle?) {
            if (currentRequestId != requestId) return
            currentRequestId = null
            emit("window.aiEdgeSttOnResult", requestId, firstResult(results).orEmpty())
          }

          override fun onError(error: Int) {
            if (currentRequestId != requestId) return
            currentRequestId = null
            // Treat "heard nothing" as an empty result so the turn just ends quietly.
            if (error == SpeechRecognizer.ERROR_NO_MATCH ||
              error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
            ) {
              emit("window.aiEdgeSttOnResult", requestId, "")
            } else {
              emitError(requestId, sttErrorMessage(error))
            }
          }

          override fun onReadyForSpeech(params: Bundle?) {}

          override fun onBeginningOfSpeech() {}

          override fun onRmsChanged(rmsdB: Float) {}

          override fun onBufferReceived(buffer: ByteArray?) {}

          override fun onEndOfSpeech() {}

          override fun onEvent(eventType: Int, params: Bundle?) {}
        }
      )

      val intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
          putExtra(
            RecognizerIntent.EXTRA_LANGUAGE_MODEL,
            RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
          )
          putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ko-KR")
          putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        }
      runCatching { sr.startListening(intent) }
        .onFailure { emitError(requestId, it.message ?: "음성 인식을 시작하지 못했어요.") }
    }
  }

  @JavascriptInterface
  fun stop(@Suppress("UNUSED_PARAMETER") requestId: String) {
    scope.launch(Dispatchers.Main) { runCatching { recognizer?.stopListening() } }
  }

  @JavascriptInterface
  fun cancel(requestId: String) {
    scope.launch(Dispatchers.Main) {
      if (currentRequestId == requestId) currentRequestId = null
      runCatching { recognizer?.cancel() }
    }
  }

  /** Releases the recognizer (called when the hosting screen goes away). */
  fun stop() {
    scope.launch(Dispatchers.Main) {
      currentRequestId = null
      runCatching { recognizer?.destroy() }
      recognizer = null
    }
  }

  private fun firstResult(b: Bundle?): String? =
    b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()

  private fun sttErrorMessage(error: Int): String =
    when (error) {
      SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "마이크 권한이 필요해요."
      SpeechRecognizer.ERROR_NETWORK,
      SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "네트워크 문제로 음성 인식에 실패했어요."
      SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "음성 인식이 사용 중이에요. 잠시 후 다시 시도해 주세요."
      else -> "음성 인식에 실패했어요."
    }

  private fun emit(fn: String, requestId: String, payload: String) {
    val wv = webViewProvider() ?: return
    val js = "if ($fn) $fn(${JSONObject.quote(requestId)}, ${JSONObject.quote(payload)});"
    wv.post { wv.evaluateJavascript(js, null) }
  }

  private fun emitError(requestId: String, message: String) =
    emit("window.aiEdgeSttOnError", requestId, message)
}
