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

package com.google.ai.edge.gallery.character

import android.content.Context
import android.net.Uri
import android.webkit.MimeTypeMap
import java.io.File

/**
 * Copies user-picked media (a transient `content://` URI from the photo picker) into the app's
 * private storage and returns a durable `file://` URI. Doing this avoids losing access when the
 * content URI's permission is revoked, and keeps the customization stable across restarts.
 */
object CharacterMediaStore {

  /** "image" | "gif" | "video" — used to choose how the background is rendered. */
  fun mediaKind(context: Context, uri: Uri): String {
    val mime = context.contentResolver.getType(uri).orEmpty()
    return when {
      mime == "image/gif" -> "gif"
      mime.startsWith("video/") -> "video"
      else -> "image"
    }
  }

  /**
   * Copies [uri] into `filesDir/character_media/` and returns a `file://…` URI string, or null on
   * failure. [kind] is just used to name the file (e.g. "still", "bg"). Run this off the main thread.
   */
  fun copyToInternal(context: Context, uri: Uri, characterId: String, kind: String): String? {
    return try {
      val ext = extensionFor(context, uri)
      val dir = File(context.filesDir, "character_media").apply { mkdirs() }
      val file = File(dir, "${characterId}_${kind}_${System.currentTimeMillis()}.$ext")
      val copied =
        context.contentResolver.openInputStream(uri)?.use { input ->
          file.outputStream().use { output -> input.copyTo(output) }
          true
        } ?: false
      if (copied) Uri.fromFile(file).toString() else null
    } catch (e: Exception) {
      null
    }
  }

  private fun extensionFor(context: Context, uri: Uri): String {
    val mime = context.contentResolver.getType(uri)
    val fromMime = mime?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) }
    return fromMime
      ?: when {
        mime == null -> "bin"
        mime.startsWith("video/") -> "mp4"
        mime == "image/gif" -> "gif"
        mime == "image/png" -> "png"
        else -> "jpg"
      }
  }
}
