/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of data/Consts.kt

import Foundation
import UIKit

// Keys used to send/receive data to the download worker.
let KEY_MODEL_URL = "KEY_MODEL_URL"
let KEY_MODEL_NAME = "KEY_MODEL_NAME"
let KEY_MODEL_COMMIT_HASH = "KEY_MODEL_COMMIT_HASH"
let KEY_MODEL_DOWNLOAD_MODEL_DIR = "KEY_MODEL_DOWNLOAD_MODEL_DIR"
let KEY_MODEL_DOWNLOAD_FILE_NAME = "KEY_MODEL_DOWNLOAD_FILE_NAME"
let KEY_MODEL_TOTAL_BYTES = "KEY_MODEL_TOTAL_BYTES"
let KEY_MODEL_DOWNLOAD_RECEIVED_BYTES = "KEY_MODEL_DOWNLOAD_RECEIVED_BYTES"
let KEY_MODEL_DOWNLOAD_RATE = "KEY_MODEL_DOWNLOAD_RATE"
let KEY_MODEL_DOWNLOAD_REMAINING_MS = "KEY_MODEL_DOWNLOAD_REMAINING_SECONDS"
let KEY_MODEL_DOWNLOAD_ERROR_MESSAGE = "KEY_MODEL_DOWNLOAD_ERROR_MESSAGE"
let KEY_MODEL_DOWNLOAD_ACCESS_TOKEN = "KEY_MODEL_DOWNLOAD_ACCESS_TOKEN"
let KEY_MODEL_EXTRA_DATA_URLS = "KEY_MODEL_EXTRA_DATA_URLS"
let KEY_MODEL_EXTRA_DATA_DOWNLOAD_FILE_NAMES = "KEY_MODEL_EXTRA_DATA_DOWNLOAD_FILE_NAMES"
let KEY_MODEL_IS_ZIP = "KEY_MODEL_IS_ZIP"
let KEY_MODEL_UNZIPPED_DIR = "KEY_MODEL_UNZIPPED_DIR"
let KEY_MODEL_START_UNZIPPING = "KEY_MODEL_START_UNZIPPING"

// Default values for LLM models.
let DEFAULT_MAX_TOKEN = 1024
let DEFAULT_TOPK = 64
let DEFAULT_TOPP: Float = 0.95
let DEFAULT_TEMPERATURE: Float = 1.0
let DEFAULT_ACCELERATORS: [Accelerator] = [.gpu]
let DEFAULT_VISION_ACCELERATOR: Accelerator = .gpu

// Max number of images allowed in an "ask image" session.
let MAX_IMAGE_COUNT = 10
// Max number of images allowed in a "ask image" session for AI Core.
let MAX_IMAGE_COUNT_AI_CORE = 1
// Max number of skills recommended in an "agent skills" session.
let MAX_RECOMMENDED_SKILL_COUNT = 15
// Max number of audio clips in an "ask audio" session.
let MAX_AUDIO_CLIP_COUNT = 1
// Max audio clip duration in seconds.
let MAX_AUDIO_CLIP_DURATION_SEC = 30
// Audio-recording related consts.
let SAMPLE_RATE = 16000

// The size of the icon shown under each model name in the model list screen.
let MODEL_INFO_ICON_SIZE: CGFloat = 18
// The extension of the tmp download files.
let TMP_FILE_EXT = "gallerytmp"

// Current device's SOC in lowercase (best-effort on iOS).
let SOC: String = {
  var sysinfo = utsname()
  uname(&sysinfo)
  let machine = withUnsafeBytes(of: &sysinfo.machine) { raw -> String in
    let ptr = raw.bindMemory(to: CChar.self).baseAddress!
    return String(cString: ptr)
  }
  return machine.lowercased()
}()

// URLs for Agent Skills.
enum AgentSkillsURLs {
  static let REPOSITORY = "https://github.com/google-ai-edge/gallery/tree/main/skills"
  static let DISCUSSIONS = "https://github.com/google-ai-edge/gallery/discussions/categories/skills"
}
