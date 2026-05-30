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

import android.util.Log
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream

private const val TAG = "AGSpeechArchive"

/**
 * Extracts a `.tar.bz2` archive into [destDir].
 *
 * Several sherpa-onnx speech models (e.g. the Korean VITS voice) ship as a single `.tar.bz2` bundle
 * because they carry a whole `espeak-ng-data` directory of hundreds of files. The app's standard
 * downloader can fetch the single archive file with a progress bar; this helper then unpacks it
 * once during model initialization.
 *
 * Extraction is guarded against path traversal ("zip slip"): any entry that would resolve outside
 * [destDir] is skipped.
 *
 * @return true if extraction completed (or was already complete), false on failure.
 */
fun extractTarBz2(archive: File, destDir: File): Boolean {
  if (!archive.exists()) {
    Log.e(TAG, "Archive does not exist: ${archive.absolutePath}")
    return false
  }
  if (!destDir.exists()) {
    destDir.mkdirs()
  }
  val canonicalDest = destDir.canonicalFile

  return try {
    TarArchiveInputStream(
        BZip2CompressorInputStream(BufferedInputStream(FileInputStream(archive)))
      )
      .use { tar ->
        val buffer = ByteArray(8192)
        var entry = tar.nextEntry
        while (entry != null) {
          val outFile = File(canonicalDest, entry.name)
          // Guard against path traversal.
          if (!outFile.canonicalPath.startsWith(canonicalDest.canonicalPath + File.separator)) {
            Log.w(TAG, "Skipping suspicious entry: ${entry.name}")
            entry = tar.nextEntry
            continue
          }
          if (entry.isDirectory) {
            outFile.mkdirs()
          } else {
            outFile.parentFile?.mkdirs()
            FileOutputStream(outFile).use { out ->
              var len: Int
              while (tar.read(buffer).also { len = it } > 0) {
                out.write(buffer, 0, len)
              }
            }
          }
          entry = tar.nextEntry
        }
      }
    true
  } catch (e: Exception) {
    Log.e(TAG, "Failed to extract ${archive.name}", e)
    false
  }
}
