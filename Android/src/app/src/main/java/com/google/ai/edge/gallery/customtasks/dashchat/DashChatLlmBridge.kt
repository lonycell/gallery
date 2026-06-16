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

import android.util.Log
import android.webkit.JavascriptInterface
import android.webkit.WebView
import com.google.ai.edge.gallery.data.Model
import com.google.ai.edge.gallery.runtime.runtimeHelper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject

private const val TAG = "AGDashChatBridge"

/**
 * The JS bridge that lets the Dash Chat web page talk to the app's on-device LLM, **sharing the same
 * conversation context as the rest of the app** (it runs inference on the currently selected,
 * already-initialized model and its conversation — no separate session).
 *
 * Exposed to the page as `window.AiEdgeLlm`:
 * - `AiEdgeLlm.isReady(): Boolean`
 * - `AiEdgeLlm.sendPrompt(requestId, prompt)` — streams tokens back via `window.aiEdgeLlmOnToken`,
 *   then `window.aiEdgeLlmOnDone`; errors via `window.aiEdgeLlmOnError`.
 * - `AiEdgeLlm.cancel(requestId)` — stops the in-flight generation.
 * - `AiEdgeLlm.newConversation()` — reserved (context is shared with the app; reset from the app).
 *
 * @param activeModel returns the currently selected model (or null if none).
 * @param isModelReady whether the given model is initialized and ready to run.
 * @param scope a coroutine scope tied to the hosting screen (cancelled on leave).
 * @param webViewProvider returns the live WebView used to push results to the page.
 */
class DashChatLlmBridge(
  private val activeModel: () -> Model?,
  private val isModelReady: (Model) -> Boolean,
  private val scope: CoroutineScope,
  private val webViewProvider: () -> WebView?,
) {
  // Only one generation at a time (the engine runs a single conversation; this also avoids racing
  // with the app's own chat).
  @Volatile private var currentRequestId: String? = null

  @JavascriptInterface
  fun isReady(): Boolean {
    val model = activeModel()
    return model != null && isModelReady(model)
  }

  @JavascriptInterface
  fun sendPrompt(requestId: String, prompt: String) {
    val model = activeModel()
    if (model == null || !isModelReady(model)) {
      emit("window.aiEdgeLlmOnError", requestId, "모델이 아직 준비되지 않았어요. 앱에서 모델을 먼저 준비해 주세요.")
      return
    }
    if (currentRequestId != null) {
      emit("window.aiEdgeLlmOnError", requestId, "이미 답변을 생성 중이에요. 잠시 후 다시 시도해 주세요.")
      return
    }
    currentRequestId = requestId
    // runInference is async; launch on Main so the WebView callbacks are posted correctly.
    scope.launch(Dispatchers.Main) {
      val builder = StringBuilder()
      try {
        model.runtimeHelper.runInference(
          model = model,
          input = prompt,
          resultListener = { partial, done, _ ->
            // Ignore late callbacks from a superseded/cancelled request.
            if (currentRequestId == requestId) {
              if (!partial.startsWith("<ctrl")) {
                builder.append(partial)
                emit("window.aiEdgeLlmOnToken", requestId, partial)
              }
              if (done) {
                currentRequestId = null
                emit("window.aiEdgeLlmOnDone", requestId, builder.toString())
              }
            }
          },
          cleanUpListener = {},
          onError = { message ->
            currentRequestId = null
            emit("window.aiEdgeLlmOnError", requestId, message.ifEmpty { "문제가 발생했어요." })
          },
          coroutineScope = scope,
        )
      } catch (e: Exception) {
        Log.e(TAG, "Dash Chat inference failed", e)
        currentRequestId = null
        emit("window.aiEdgeLlmOnError", requestId, e.message ?: "추론에 실패했어요.")
      }
    }
  }

  @JavascriptInterface
  fun cancel(requestId: String) {
    val model = activeModel() ?: return
    runCatching { model.runtimeHelper.stopResponse(model) }
    if (currentRequestId == requestId) currentRequestId = null
  }

  @JavascriptInterface
  fun newConversation() {
    // Context is shared with the app; a hard reset here would wipe the app's chat, so this is a
    // no-op by design. Reset the conversation from the app's chat screen instead.
    Log.d(TAG, "newConversation() requested (no-op: context shared with app).")
  }

  /** Stops any in-flight generation (called when the hosting screen goes away). */
  fun stop() {
    val id = currentRequestId ?: return
    cancel(id)
  }

  /** Pushes a JS callback `fn(requestId, payload)` onto the page, on the WebView's thread. */
  private fun emit(fn: String, requestId: String, payload: String) {
    val wv = webViewProvider() ?: return
    val js = "if ($fn) $fn(${JSONObject.quote(requestId)}, ${JSONObject.quote(payload)});"
    wv.post { wv.evaluateJavascript(js, null) }
  }
}
