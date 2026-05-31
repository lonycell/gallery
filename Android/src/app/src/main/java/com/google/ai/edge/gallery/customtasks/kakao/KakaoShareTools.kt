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
package com.google.ai.edge.gallery.customtasks.kakao

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.ai.edge.litertlm.Tool
import com.google.ai.edge.litertlm.ToolParam
import com.google.ai.edge.litertlm.ToolSet

private const val TAG = "AGKakaoShareTools"
private const val KAKAO_TALK_PACKAGE = "com.kakao.talk"

/**
 * EXAMPLE: a function-calling tool that sends a KakaoTalk message via the share intent.
 *
 * Design rationale (see customtasks/kakao/README.md): KakaoTalk does not allow an app to silently
 * send a message to an arbitrary friend, so this tool composes the message and hands it to the
 * KakaoTalk app through Android's `ACTION_SEND` share intent. KakaoTalk then shows its own
 * chat-picker UI where the user chooses the recipient and confirms sending. That confirmation step
 * is exactly what we want for a voice assistant: sending a message is an irreversible outbound
 * action, so a human stays in the loop.
 *
 * This needs no Kakao SDK, no login, and no special permission (only `<queries>` visibility for the
 * KakaoTalk package in the manifest, on Android 11+).
 *
 * The model decides WHEN to call this; the `@Tool`/`@ToolParam` descriptions teach it. The
 * `recipient` is passed for the model's/UI's context only — the actual recipient is chosen by the
 * user in KakaoTalk.
 *
 * @param context used to start the share intent. An application context is fine (we add
 *   `FLAG_ACTIVITY_NEW_TASK`).
 * @param onShared optional hook (analytics / "opening KakaoTalk…" status in your UI).
 */
class KakaoShareTools(
  private val context: Context,
  private val onShared: (recipient: String) -> Unit = {},
) : ToolSet {

  @Tool(
    description =
      "Sends a message via KakaoTalk. Call this only when the user clearly asks to send/forward a " +
        "KakaoTalk (카톡) message. It opens KakaoTalk's share screen with the composed text; the " +
        "user then picks the recipient and confirms sending. Confirm the recipient and summarize " +
        "the message to the user before calling this."
  )
  fun sendKakaoMessage(
    @ToolParam(description = "The intended recipient's name, for context (user selects in KakaoTalk).")
    recipient: String,
    @ToolParam(description = "The message body to send.") message: String,
  ): Map<String, String> {
    if (message.isBlank()) {
      return mapOf("status" to "failed", "error" to "Message body is empty")
    }
    Log.d(TAG, "sendKakaoMessage to '$recipient'")
    val intent =
      Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        setPackage(KAKAO_TALK_PACKAGE)
        putExtra(Intent.EXTRA_TEXT, message)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }
    return try {
      context.startActivity(intent)
      onShared(recipient)
      // "shared" — not "sent": the user still confirms sending inside KakaoTalk.
      mapOf(
        "status" to "shared",
        "recipient" to recipient,
        "note" to "KakaoTalk opened; ask the user to pick the recipient and confirm sending.",
      )
    } catch (e: ActivityNotFoundException) {
      Log.w(TAG, "KakaoTalk not installed", e)
      mapOf("status" to "failed", "error" to "KakaoTalk is not installed on this device")
    } catch (e: Exception) {
      Log.e(TAG, "Failed to open KakaoTalk share", e)
      mapOf("status" to "failed", "error" to (e.message ?: "Unknown error"))
    }
  }
}
