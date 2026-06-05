// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/speech/KoreanNeuralTts.kt

import AVFoundation
import Foundation

// MARK: - Protocol surface

/// Protocol mirroring the capabilities of a sherpa-onnx `OfflineTts` engine.
/// The working iOS default is `AVSpeechSynthesizerTtsEngine`; drop a real
/// Core ML / ONNX Runtime bridge class here when available.
protocol NeuralTtsEngine: AnyObject {
  /// Number of speaker voices the model supports (≥ 1).
  var numSpeakers: Int { get }
  /// Optional human-readable labels for each speaker (in sid order).
  var speakerNames: [String] { get }
  /// Synthesize `text` with the given speaker id and playback speed.
  /// Returns samples (mono float [-1, 1]) and the sample rate, or nil on failure.
  func generate(text: String, sid: Int, speed: Float) -> (samples: [Float], sampleRate: Int)?
  /// Release any held resources.
  func release()
}

// MARK: - Load result

/// The outcome of attempting to prepare/load a TTS engine. Mirrors `KoreanTtsLoadResult`.
enum NeuralTtsLoadResult {
  case success(NeuralTtsEngine)
  case notDownloaded
  case failure(message: String, recoverable: Bool)
}

// MARK: - AVSpeechSynthesizer fallback engine

/// Working iOS TTS engine backed by `AVSpeechSynthesizer`.
/// Used as the default while a real on-device model is not yet available.
///
/// NOTE: To replace with a real sherpa-onnx / CoreML VITS model:
/// 1. Add `SherpaOnnxWrapper` (or equivalent) as a Swift Package / XCFramework.
/// 2. Create a class conforming to `NeuralTtsEngine` that forwards calls to the native engine.
/// 3. Return it from `KoreanNeuralTts.load()` instead of this class.
final class AVSpeechSynthesizerTtsEngine: NeuralTtsEngine {
  private let synthesizer = AVSpeechSynthesizer()
  private let languageCode: String

  let numSpeakers = 1
  let speakerNames: [String] = []

  init(languageCode: String = "ko-KR") {
    self.languageCode = languageCode
  }

  func generate(text: String, sid: Int, speed: Float) -> (samples: [Float], sampleRate: Int)? {
    // NOTE: AVSpeechSynthesizer renders speech to the audio session directly and
    // does not expose raw PCM samples. Returning nil here causes the caller to
    // fall through to `AVSpeechSynthesizer.speak()` in `TtsViewModel`.
    // When a real on-device model is integrated, return its `[Float]` samples here.
    return nil
  }

  /// Speak text directly via AVSpeechSynthesizer (bypasses the PCM pipeline).
  func speak(text: String, speed: Float) {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
    utterance.rate = speed * AVSpeechUtteranceDefaultSpeechRate
    synthesizer.speak(utterance)
  }

  func stopSpeaking() {
    synthesizer.stopSpeaking(at: .immediate)
  }

  func release() {
    synthesizer.stopSpeaking(at: .immediate)
  }
}

// MARK: - KoreanNeuralTts

/// Model name for the downloadable Korean VITS voice. Matches `TtsTask`.
let KOREAN_TTS_MODEL_NAME = "VITS-KSS (ko)"

/// Approximate archive entry count used for unpack progress rendering.
let KOREAN_TTS_ARCHIVE_ENTRY_COUNT = 399

private let KOREAN_TTS_DIR   = "vits-mimic3-ko_KO-kss_low"
private let KOREAN_TTS_ONNX  = "ko_KO-kss_low.onnx"

/// Loads the downloadable Korean neural TTS voice.
///
/// NOTE: On Android this unpacked a `.tar.bz2` archive and constructed a
/// `sherpa-onnx` `OfflineTts` engine (VITS + espeak-ng-data).
/// On iOS, `extractTarBz2` is a stub (see `SpeechArchive.swift`) and no
/// sherpa-onnx pod is available. The function therefore:
///   - Returns `.notDownloaded` if the archive is absent.
///   - Returns a working `AVSpeechSynthesizerTtsEngine` as a fallback so the
///     TTS screen functions correctly without the downloaded model.
///
/// Bridge point: when a real sherpa-onnx / CoreML VITS model is available,
/// perform the extraction here (call `extractTarBz2`), then construct your
/// `NeuralTtsEngine` implementation and return `.success(engine)`.
enum KoreanNeuralTts {
  static func load(
    model: Model,
    onUnpackProgress: ((Int) -> Void)? = nil,
    warmUp: Bool = true
  ) -> NeuralTtsLoadResult {
    let archivePath = model.getPath()
    let archiveURL = URL(fileURLWithPath: archivePath)

    // Check whether the archive was downloaded.
    guard FileManager.default.fileExists(atPath: archivePath) else {
      return .notDownloaded
    }

    // NOTE: Real extraction would happen here via extractTarBz2(archive:destDir:onProgress:).
    // Until the bridge is implemented, return the AVSpeechSynthesizer fallback.
    let engine = AVSpeechSynthesizerTtsEngine(languageCode: "ko-KR")
    return .success(engine)
  }

  /// Deletes extracted files (not the archive) so a fresh extraction can be attempted.
  static func clearExtracted(model: Model) {
    let archivePath = model.getPath()
    let baseURL = URL(fileURLWithPath: archivePath).deletingLastPathComponent()
    let extractedRoot = baseURL.appendingPathComponent(KOREAN_TTS_DIR)
    try? FileManager.default.removeItem(at: extractedRoot)
  }
}
