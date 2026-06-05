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

/**
 * Key-free web search. Primary source is DuckDuckGo's HTML ("lite") endpoint, which returns real
 * organic results for general queries (unlike the Instant Answer API, which is empty for most
 * searches). When that yields nothing, it falls back to the Wikipedia search API for a factual
 * summary. Both are best-effort and parsed defensively; any failure returns "" so the caller reports
 * "no results" rather than crashing.
 */
object WebSearch {
  private const val MAX_RESULTS = 6
  private const val UA = "Mozilla/5.0 (Android) BeF-Ai/1.0"

  fun search(query: String): String {
    val fromDuck = runCatching { searchDuckDuckGoHtml(query) }.getOrElse { e ->
      Log.w(TAG, "DuckDuckGo HTML search failed", e)
      ""
    }
    if (fromDuck.isNotBlank()) return fromDuck
    // Fallback: Wikipedia search (robust for factual / entity queries).
    return runCatching { searchWikipedia(query) }.getOrElse { e ->
      Log.w(TAG, "Wikipedia search failed", e)
      ""
    }
  }

  // --- DuckDuckGo HTML (lite) ---

  // The lite page renders each result as a link followed by a snippet table cell. We pull the
  // visible link text (title) and the adjacent snippet, strip tags/entities, and list a few.
  private val linkRegex =
    Regex("""<a[^>]*class="result-link"[^>]*>(.*?)</a>""", RegexOption.DOT_MATCHES_ALL)
  private val snippetRegex =
    Regex("""<td[^>]*class="result-snippet"[^>]*>(.*?)</td>""", RegexOption.DOT_MATCHES_ALL)
  private val tagRegex = Regex("""<[^>]+>""")

  private fun searchDuckDuckGoHtml(query: String): String {
    val q = URLEncoder.encode(query, "UTF-8")
    val url = URL("https://lite.duckduckgo.com/lite/?q=$q")
    val conn = (url.openConnection() as HttpURLConnection).apply {
      requestMethod = "GET"
      connectTimeout = 12_000
      readTimeout = 20_000
      instanceFollowRedirects = true
      setRequestProperty("User-Agent", UA)
      setRequestProperty("Accept", "text/html")
      setRequestProperty("Accept-Language", "ko,en;q=0.8")
    }
    val code = conn.responseCode
    if (code != HttpURLConnection.HTTP_OK) {
      Log.w(TAG, "DuckDuckGo lite HTTP $code")
      return ""
    }
    val html = conn.inputStream.use { String(it.readBytes(), Charsets.UTF_8) }
    val titles = linkRegex.findAll(html).map { cleanHtml(it.groupValues[1]) }.toList()
    val snippets = snippetRegex.findAll(html).map { cleanHtml(it.groupValues[1]) }.toList()

    val sb = StringBuilder()
    var count = 0
    var i = 0
    while (i < titles.size && count < MAX_RESULTS) {
      val title = titles[i]
      val snippet = snippets.getOrNull(i).orEmpty()
      if (title.isNotBlank() || snippet.isNotBlank()) {
        sb.append("- ")
        if (title.isNotBlank()) sb.append(title)
        if (snippet.isNotBlank()) {
          if (title.isNotBlank()) sb.append(": ")
          sb.append(snippet)
        }
        sb.append('\n')
        count++
      }
      i++
    }
    return sb.toString().trim()
  }

  // --- Wikipedia search fallback ---

  private fun searchWikipedia(query: String): String {
    val lang = if (containsHangul(query)) "ko" else "en"
    val q = URLEncoder.encode(query, "UTF-8")
    val url =
      URL(
        "https://$lang.wikipedia.org/w/api.php?action=query&list=search&srsearch=$q" +
          "&srlimit=$MAX_RESULTS&format=json&utf8=1"
      )
    val conn = (url.openConnection() as HttpURLConnection).apply {
      requestMethod = "GET"
      connectTimeout = 12_000
      readTimeout = 20_000
      setRequestProperty("User-Agent", UA)
      setRequestProperty("Accept", "application/json")
    }
    if (conn.responseCode != HttpURLConnection.HTTP_OK) {
      Log.w(TAG, "Wikipedia HTTP ${conn.responseCode}")
      return ""
    }
    val text = conn.inputStream.use { String(it.readBytes(), Charsets.UTF_8) }
    val results = JSONObject(text).optJSONObject("query")?.optJSONArray("search") ?: return ""
    val sb = StringBuilder()
    var i = 0
    while (i < results.length() && i < MAX_RESULTS) {
      val item = results.optJSONObject(i)
      val title = item?.optString("title").orEmpty()
      val snippet = cleanHtml(item?.optString("snippet").orEmpty())
      if (title.isNotBlank()) {
        sb.append("- ").append(title)
        if (snippet.isNotBlank()) sb.append(": ").append(snippet)
        sb.append('\n')
      }
      i++
    }
    return sb.toString().trim()
  }

  /** Strips HTML tags and decodes the few entities the sources commonly emit. */
  private fun cleanHtml(raw: String): String =
    tagRegex
      .replace(raw, "")
      .replace("&amp;", "&")
      .replace("&lt;", "<")
      .replace("&gt;", ">")
      .replace("&quot;", "\"")
      .replace("&#39;", "'")
      .replace("&nbsp;", " ")
      .replace(Regex("""\s+"""), " ")
      .trim()

  private fun containsHangul(text: String): Boolean =
    text.any { it.code in 0xAC00..0xD7A3 || it.code in 0x1100..0x11FF || it.code in 0x3130..0x318F }
}
