/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of Analytics.kt
//
// The Android app logs to Firebase Analytics. iOS keeps the same event taxonomy
// behind a thin, no-op-by-default logger so call sites stay identical. Wire a
// real Firebase iOS SDK into `Analytics.log` to enable reporting.

import Foundation

enum GalleryEvent: String {
  case capabilitySelect = "capability_select"
  case modelDownload = "model_download"
  case generateAction = "generate_action"
  case buttonClicked = "button_clicked"
  case skillManagement = "skill_management"
  case skillExecution = "skill_execution"
  case chatHistory = "chat_history"
  case mcpManagement = "mcp_management"
  case mcpExecution = "mcp_execution"
}

/// Mirrors the global `firebaseAnalytics?.logEvent(...)` call sites.
enum Analytics {
  static func log(_ event: GalleryEvent, params: [String: Any] = [:]) {
    galleryLog("AGAnalytics", "event=\(event.rawValue) params=\(params)")
  }
}
