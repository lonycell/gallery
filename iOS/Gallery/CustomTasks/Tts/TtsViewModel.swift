// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/tts/TtsViewModel.kt

import AVFoundation
import Combine
import Foundation

// MARK: - UI state

/// UI state for `TtsScreen`.
struct TtsUiState {
  var isSynthesizing: Bool = false
  var error: String = ""
}

// MARK: - TtsViewModel

@MainActor
final class TtsViewModel: ObservableObject {
  @Published var uiState = TtsUiState()

  private let player = AudioPlayer()
  /// Fallback synthesizer used when the engine's `generate()` returns nil
  /// (i.e. on-device model not yet available; system TTS path).
  private let fallbackSynth = AVSpeechSynthesizer()
  private var speakTask: _Concurrency.Task<Void, Never>?

  func speak(instance: TtsModelInstance, text: String, speed: Float, sid: Int = 0) {
    guard !text.isBlankStr else { return }
    let safeSid = max(0, min(sid, max(0, instance.numSpeakers - 1)))

    speakTask?.cancel()
    speakTask = _Concurrency.Task { [weak self] in
      guard let self else { return }
      await MainActor.run { self.uiState = TtsUiState(isSynthesizing: true) }

      do {
        let generated = await _Concurrency.Task.detached(priority: .userInitiated) {
          instance.engine.generate(text: text, sid: safeSid, speed: speed)
        }.value
        if let (samples, sampleRate) = generated {
          // On-device model produced PCM — play via AudioPlayer.
          await self.player.playToCompletion(samples: samples, sampleRate: sampleRate)
        } else {
          // Fallback: system TTS via AVSpeechSynthesizer.
          await self.speakFallback(text: text, speed: speed, instance: instance)
        }
      }

      await MainActor.run { self.uiState.isSynthesizing = false }
    }
  }

  func stop() {
    speakTask?.cancel()
    speakTask = nil
    player.stop()
    fallbackSynth.stopSpeaking(at: .immediate)
    uiState.isSynthesizing = false
  }

  // MARK: - Fallback path

  private func speakFallback(
    text: String,
    speed: Float,
    instance: TtsModelInstance
  ) async {
    if let av = instance.engine as? AVSpeechSynthesizerTtsEngine {
      // Use the engine's own AVSpeechSynthesizer.
      av.speak(text: text, speed: speed)
    } else {
      // Generic fallback.
      let utterance = AVSpeechUtterance(string: text)
      utterance.rate = speed * AVSpeechUtteranceDefaultSpeechRate
      fallbackSynth.speak(utterance)
    }
    // Rough wait — system TTS has no async completion API.
    // A real on-device engine replaces this path entirely.
    let estimated = max(1.0, Double(text.count) / 10.0 / Double(speed))
    try? await _Concurrency.Task.sleep(nanoseconds: UInt64(estimated * 1_000_000_000))
  }
}

private extension String {
  var isBlankStr: Bool { self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
