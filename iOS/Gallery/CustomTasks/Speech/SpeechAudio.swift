// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/speech/SpeechAudio.kt

import AVFoundation
import Foundation

/// The sample rate (Hz) shared by the speech models bundled with the Speech tasks.
let SPEECH_SAMPLE_RATE: Int = 16_000

/// The home-screen category that groups the speech-related custom tasks
/// (Text to Speech and Speech to Text).
let SpeechCategory = CategoryInfo(id: "speech", label: "Speech")

// MARK: - AudioPlayer

/// Plays back PCM audio produced by a TTS engine.
///
/// Samples are expected to be mono floats in the [-1, 1] range.
/// Playback runs off the main thread so the caller is never blocked.
final class AudioPlayer {
  private var player: AVAudioPlayer?
  private var playerTask: _Concurrency.Task<Void, Never>?

  /// Fire-and-forget playback. If something is already playing it is stopped first.
  func play(samples: [Float], sampleRate: Int) {
    stop()
    guard !samples.isEmpty else { return }
    playerTask = _Concurrency.Task.detached { [weak self] in
      await self?.playInternal(samples: samples, sampleRate: sampleRate)
    }
  }

  /// Suspends until playback finishes (or the calling Task is cancelled).
  /// Suitable for sequential sentence-by-sentence playback.
  func playToCompletion(samples: [Float], sampleRate: Int) async {
    stop()
    guard !samples.isEmpty else { return }
    await playInternal(samples: samples, sampleRate: sampleRate)
  }

  private func playInternal(samples: [Float], sampleRate: Int) async {
    // Build a 16-bit PCM WAV buffer in memory.
    guard let data = buildWav(samples: samples, sampleRate: sampleRate) else { return }
    do {
      let p = try AVAudioPlayer(data: data)
      player = p
      p.prepareToPlay()
      p.play()
      // Poll until the player finishes or the Task is cancelled.
      while p.isPlaying {
        if _Concurrency.Task.isCancelled { p.stop(); break }
        try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000)  // 20 ms
      }
    } catch {
      // Non-fatal; the UI already shows an error if synthesis itself failed.
    }
  }

  func stop() {
    playerTask?.cancel()
    playerTask = nil
    player?.stop()
    player = nil
  }

  // MARK: WAV builder

  /// Encodes [-1,1] float samples as a 16-bit PCM mono WAV file in memory.
  private func buildWav(samples: [Float], sampleRate: Int) -> Data? {
    let numSamples = samples.count
    let byteCount = numSamples * 2
    let headerSize = 44
    var data = Data(count: headerSize + byteCount)

    func write32LE(_ value: UInt32, at offset: Int) {
      data[offset]     = UInt8(value & 0xFF)
      data[offset + 1] = UInt8((value >> 8) & 0xFF)
      data[offset + 2] = UInt8((value >> 16) & 0xFF)
      data[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
    func write16LE(_ value: UInt16, at offset: Int) {
      data[offset]     = UInt8(value & 0xFF)
      data[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    // RIFF header
    data[0...3]   = Data("RIFF".utf8)
    write32LE(UInt32(36 + byteCount), at: 4)
    data[8...11]  = Data("WAVE".utf8)
    data[12...15] = Data("fmt ".utf8)
    write32LE(16, at: 16)          // PCM chunk size
    write16LE(1, at: 20)           // PCM format
    write16LE(1, at: 22)           // mono
    write32LE(UInt32(sampleRate), at: 24)
    write32LE(UInt32(sampleRate * 2), at: 28)  // byte rate
    write16LE(2, at: 32)           // block align
    write16LE(16, at: 34)          // bits per sample
    data[36...39] = Data("data".utf8)
    write32LE(UInt32(byteCount), at: 40)

    // PCM samples
    var offset = headerSize
    for s in samples {
      let clamped = max(-1, min(1, s))
      let raw = Int16(clamped * 32767)
      data[offset]     = UInt8(bitPattern: Int8(raw & 0x7F) )
      data[offset]     = UInt8(raw & 0xFF)
      data[offset + 1] = UInt8((raw >> 8) & 0xFF)
      offset += 2
    }
    return data
  }
}

// MARK: - AudioRecorder

/// Records microphone audio as mono float samples in the [-1, 1] range at
/// `SPEECH_SAMPLE_RATE` Hz, suitable for on-device STT engines.
///
/// The caller is responsible for holding the `NSMicrophoneUsageDescription`
/// / microphone permission before calling `start()`.
///
/// NOTE: On Android this used `AudioRecord` (PCM_16BIT). On iOS we use
/// `AVAudioEngine` with a tap on the input node, converting the hardware
/// buffer's native format to 16 kHz mono PCM on the fly.
/// To integrate a real on-device sherpa-onnx / CoreML STT engine, feed
/// the `[Float]` returned by `stop()` directly into the recognizer's
/// `acceptWaveform(samples:sampleRate:)` equivalent.
final class AudioRecorder {
  private let sampleRate: Int
  private var engine: AVAudioEngine?
  private var chunks: [[Float]] = []
  private let lock = NSLock()
  private(set) var isRecording = false

  init(sampleRate: Int = SPEECH_SAMPLE_RATE) {
    self.sampleRate = sampleRate
  }

  /// Starts capturing microphone audio. Throws if the engine can't start.
  func start() throws {
    guard !isRecording else { return }
    lock.lock(); chunks.removeAll(); lock.unlock()

    let e = AVAudioEngine()
    engine = e

    let inputNode = e.inputNode
    let hwFormat = inputNode.outputFormat(forBus: 0)
    guard let targetFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: Double(sampleRate),
      channels: 1,
      interleaved: false)
    else {
      throw RecordingError.formatUnsupported
    }

    // NOTE: `AVAudioConverter` translates from the hardware's native sample
    // rate / channel layout to 16 kHz mono float. Replace this path with a
    // sherpa-onnx streaming recognizer tap when integrating on-device ASR.
    guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
      throw RecordingError.formatUnsupported
    }

    let bufferSize = AVAudioFrameCount(hwFormat.sampleRate * 0.1)  // 100 ms chunks
    inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) {
      [weak self] buffer, _ in
      guard let self else { return }
      let ratio = targetFormat.sampleRate / hwFormat.sampleRate
      let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 0.5)
      guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames) else { return }
      var error: NSError?
      converter.convert(to: outBuffer, error: &error) { _, status in
        status.pointee = .haveData
        return buffer
      }
      if let channelData = outBuffer.floatChannelData?[0] {
        let count = Int(outBuffer.frameLength)
        let floats = Array(UnsafeBufferPointer(start: channelData, count: count))
        self.lock.lock(); self.chunks.append(floats); self.lock.unlock()
      }
    }

    try e.start()
    isRecording = true
  }

  /// Stops recording and returns all captured samples concatenated.
  func stop() -> [Float] {
    guard isRecording else { return [] }
    isRecording = false
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    engine = nil

    lock.lock(); defer { lock.unlock() }
    var out: [Float] = []
    for c in chunks { out.append(contentsOf: c) }
    chunks.removeAll()
    return out
  }

  enum RecordingError: Error {
    case formatUnsupported
    case engineStart(Error)
  }
}
