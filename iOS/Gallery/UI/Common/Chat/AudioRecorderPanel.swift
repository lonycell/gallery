/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/AudioRecorderPanel.kt
// NOTE: Android used AudioRecord (raw PCM). iOS bridge uses AVAudioRecorder
// with PCM/WAV settings so the recorded data is compatible with the rest of the
// pipeline. Microphone permission (NSMicrophoneUsageDescription) must be in Info.plist.

import SwiftUI
import AVFoundation

private let MAX_AUDIO_CLIP_DURATION_SEC: Double = 30
private let SAMPLE_RATE_HZ = 16000

struct AudioRecorderPanel: View {
  let task: Task
  var onAmplitudeChanged: (Int) -> Void = { _ in }
  var onSendAudioClip: (Data) -> Void
  var onClose: () -> Void

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  @State private var isRecording = false
  @State private var elapsedSeconds: Double = 0
  // NOTE: AVAudioRecorder is the iOS bridge for Android's AudioRecord.
  @State private var recorder: AVAudioRecorder?
  @State private var timer: Timer?
  @State private var tmpURL: URL?

  private var taskIconColor: Color {
    let idx = task.index >= 0 ? task.index % customColors.taskIconColors.count : 0
    return customColors.taskIconColors.isEmpty ? colors.primary : customColors.taskIconColors[idx]
  }

  var body: some View {
    HStack(spacing: 4) {
      // Close button
      Button(action: {
        if isRecording { stopRecording(send: false) }
        onClose()
      }) {
        Image(systemName: "xmark")
          .frame(width: 44, height: 44)
          .background(colors.surfaceContainer.opacity(0.7))
          .clipShape(Circle())
      }
      .buttonStyle(.plain)

      // Control pill
      HStack {
        if !isRecording {
          Text("녹음 버튼을 눌러 시작하세요")
            .font(.caption).foregroundColor(colors.onSurfaceVariant)
        } else {
          HStack(spacing: 12) {
            Circle()
              .fill(customColors.recordButtonBgColor)
              .frame(width: 8, height: 8)
            Text(String(format: "%.1f s", elapsedSeconds))
              .font(.subheadline)
          }
        }
        Spacer()
        // Record / Send button
        Button(action: {
          if !isRecording { startRecording() } else { stopRecording(send: true) }
        }) {
          Image(systemName: isRecording ? "arrow.up" : "mic.fill")
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(taskIconColor)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }
      .padding(.leading, 12)
      .frame(maxWidth: .infinity)
      .background(colors.surfaceContainer.opacity(0.7))
      .clipShape(Capsule())
    }
    .padding(.horizontal, 8)
    .onDisappear { stopRecording(send: false) }
  }

  private func startRecording() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".wav")
    tmpURL = url

    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatLinearPCM),
      AVSampleRateKey: SAMPLE_RATE_HZ,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
    ]

    do {
      try AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
      let rec = try AVAudioRecorder(url: url, settings: settings)
      rec.isMeteringEnabled = true
      rec.record()
      recorder = rec
      isRecording = true
      elapsedSeconds = 0

      timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
        DispatchQueue.main.async {
          guard let rec = recorder else { return }
          rec.updateMeters()
          let db = rec.averagePower(forChannel: 0)
          // Convert dBFS (-160...0) to 0...32767 amplitude approximation
          let normalized = pow(10.0, Double(db) / 20.0)
          let amplitude = Int(normalized * 32767)
          onAmplitudeChanged(max(0, amplitude))
          elapsedSeconds += 0.1
          if elapsedSeconds >= MAX_AUDIO_CLIP_DURATION_SEC {
            stopRecording(send: true)
          }
        }
      }
    } catch {
      galleryLog("AudioRecorderPanel", "Failed to start recording: \(error)")
    }
  }

  private func stopRecording(send: Bool) {
    timer?.invalidate()
    timer = nil
    recorder?.stop()
    recorder = nil
    isRecording = false
    onAmplitudeChanged(0)

    if send, let url = tmpURL {
      // Strip WAV header (44 bytes) to get raw PCM matching Android's byte array
      if let wavData = try? Data(contentsOf: url) {
        let headerSize = 44
        let pcmData = wavData.count > headerSize
          ? wavData.subdata(in: headerSize..<wavData.count)
          : Data()
        onSendAudioClip(pcmData)
      }
      try? FileManager.default.removeItem(at: url)
      tmpURL = nil
    }
  }
}
