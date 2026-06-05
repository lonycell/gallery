// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/speech/WhisperNeuralStt.kt

import Foundation

// MARK: - Constants

/// Model name for the downloadable Whisper small multilingual STT model. Matches `SttTask`.
let WHISPER_KO_STT_MODEL_NAME = "Whisper small (multilingual)"

// File layout of the sherpa-onnx multilingual Whisper `small` model (int8).
let WHISPER_SMALL_ENCODER = "small-encoder.int8.onnx"
let WHISPER_SMALL_DECODER = "small-decoder.int8.onnx"
let WHISPER_SMALL_TOKENS  = "small-tokens.txt"

// MARK: - WhisperNeuralStt

/// Loads a downloadable multilingual Whisper recognizer (shared with the STT task).
///
/// NOTE: On Android this constructed a `sherpa-onnx` `OfflineRecognizer` configured
/// for Whisper (split encoder/decoder int8 `.onnx` + `tokens.txt`, no archive to unpack).
/// On iOS, no sherpa-onnx pod is available.
///
/// Bridge point: when a real sherpa-onnx / CoreML Whisper model is ready,
/// 1. Locate encoder, decoder, and tokens files via `model.getPath(fileName:)`.
/// 2. Construct a `NeuralSttEngine` implementation (conforming to `NeuralSttEngine`) and
///    return `.success(engine)`.
enum WhisperNeuralStt {
  static func load(
    model: Model,
    encoderFileName: String = WHISPER_SMALL_ENCODER,
    decoderFileName: String = WHISPER_SMALL_DECODER,
    tokensFileName: String  = WHISPER_SMALL_TOKENS,
    language: String = "ko"
  ) -> NeuralSttLoadResult {
    let encoderPath = model.getPath(fileName: encoderFileName)
    let encoder = FileManager.default.fileExists(atPath: encoderPath)
      ? encoderPath
      : model.getPath()
    let decoder = model.getPath(fileName: decoderFileName)
    let tokens  = model.getPath(fileName: tokensFileName)

    guard FileManager.default.fileExists(atPath: encoder),
          FileManager.default.fileExists(atPath: decoder),
          FileManager.default.fileExists(atPath: tokens) else {
      return .notDownloaded
    }

    // NOTE: Real Whisper engine construction is not yet implemented.
    // Return the SFSpeechRecognizer fallback so the STT screen remains usable.
    let locale = language.isEmpty || language == "auto"
      ? Locale(identifier: "ko-KR")
      : Locale(identifier: language)
    let engine = SFSpeechRecognizerSttEngine(locale: locale)
    return .success(engine)
  }
}
