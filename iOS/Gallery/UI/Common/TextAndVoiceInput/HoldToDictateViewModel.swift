/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/textandvoiceinput/HoldToDictateViewModel.kt
//
// NOTE: Android used android.speech.SpeechRecognizer (SpeechRecognizer.createSpeechRecognizer +
// RecognitionListener). iOS uses AVAudioEngine + SFSpeechRecognizer from the Speech framework.
// The public API surface (startSpeechRecognition / stopSpeechRecognition / cancelSpeechRecognition)
// is identical to Android.

import Foundation
import Combine
import Speech
import AVFoundation

private let AUDIO_METER_MIN_DB: Float = -2.0
private let AUDIO_METER_MAX_DB: Float = 100.0

/// UI state for HoldToDictateViewModel. Mirrors `HoldToDictateUiState`.
struct HoldToDictateUiState {
  var recognizing: Bool = false
  var recognizedText: String = ""
}

/// ViewModel for hold-to-dictate speech recognition. Mirrors `HoldToDictateViewModel`.
@MainActor
final class HoldToDictateViewModel: ObservableObject {
  @Published private(set) var uiState = HoldToDictateUiState()

  // NOTE: SFSpeechRecognizer is the iOS equivalent of Android SpeechRecognizer.
  private var speechRecognizer: SFSpeechRecognizer?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private let audioEngine = AVAudioEngine()

  private var onDoneCallback: ((String) -> Void)?
  private var onAmplitudeCallback: ((Int) -> Void)?

  init() {
    speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
  }

  func startSpeechRecognition(onDone: @escaping (String) -> Void,
                               onAmplitudeChanged: @escaping (Int) -> Void) {
    onDoneCallback = onDone
    onAmplitudeCallback = onAmplitudeChanged
    setRecognizedText("")
    setRecognizing(true)

    Task.detached(priority: .userInitiated) { [weak self] in
      await self?.startRecognitionSession()
    }
  }

  func stopSpeechRecognition() {
    Task {
      try? await Task.sleep(nanoseconds: 500_000_000)
      await MainActor.run {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        setRecognizing(false)
      }
    }
  }

  func cancelSpeechRecognition() {
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    recognitionTask = nil
    setRecognizing(false)
  }

  func setRecognizing(_ value: Bool) {
    uiState.recognizing = value
  }

  func setRecognizedText(_ text: String) {
    uiState.recognizedText = text
  }

  // MARK: Private

  private func startRecognitionSession() async {
    // NOTE: Request microphone + speech-recognition permissions if not already granted.
    let authStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
      SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
    }
    guard authStatus == .authorized else { return }

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch { return }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    recognitionRequest = request

    let inputNode = audioEngine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
      request.append(buffer)
      // Amplitude estimation from raw PCM samples
      if let channelData = buffer.floatChannelData?[0] {
        let frames = buffer.frameLength
        var rms: Float = 0
        for i in 0..<Int(frames) { rms += channelData[i] * channelData[i] }
        rms = sqrt(rms / Float(frames))
        let dB = 20 * log10(max(rms, 1e-7))
        let amplitude = self?.convertDbToAmplitude(dB) ?? 0
        DispatchQueue.main.async { self?.onAmplitudeCallback?(amplitude) }
      }
    }

    audioEngine.prepare()
    do { try audioEngine.start() } catch { return }

    recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }
      if let result {
        let text = result.bestTranscription.formattedString
        Task { @MainActor in self.setRecognizedText(text) }
        if result.isFinal {
          Task { @MainActor in
            self.onDoneCallback?(text)
            self.setRecognizing(false)
          }
        }
      }
      if error != nil {
        Task { @MainActor in self.setRecognizing(false) }
      }
    }
  }

  private func convertDbToAmplitude(_ dB: Float) -> Int {
    let clamped = min(max(dB, AUDIO_METER_MIN_DB), AUDIO_METER_MAX_DB)
    return Int((clamped - AUDIO_METER_MIN_DB) * 65535 / (AUDIO_METER_MAX_DB - AUDIO_METER_MIN_DB))
  }
}

