// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/stt/SttViewModel.kt

import AVFoundation
import Combine
import Foundation
import Speech

// MARK: - UI state

/// UI state for `SttScreen`.
struct SttUiState {
  var isRecording: Bool = false
  var isTranscribing: Bool = false
  var transcript: String = ""
  var error: String = ""
}

// MARK: - SttViewModel

@MainActor
final class SttViewModel: ObservableObject {
  @Published var uiState = SttUiState()

  private let recorder = AudioRecorder(sampleRate: SPEECH_SAMPLE_RATE)
  private var transcribeTask: Task<Void, Never>?

  // MARK: - Public API

  func startRecording() {
    do {
      try recorder.start()
      uiState = SttUiState(isRecording: true)
    } catch {
      uiState = SttUiState(error: error.localizedDescription)
    }
  }

  func stopAndTranscribe(instance: SttModelInstance) {
    guard uiState.isRecording else { return }
    let samples = recorder.stop()
    uiState.isRecording = false

    guard !samples.isEmpty else {
      uiState.error = "녹음된 오디오가 없습니다."
      return
    }

    uiState.isTranscribing = true
    transcribeTask?.cancel()
    transcribeTask = Task { [weak self] in
      guard let self else { return }
      do {
        let text = await Task.detached(priority: .userInitiated) {
          await instance.engine.transcribe(samples: samples, sampleRate: SPEECH_SAMPLE_RATE)
        }.value
        await MainActor.run {
          self.uiState.isTranscribing = false
          self.uiState.transcript = text
        }
      }
    }
  }

  func cancelRecording() {
    guard uiState.isRecording else { return }
    _ = recorder.stop()
    uiState.isRecording = false
  }

  /// Requests microphone permission and calls `onGranted` / `onDenied` on the main thread.
  func requestMicrophonePermission(onGranted: @escaping () -> Void, onDenied: @escaping () -> Void) {
    AVAudioApplication.requestRecordPermission { granted in
      DispatchQueue.main.async {
        if granted { onGranted() } else { onDenied() }
      }
    }
  }

  deinit {
    // Note: `deinit` is not isolated; cancel the task synchronously.
    transcribeTask?.cancel()
  }
}
