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

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.webkit.JavascriptInterface
import android.webkit.WebView
import java.util.Locale
import org.json.JSONObject

/**
 * Text-to-speech bridge for the Dash Chat web page, mirroring [DashChatLlmBridge]. Wraps the system
 * [TextToSpeech] engine so a hosted page can speak replies exactly like the native chat does.
 *
 * Exposed to the page as `window.AiEdgeTts`:
 * - `AiEdgeTts.isReady(): Boolean`
 * - `AiEdgeTts.speak(requestId, text)` — fires `window.aiEdgeTtsOnStart` then
 *   `window.aiEdgeTtsOnDone`; errors via `window.aiEdgeTtsOnError`.
 * - `AiEdgeTts.stop(requestId)` — stop any in-flight playback.
 *
 * The page serializes utterances (one sentence at a time, waiting for `onDone` before the next), so
 * each [speak] uses `QUEUE_FLUSH`. Engine callbacks arrive on a binder thread and are posted back on
 * the WebView's thread.
 */
class DashChatTtsBridge(
  context: Context,
  private val webViewProvider: () -> WebView?,
) {
  @Volatile private var ready = false
  @Volatile private var currentRequestId: String? = null
  private var tts: TextToSpeech? = null

  init {
    tts =
      TextToSpeech(context) { status ->
        ready = status == TextToSpeech.SUCCESS
        if (ready) {
          tts?.language = Locale.KOREAN
          tts?.setOnUtteranceProgressListener(
            object : UtteranceProgressListener() {
              override fun onStart(utteranceId: String?) {
                if (utteranceId != null) emit("window.aiEdgeTtsOnStart", utteranceId)
              }

              override fun onDone(utteranceId: String?) {
                if (utteranceId == null) return
                if (currentRequestId == utteranceId) currentRequestId = null
                emit("window.aiEdgeTtsOnDone", utteranceId)
              }

              @Deprecated("Deprecated in Java")
              override fun onError(utteranceId: String?) {
                if (utteranceId != null) emitError(utteranceId, "음성 합성에 실패했어요.")
              }

              override fun onError(utteranceId: String?, errorCode: Int) {
                if (utteranceId != null) emitError(utteranceId, "음성 합성에 실패했어요.")
              }
            }
          )
        }
      }
  }

  @JavascriptInterface fun isReady(): Boolean = ready

  @JavascriptInterface
  fun speak(requestId: String, text: String) {
    val engine = tts
    if (!ready || engine == null) {
      emitError(requestId, "음성 엔진이 아직 준비되지 않았어요.")
      return
    }
    currentRequestId = requestId
    val result = engine.speak(text, TextToSpeech.QUEUE_FLUSH, Bundle(), requestId)
    if (result != TextToSpeech.SUCCESS) emitError(requestId, "음성 합성을 시작하지 못했어요.")
  }

  @JavascriptInterface
  fun stop(requestId: String) {
    if (currentRequestId == requestId) currentRequestId = null
    runCatching { tts?.stop() }
  }

  /** Stops and releases the engine (called when the hosting screen goes away). */
  fun shutdown() {
    runCatching { tts?.stop() }
    runCatching { tts?.shutdown() }
    tts = null
    ready = false
  }

  private fun emit(fn: String, requestId: String) {
    val wv = webViewProvider() ?: return
    val js = "if ($fn) $fn(${JSONObject.quote(requestId)});"
    wv.post { wv.evaluateJavascript(js, null) }
  }

  private fun emitError(requestId: String, message: String) {
    val wv = webViewProvider() ?: return
    val js =
      "if (window.aiEdgeTtsOnError) window.aiEdgeTtsOnError(" +
        "${JSONObject.quote(requestId)}, ${JSONObject.quote(message)});"
    wv.post { wv.evaluateJavascript(js, null) }
  }
}
