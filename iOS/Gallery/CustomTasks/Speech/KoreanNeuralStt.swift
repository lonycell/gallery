// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/speech/KoreanNeuralStt.kt

import Foundation
import Speech

// MARK: - Protocol surface

/// Protocol mirroring the capabilities of a sherpa-onnx `OfflineRecognizer`.
/// The working iOS default is `SFSpeechRecognizerSttEngine`; drop a real
/// Core ML / ONNX Runtime bridge class here when available.
protocol NeuralSttEngine: AnyObject {
  /// Transcribe mono float samples (16 kHz).
  /// Must be called off the main thread. Returns the transcript or empty string.
  func transcribe(samples: [Float], sampleRate: Int) async -> String
  /// Release any held resources.
  func release()
}

// MARK: - Load result

/// The outcome of attempting to prepare/load an STT engine. Mirrors `NeuralSttLoadResult`.
enum NeuralSttLoadResult {
  case success(NeuralSttEngine)
  case notDownloaded
  case failure(message: String, recoverable: Bool)
}

// MARK: - SFSpeechRecognizer fallback engine

/// Working iOS STT engine backed by `SFSpeechRecognizer`.
/// Used as the default while a real on-device model is not yet available.
///
/// NOTE: To replace with a real sherpa-onnx / CoreML model:
/// 1. Implement a `NeuralSttEngine` class that wraps your native recognizer.
/// 2. Return it from `KoreanNeuralStt.load()` instead of this class.
/// 3. Remove the `SFSpeechRecognizer` authorization call from `SttViewModel` if desired.
final class SFSpeechRecognizerSttEngine: NeuralSttEngine {
  private let locale: Locale

  init(locale: Locale = Locale(identifier: "ko-KR")) {
    self.locale = locale
  }

  func transcribe(samples: [Float], sampleRate: Int) async -> String {
    // NOTE: SFSpeechRecognizer requires audio files or live audio buffers;
    // it does not directly accept raw float arrays. This implementation
    // encodes the PCM samples into a temporary WAV file and feeds it to
    // the recognizer.
    guard let wavData = buildWav(samples: samples, sampleRate: sampleRate) else { return "" }
    return await withCheckedContinuation { continuation in
      let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".wav")
      do {
        try wavData.write(to: tmpURL)
      } catch {
        continuation.resume(returning: "")
        return
      }
      guard let recognizer = SFSpeechRecognizer(locale: locale),
            recognizer.isAvailable else {
        try? FileManager.default.removeItem(at: tmpURL)
        continuation.resume(returning: "")
        return
      }
      let request = SFSpeechURLRecognitionRequest(url: tmpURL)
      request.shouldReportPartialResults = false
      recognizer.recognitionTask(with: request) { result, error in
        try? FileManager.default.removeItem(at: tmpURL)
        continuation.resume(returning: result?.bestTranscription.formattedString ?? "")
      }
    }
  }

  func release() {}

  // MARK: WAV helper

  private func buildWav(samples: [Float], sampleRate: Int) -> Data? {
    let numSamples = samples.count
    let byteCount = numSamples * 2
    let headerSize = 44
    var data = Data(count: headerSize + byteCount)

    func write32(_ v: UInt32, at offset: Int) {
      data[offset]   = UInt8(v & 0xFF)
      data[offset+1] = UInt8((v >> 8) & 0xFF)
      data[offset+2] = UInt8((v >> 16) & 0xFF)
      data[offset+3] = UInt8((v >> 24) & 0xFF)
    }
    func write16(_ v: UInt16, at offset: Int) {
      data[offset]   = UInt8(v & 0xFF)
      data[offset+1] = UInt8((v >> 8) & 0xFF)
    }

    data[0...3]   = Data("RIFF".utf8)
    write32(UInt32(36 + byteCount), at: 4)
    data[8...11]  = Data("WAVE".utf8)
    data[12...15] = Data("fmt ".utf8)
    write32(16, at: 16); write16(1, at: 20); write16(1, at: 22)
    write32(UInt32(sampleRate), at: 24)
    write32(UInt32(sampleRate * 2), at: 28)
    write16(2, at: 32); write16(16, at: 34)
    data[36...39] = Data("data".utf8)
    write32(UInt32(byteCount), at: 40)

    var offset = headerSize
    for s in samples {
      let raw = Int16((max(-1, min(1, s)) * 32767).rounded())
      data[offset]   = UInt8(raw & 0xFF)
      data[offset+1] = UInt8((raw >> 8) & 0xFF)
      offset += 2
    }
    return data
  }
}

// MARK: - KoreanNeuralStt

/// Model name for the downloadable SenseVoice STT model. Matches `SttTask`.
let NEURAL_STT_MODEL_NAME = "SenseVoice (multilingual)"
private let NEURAL_STT_TOKENS = "tokens.txt"

/// Loads the downloadable multilingual SenseVoice recognizer (shared with the STT task).
///
/// NOTE: On Android this constructed a `sherpa-onnx` `OfflineRecognizer` configured
/// for SenseVoice (single `.onnx` + `tokens.txt`, no archive to unpack).
/// On iOS, no sherpa-onnx pod is available.
///
/// Bridge point: when a real sherpa-onnx / CoreML SenseVoice model is ready,
/// 1. Locate `model.int8.onnx` and `tokens.txt` via `model.getPath(fileName:)`.
/// 2. Construct a `NeuralSttEngine` implementation and return `.success(engine)`.
enum KoreanNeuralStt {
  static func load(
    model: Model,
    languageHint: String = "auto"
  ) -> NeuralSttLoadResult {
    let modelPath  = model.getPath()
    let tokensPath = model.getPath(fileName: NEURAL_STT_TOKENS)

    guard FileManager.default.fileExists(atPath: modelPath),
          FileManager.default.fileExists(atPath: tokensPath) else {
      return .notDownloaded
    }

    // NOTE: Real SenseVoice engine construction is not yet implemented.
    // Return the SFSpeechRecognizer fallback so the STT screen remains usable.
    let locale = languageHint == "auto" || languageHint.isEmpty
      ? Locale(identifier: "ko-KR")
      : Locale(identifier: languageHint)
    let engine = SFSpeechRecognizerSttEngine(locale: locale)
    return .success(engine)
  }
}
