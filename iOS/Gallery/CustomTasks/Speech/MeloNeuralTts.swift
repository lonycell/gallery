// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/speech/MeloNeuralTts.kt

import Foundation

// MARK: - Constants

/// Model name for the downloadable MeloTTS Korean voice. Matches `TtsTask`.
let MELO_TTS_MODEL_NAME = "MeloTTS (ko)"

let MELO_TTS_DIR      = "vits-melo-tts-ko"
let MELO_TTS_ONNX     = "model.onnx"
let MELO_TTS_TOKENS   = "tokens.txt"
let MELO_TTS_LEXICON  = "lexicon.txt"
let MELO_TTS_DICT_DIR = "dict"

/// Approximate archive entry count used for unpack progress rendering.
let MELO_TTS_ARCHIVE_ENTRY_COUNT = 600

// MARK: - MeloTtsLoadResult

/// The outcome of attempting to prepare/load the MeloTTS Korean neural voice.
/// Mirrors `MeloTtsLoadResult`.
enum MeloTtsLoadResult {
  case success(NeuralTtsEngine)
  case notDownloaded
  case failure(message: String, recoverable: Bool)
}

// MARK: - MeloNeuralTts

/// Loads the downloadable MeloTTS Korean neural voice (shared with the TTS task).
///
/// NOTE: On Android this unpacked a `.tar.bz2` archive and constructed a
/// `sherpa-onnx` VITS engine (`model.onnx + tokens.txt + lexicon.txt + dict/`).
/// On iOS, `extractTarBz2` is a stub and no sherpa-onnx pod is available.
///
/// Bridge point: when a real on-device MeloTTS / CoreML model is ready,
/// 1. Call `extractTarBz2(archive:destDir:onProgress:)` (implement in `SpeechArchive.swift`).
/// 2. Locate `model.onnx`, `tokens.txt`, `lexicon.txt`, `dict/` inside the extracted directory.
/// 3. Construct a `NeuralTtsEngine` backed by your ONNX / CoreML runtime and return `.success(engine)`.
enum MeloNeuralTts {
  static func load(
    model: Model,
    onUnpackProgress: ((Int) -> Void)? = nil,
    warmUp: Bool = true
  ) -> MeloTtsLoadResult {
    let archivePath = model.getPath()

    guard FileManager.default.fileExists(atPath: archivePath) else {
      return .notDownloaded
    }

    // NOTE: Real extraction and engine construction is not yet implemented.
    // Return the AVSpeechSynthesizer fallback so the TTS screen remains usable.
    let engine = AVSpeechSynthesizerTtsEngine(languageCode: "ko-KR")
    return .success(engine)
  }

  /// Deletes extracted MeloTTS files (not the archive) so a fresh extraction can be attempted.
  static func clearExtracted(model: Model) {
    let archivePath = model.getPath()
    let baseURL = URL(fileURLWithPath: archivePath).deletingLastPathComponent()
    let extractedRoot = baseURL.appendingPathComponent(MELO_TTS_DIR)
    try? FileManager.default.removeItem(at: extractedRoot)
  }
}
