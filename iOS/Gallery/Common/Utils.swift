/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Partial port of common/Utils.kt + ui/common/Utils.kt — shared helpers.
// (UI-specific formatting helpers also live here; feature agents extend this.)

import Foundation
import SwiftUI

/// Central place for the app's private file locations. On Android these came from
/// `context.getExternalFilesDir(null)`; on iOS we use Application Support.
enum FileSystem {
  static let appFilesDir: URL = {
    let fm = FileManager.default
    let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = base.appendingPathComponent("gallery", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }()

  static let cachesDir: URL =
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!

  static func ensureDir(_ url: URL) {
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
}

private let TAG = "AGUtils"

/// Convert a model's size in bytes into a human readable string (e.g. "1.2 GB").
func readableFileSize(_ bytes: Int64, si: Bool = true) -> String {
  let unit: Int64 = si ? 1000 : 1024
  if bytes < unit { return "\(bytes) B" }
  let exp = Int(log(Double(bytes)) / log(Double(unit)))
  let pre = (si ? "kMGTPE" : "KMGTPE")
  let idx = pre.index(pre.startIndex, offsetBy: exp - 1)
  let prefix = String(pre[idx]) + (si ? "" : "i")
  return String(format: "%.1f %@B", Double(bytes) / pow(Double(unit), Double(exp)), prefix)
}

/// Format milliseconds as a latency string (e.g. "1.23 s").
func latencyString(_ latencyMs: Float) -> String {
  if latencyMs < 0 { return "" }
  return String(format: "%.2f s", latencyMs / 1000.0)
}

/// Wall-clock milliseconds since the epoch (replacement for System.currentTimeMillis()).
func currentTimeMillis() -> Int64 {
  Int64(Date().timeIntervalSince1970 * 1000)
}

extension View {
  /// Conditionally apply a transform, mirroring common Compose `if` modifiers.
  @ViewBuilder func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
    if condition { transform(self) } else { self }
  }
}

private let logEnabled = true
func galleryLog(_ tag: String, _ message: String) {
  if logEnabled { print("[\(tag)] \(message)") }
}
