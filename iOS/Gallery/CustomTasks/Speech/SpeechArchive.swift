// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/speech/SpeechArchive.kt

import Foundation

/// Extracts a `.tar.bz2` archive into `destDir`.
///
/// Several sherpa-onnx speech models ship as a single `.tar.bz2` bundle
/// because they carry a whole `espeak-ng-data` directory of hundreds of files.
/// The app's standard downloader can fetch the single archive with a progress bar;
/// this helper then unpacks it once during model initialization.
///
/// NOTE: On Android this used Apache Commons Compress
/// (`TarArchiveInputStream` + `BZip2CompressorInputStream`).
/// iOS has no bundled bzip2 tar extractor in the standard frameworks.
/// To enable real archive extraction, link `libarchive` (available via a
/// Swift Package or CocoaPod) and replace the body of this function with:
///
///   ```swift
///   // import CArchive  // or use Process to shell out to `tar`
///   let result = archive_read_new()
///   archive_read_support_filter_bzip2(result)
///   archive_read_support_format_tar(result)
///   // … iterate entries, guard against path traversal, write files …
///   ```
///
/// Until that bridge is in place the function always returns `false` and
/// callers treat the model as not extracted yet.
///
/// Path-traversal guard: any entry whose resolved path falls outside `destDir`
/// must be skipped (matches Android's "zip slip" check).
///
/// - Parameters:
///   - archive: The `.tar.bz2` file.
///   - destDir: Directory to extract into.
///   - onProgress: Optional callback with the number of entries processed so far.
/// - Returns: `true` if extraction completed, `false` on failure.
@discardableResult
func extractTarBz2(
  archive: URL,
  destDir: URL,
  onProgress: ((Int) -> Void)? = nil
) -> Bool {
  // NOTE: Real tar.bz2 extraction is not implemented.
  // See the doc-comment above for the integration path.
  return false
}
