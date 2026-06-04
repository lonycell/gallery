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

package com.google.ai.edge.gallery.customtasks.websearch

import android.util.Log
import com.google.ai.edge.gallery.customtasks.agentchat.AgentTools
import com.google.ai.edge.litertlm.Tool
import com.google.ai.edge.litertlm.ToolParam
import com.google.ai.edge.litertlm.ToolSet
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import org.json.JSONArray
import org.json.JSONObject

private const val TAG = "AGWebSearch"

/**
 * A built-in function-calling tool that lets the assistant look things up on the internet.
 *
 * It uses DuckDuckGo's key-free Instant Answer API so it works out of the box; a real search API
 * (with a key) can be substituted later. While searching it reports progress through [agentTools] so
 * the chat can show a "searching…" status, and it returns the results as text for the model to
 * summarize (and then speak).
 */
class WebSearchTools(private val agentTools: AgentTools? = null) : ToolSet {

  @Tool(
    description =
      "Searches the public internet for up-to-date information and returns the top results as text. " +
        "Call this whenever the user asks about current events, recent news, today's facts, prices, " +
        "schedules, or anything time-sensitive that you may not reliably know. After getting the " +
        "results, summarize them concisely in the user's language — the reply is read aloud, so keep " +
        "it short and natural, and mention if the information may be incomplete."
  )
  fun searchWeb(
    @ToolParam(description = "The search query, phrased for a search engine, in the user's language.")
    query: String
  ): Map<String, String> {
    if (query.isBlank()) {
      return mapOf("status" to "failed", "error" to "empty query")
    }
    agentTools?.postProgress("인터넷 검색 중…", true)
    return try {
      val results = WebSearch.search(query)
      if (results.isBlank()) {
        mapOf("status" to "empty", "note" to "No relevant results were found.")
      } else {
        mapOf("status" to "ok", "query" to query, "results" to results)
      }
    } catch (e: Exception) {
      Log.w(TAG, "Web search failed", e)
      mapOf("status" to "failed", "error" to (e.message ?: "search failed"))
    } finally {
      agentTools?.postProgress("", false)
    }
  }
}

/** Key-free web search backed by DuckDuckGo's Instant Answer API. */
object WebSearch {
  private const val MAX_RELATED = 6

  fun search(query: String): String {
    val q = URLEncoder.encode(query, "UTF-8")
    val url =
      URL("https://api.duckduckgo.com/?q=$q&format=json&no_html=1&no_redirect=1&skip_disambig=1")
    val conn = (url.openConnection() as HttpURLConnection).apply {
      requestMethod = "GET"
      connectTimeout = 12_000
      readTimeout = 20_000
      setRequestProperty("User-Agent", "Mozilla/5.0 (Android) BeF-Ai/1.0")
      setRequestProperty("Accept", "application/json")
    }
    val code = conn.responseCode
    if (code != HttpURLConnection.HTTP_OK) {
      Log.w(TAG, "DuckDuckGo HTTP $code")
      return ""
    }
    val text = conn.inputStream.use { String(it.readBytes(), Charsets.UTF_8) }
    return parse(JSONObject(text))
  }

  private fun parse(json: JSONObject): String {
    val sb = StringBuilder()
    val abstract = json.optString("AbstractText").ifBlank { json.optString("Abstract") }
    if (abstract.isNotBlank()) sb.append(abstract).append('\n')
    val answer = json.optString("Answer")
    if (answer.isNotBlank()) sb.append(answer).append('\n')
    val definition = json.optString("Definition")
    if (definition.isNotBlank()) sb.append(definition).append('\n')

    var count = 0
    val related = json.optJSONArray("RelatedTopics")
    if (related != null) {
      var i = 0
      while (i < related.length() && count < MAX_RELATED) {
        val item = related.optJSONObject(i)
        if (item != null) {
          val itemText = item.optString("Text")
          if (itemText.isNotBlank()) {
            sb.append("- ").append(itemText).append('\n')
            count++
          } else {
            count += appendTopics(item.optJSONArray("Topics"), sb, MAX_RELATED - count)
          }
        }
        i++
      }
    }
    return sb.toString().trim()
  }

  private fun appendTopics(topics: JSONArray?, sb: StringBuilder, remaining: Int): Int {
    if (topics == null || remaining <= 0) return 0
    var added = 0
    var j = 0
    while (j < topics.length() && added < remaining) {
      val t = topics.optJSONObject(j)?.optString("Text").orEmpty()
      if (t.isNotBlank()) {
        sb.append("- ").append(t).append('\n')
        added++
      }
      j++
    }
    return added
  }
}
