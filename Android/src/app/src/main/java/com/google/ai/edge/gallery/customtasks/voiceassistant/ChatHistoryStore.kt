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

package com.google.ai.edge.gallery.customtasks.voiceassistant

import android.content.Context
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton
import org.json.JSONArray
import org.json.JSONObject

private const val TAG = "AGChatHistoryStore"
// Cap how many messages we keep per conversation so storage (and the restored LLM context) stay
// bounded.
private const val MAX_STORED_MESSAGES = 100

/**
 * Persists the voice chat history on disk, one conversation per character, as a small JSON file.
 *
 * Used both to restore the on-screen messages and to seed the LLM's context when a character is
 * (re)selected, so a conversation survives character switches and app restarts.
 */
@Singleton
class ChatHistoryStore @Inject constructor(@ApplicationContext private val context: Context) {

  private val dir: File by lazy {
    File(context.filesDir, "voice_chat_history").apply { mkdirs() }
  }

  private fun fileFor(conversationId: String): File {
    val safe = conversationId.replace(Regex("[^A-Za-z0-9_-]"), "_")
    return File(dir, "$safe.json")
  }

  /** Loads the stored messages for [conversationId] (empty if none). */
  fun load(conversationId: String): List<ChatMessage> {
    if (conversationId.isEmpty()) return emptyList()
    val file = fileFor(conversationId)
    if (!file.exists()) return emptyList()
    return try {
      val arr = JSONArray(file.readText())
      buildList {
        for (i in 0 until arr.length()) {
          val obj = arr.getJSONObject(i)
          val role =
            if (obj.getString("r") == "u") ChatMessage.Role.USER else ChatMessage.Role.ASSISTANT
          add(ChatMessage(role = role, text = obj.getString("t")))
        }
      }
    } catch (e: Exception) {
      Log.w(TAG, "Failed to load history for '$conversationId'", e)
      emptyList()
    }
  }

  /** Saves [messages] for [conversationId] (skips empty messages; keeps only the most recent ones). */
  fun save(conversationId: String, messages: List<ChatMessage>) {
    if (conversationId.isEmpty()) return
    try {
      val arr = JSONArray()
      for (message in messages.takeLast(MAX_STORED_MESSAGES)) {
        if (message.kind != ChatMessageKind.TEXT || message.text.isBlank()) continue
        arr.put(
          JSONObject()
            .put("r", if (message.role == ChatMessage.Role.USER) "u" else "a")
            .put("t", message.text)
        )
      }
      fileFor(conversationId).writeText(arr.toString())
    } catch (e: Exception) {
      Log.w(TAG, "Failed to save history for '$conversationId'", e)
    }
  }
}
