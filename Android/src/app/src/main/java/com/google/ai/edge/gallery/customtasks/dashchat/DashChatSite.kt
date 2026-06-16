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
import android.util.Log
import android.webkit.WebStorage
import android.webkit.WebView
import com.google.ai.edge.gallery.common.LOCAL_URL_BASE
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.ZipInputStream

private const val TAG = "AGDashChatSite"

/**
 * Clears the WebView's cached resources and web storage so a freshly re-downloaded site (served at
 * the same local URL) is never shadowed by stale cached assets/state. Must be called on the main
 * thread (it briefly creates a WebView).
 */
fun clearDashChatWebCache(context: Context) {
  runCatching {
    WebView(context).apply {
      clearCache(true)
      clearHistory()
      destroy()
    }
  }
  runCatching { WebStorage.getInstance().deleteAllData() }
}

/**
 * Downloads, unpacks and locates the "대쉬 챗(Dash Chat)" web build — a zip of a compiled website that
 * is fetched like a model, extracted into app storage, and then browsed locally in a WebView.
 *
 * The extracted site lives under `filesDir/dashchat/`, which [BaseGalleryWebViewClient]'s asset
 * loader serves at `$LOCAL_URL_BASE/dashchat/…`. Until the user downloads a site, a small bundled
 * sample under `assets/dashchat/` (served at `$LOCAL_URL_BASE/assets/dashchat/…`) is used so the
 * page works out of the box and documents the JS bridge contract.
 */
object DashChatSite {
  /** The hosted web-build zip. Replace to ship a different site. */
  const val SITE_URL = "https://kr.object.ncloudstorage.com/llm-models/sites-z/sites-0001.zip"

  private const val DIR = "dashchat"
  private const val INDEX = "index.html"
  private const val ZIP_CACHE = "dashchat_site.zip"

  /** Directory the downloaded site is extracted into. */
  fun siteDir(context: Context): File = File(context.filesDir, DIR)

  /** True once a downloaded site (with an index.html) is present. */
  fun isInstalled(context: Context): Boolean = File(siteDir(context), INDEX).exists()

  /**
   * The url to load: the downloaded site if installed, otherwise the bundled sample. Both resolve
   * through the WebView asset loader so they are same-origin and may use the JS bridge.
   */
  fun indexUrl(context: Context): String =
    if (isInstalled(context)) "$LOCAL_URL_BASE/$DIR/$INDEX"
    else "$LOCAL_URL_BASE/assets/$DIR/$INDEX"

  /**
   * Removes everything the site download leaves on disk: the extracted site and the cached zip.
   * Pair with [clearDashChatWebCache] to also drop the WebView's HTTP/asset cache and web storage,
   * so a re-download of a new version (same URL) is never served stale content.
   */
  fun clearAll(context: Context) {
    runCatching { siteDir(context).deleteRecursively() }
    runCatching { File(context.cacheDir, ZIP_CACHE).delete() }
  }

  /**
   * Downloads [SITE_URL] and extracts it into [siteDir], reporting download progress (0..100, or -1
   * when the total size is unknown). Blocking — call on [kotlinx.coroutines.Dispatchers.IO]. Returns
   * an error message on failure, or null on success.
   */
  fun downloadAndInstall(context: Context, onProgress: (Int) -> Unit): String? {
    val tmp = File(context.cacheDir, ZIP_CACHE)
    return try {
      // 1) Download the zip.
      val conn = (URL(SITE_URL).openConnection() as HttpURLConnection).apply {
        requestMethod = "GET"
        connectTimeout = 20_000
        readTimeout = 60_000
        instanceFollowRedirects = true
        setRequestProperty("User-Agent", "Mozilla/5.0 (Android) BeF-Ai/1.0")
      }
      val code = conn.responseCode
      if (code != HttpURLConnection.HTTP_OK) {
        return "다운로드 실패 (HTTP $code)"
      }
      val total = conn.contentLengthLong
      conn.inputStream.use { input ->
        FileOutputStream(tmp).use { out ->
          val buffer = ByteArray(8192)
          var received = 0L
          var len: Int
          while (input.read(buffer).also { len = it } > 0) {
            out.write(buffer, 0, len)
            received += len
            onProgress(if (total > 0L) ((received * 100) / total).toInt().coerceIn(0, 100) else -1)
          }
        }
      }
      // 2) Extract into a clean site directory.
      val dest = siteDir(context)
      dest.deleteRecursively()
      dest.mkdirs()
      if (!extractZip(tmp, dest)) {
        return "압축 해제에 실패했어요."
      }
      if (!File(dest, INDEX).exists()) {
        // Some builds nest everything under a single top folder; if so, hoist it.
        hoistSingleRootIfNeeded(dest)
      }
      if (!File(dest, INDEX).exists()) {
        return "사이트에 index.html이 없어요."
      }
      null
    } catch (e: Exception) {
      Log.e(TAG, "Dash Chat site install failed", e)
      e.message ?: "다운로드 중 오류가 발생했어요."
    } finally {
      runCatching { tmp.delete() }
    }
  }

  /**
   * If the zip extracted into a single top-level folder (e.g. `site/index.html`) rather than at the
   * root, move that folder's contents up so `index.html` sits directly in [dest].
   */
  private fun hoistSingleRootIfNeeded(dest: File) {
    val children = dest.listFiles() ?: return
    val onlyDir = children.singleOrNull { it.isDirectory } ?: return
    if (children.size == 1 && File(onlyDir, INDEX).exists()) {
      onlyDir.listFiles()?.forEach { child ->
        child.renameTo(File(dest, child.name))
      }
      onlyDir.deleteRecursively()
    }
  }

  /** Extracts a `.zip` into [destDir], guarding against path traversal ("zip slip"). */
  private fun extractZip(zip: File, destDir: File): Boolean {
    val canonicalDest = destDir.canonicalFile
    return try {
      ZipInputStream(BufferedInputStream(zip.inputStream())).use { zis ->
        val buffer = ByteArray(8192)
        var entry = zis.nextEntry
        while (entry != null) {
          val outFile = File(canonicalDest, entry.name)
          if (!outFile.canonicalPath.startsWith(canonicalDest.canonicalPath + File.separator)) {
            Log.w(TAG, "Skipping suspicious entry: ${entry.name}")
            entry = zis.nextEntry
            continue
          }
          if (entry.isDirectory) {
            outFile.mkdirs()
          } else {
            outFile.parentFile?.mkdirs()
            FileOutputStream(outFile).use { out ->
              var len: Int
              while (zis.read(buffer).also { len = it } > 0) {
                out.write(buffer, 0, len)
              }
            }
          }
          entry = zis.nextEntry
        }
      }
      true
    } catch (e: Exception) {
      Log.e(TAG, "Failed to extract ${zip.name}", e)
      false
    }
  }
}
