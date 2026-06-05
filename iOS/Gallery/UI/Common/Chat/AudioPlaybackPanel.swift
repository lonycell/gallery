/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/AudioPlaybackPanel.kt
// NOTE: Android used AudioTrack for raw PCM playback. iOS bridge uses AVAudioPlayer
// with a WAV file built from the PCM data via ChatMessageAudioClip.genDataForWav().
// AVAudioSession category is set to .playback so audio plays over the speaker.

import SwiftUI
import AVFoundation

private let BAR_SPACE: CGFloat = 2
private let BAR_WIDTH: CGFloat = 2
private let MIN_BAR_COUNT = 16
private let MAX_BAR_COUNT = 48

struct AudioPlaybackPanel: View {
  let audioData: Data
  let sampleRate: Int
  var isRecording: Bool = false
  var onDarkBg: Bool = false

  @Environment(\.customColors) private var customColors
  @Environment(\.galleryColors) private var colors

  @State private var isPlaying = false
  @State private var playbackProgress: Float = 0
  // NOTE: AVAudioPlayer is the iOS bridge for Android's AudioTrack.
  @State private var player: AVAudioPlayer?
  @State private var progressTimer: Timer?

  private var durationInSeconds: Double {
    let bytesPerSample = 2
    let totalFrames = Double(audioData.count) / Double(bytesPerSample)
    return totalFrames / Double(sampleRate)
  }

  private var barCount: Int {
    let maxAudioSec = 30.0
    let f = durationInSeconds / maxAudioSec
    return Int((Double(MAX_BAR_COUNT - MIN_BAR_COUNT) * f) + Double(MIN_BAR_COUNT))
  }

  private var amplitudeLevels: [Float] {
    generateAmplitudeLevels(audioData: audioData, barCount: barCount)
  }

  var body: some View {
    HStack(spacing: 4) {
      // Play/Stop button
      Button {
        if isPlaying { stopPlayback() } else { startPlayback() }
      } label: {
        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
          .foregroundColor(onDarkBg ? .white : colors.primary)
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)

      // Waveform visualization
      AmplitudeBarGraph(
        amplitudeLevels: amplitudeLevels,
        progress: playbackProgress,
        onDarkBg: onDarkBg
      )
      .frame(
        width: CGFloat(barCount) * (BAR_WIDTH + BAR_SPACE) - BAR_SPACE,
        height: 24
      )

      // Duration label
      Text(String(format: "%.1fs", durationInSeconds))
        .font(.subheadline).fontWeight(.semibold)
        .foregroundColor(onDarkBg ? .white : colors.onSurfaceVariant)
        .padding(.leading, 8)
    }
    .onChange(of: isRecording) { recording in
      if recording {
        stopPlayback()
        playbackProgress = 0
      }
    }
    .onDisappear { stopPlayback() }
  }

  private func startPlayback() {
    // NOTE: Build a WAV from raw PCM then hand it to AVAudioPlayer.
    let msg = ChatMessageAudioClip(audioData: audioData, sampleRate: sampleRate, side: .agent)
    let wavData = msg.genDataForWav()
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
      let p = try AVAudioPlayer(data: wavData)
      p.prepareToPlay()
      p.play()
      player = p
      isPlaying = true
      playbackProgress = 0

      progressTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { _ in
        DispatchQueue.main.async {
          guard let pl = player else { return }
          if pl.isPlaying {
            playbackProgress = Float(pl.currentTime / pl.duration)
          } else {
            playbackProgress = 0
            isPlaying = false
            progressTimer?.invalidate()
            progressTimer = nil
          }
        }
      }
    } catch {
      galleryLog("AudioPlaybackPanel", "Failed to play audio: \(error)")
    }
  }

  private func stopPlayback() {
    player?.stop()
    player = nil
    progressTimer?.invalidate()
    progressTimer = nil
    isPlaying = false
    playbackProgress = 0
  }
}

private struct AmplitudeBarGraph: View {
  let amplitudeLevels: [Float]
  let progress: Float
  var onDarkBg: Bool = false

  @Environment(\.customColors) private var customColors
  @Environment(\.galleryColors) private var colors

  var body: some View {
    GeometryReader { geo in
      Canvas { ctx, size in
        let barCount = amplitudeLevels.count
        let totalSpacing = BAR_SPACE * CGFloat(barCount - 1)
        let barW = (size.width - totalSpacing) / CGFloat(barCount)
        let progressWidth = size.width * CGFloat(progress)

        for (index, level) in amplitudeLevels.enumerated() {
          let barH = max(1.5, CGFloat(level) * size.height)
          let x = CGFloat(index) * (barW + BAR_SPACE)
          let rect = CGRect(
            x: x,
            y: (size.height - barH) / 2,
            width: barW,
            height: barH
          )
          let path = Path(roundedRect: rect, cornerRadius: barW / 2)

          // Color: progress region = accent, rest = waveform bg
          if x + barW <= progressWidth {
            ctx.fill(path, with: .color(onDarkBg ? .white : colors.primary))
          } else {
            ctx.fill(path, with: .color(customColors.waveFormBgColor))
          }
        }
      }
    }
  }
}

private func generateAmplitudeLevels(audioData: Data, barCount: Int) -> [Float] {
  guard !audioData.isEmpty, barCount > 0 else { return Array(repeating: 0, count: barCount) }
  let samples = audioData.withUnsafeBytes { ptr -> [Int16] in
    guard let base = ptr.baseAddress else { return [] }
    let count = audioData.count / 2
    return Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: Int16.self), count: count))
  }
  guard !samples.isEmpty else { return Array(repeating: 0, count: barCount) }
  let chunkSize = max(1, samples.count / barCount)
  var levels = [Float]()
  for i in 0..<barCount {
    let start = i * chunkSize
    let end = min(start + chunkSize, samples.count)
    var maxAmp: Double = 0
    for j in start..<end {
      let abs = Double(abs(samples[j]))
      if abs > maxAmp { maxAmp = abs }
    }
    levels.append(Float(maxAmp / Double(Int16.max)).clamped(to: 0...1))
  }
  let maxVal = levels.max() ?? 0
  if maxVal == 0 { return levels }
  let scale = 0.9 / maxVal
  return levels.map { $0 * scale }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
