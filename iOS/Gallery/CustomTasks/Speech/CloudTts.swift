// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/speech/CloudTts.kt

import Foundation

// MARK: - Data types

/// Decoded audio ready for `AudioPlayer`.
struct CloudAudio {
  let samples: [Float]
  let sampleRate: Int
}

/// A selectable speaker (voice) within a cloud provider.
struct CloudTtsVoice {
  let speakerId: String
  let label: String
}

/// A commercial TTS provider configured by parameters (not a downloaded model):
/// a base URL, an API token (+ optional client id) and the list of available speaker ids.
struct CloudTtsProvider {
  let id: String
  let name: String
  let baseUrl: String
  let apiToken: String
  /// Extra credential when the provider needs two (e.g. Naver client id). Empty otherwise.
  let clientId: String
  let voices: [CloudTtsVoice]

  init(id: String, name: String, baseUrl: String, apiToken: String,
       clientId: String = "", voices: [CloudTtsVoice]) {
    self.id = id; self.name = name; self.baseUrl = baseUrl
    self.apiToken = apiToken; self.clientId = clientId; self.voices = voices
  }
}

let CLOUD_PROVIDER_ELEVENLABS = "elevenlabs"
let CLOUD_PROVIDER_CLOVA = "clova"
private let VOICE_ID_PREFIX = "cloud"

// MARK: - CloudTtsService

/// Cloud (commercial) TTS support — ElevenLabs and Naver Clova.
///
/// Unlike on-device neural voices, these are not downloaded; they are called over HTTP
/// using the configured parameters. The auth tokens / client ids below are SAMPLE
/// placeholders — replace them (via a settings screen) with real credentials to enable
/// the providers.
///
/// Voices are surfaced as voice ids of the form `cloud:<providerId>:<speakerId>` so a
/// character can be assigned a cloud speaker through the same per-character voice
/// selection used for on-device voices.
final class CloudTtsService {

  var providers: [CloudTtsProvider]

  init(providers: [CloudTtsProvider]? = nil) {
    self.providers = providers ?? CloudTtsService.defaultSampleProviders()
  }

  func setProviders(_ newProviders: [CloudTtsProvider]) {
    providers = newProviders
  }

  /// Returns the selectable cloud voices as (voiceId, label) pairs for the voice picker.
  func voiceOptions() -> [(String, String)] {
    providers.flatMap { provider in
      provider.voices.map { voice in
        ("\(VOICE_ID_PREFIX):\(provider.id):\(voice.speakerId)",
         "\(provider.name) · \(voice.label)")
      }
    }
  }

  func isCloudVoice(_ voiceId: String) -> Bool {
    voiceId.hasPrefix("\(VOICE_ID_PREFIX):")
  }

  /// Synthesizes `text` for the cloud voice `voiceId` (`cloud:<provider>:<speaker>`).
  /// Network call — must be called off the main thread (or via async).
  /// Returns `nil` on any failure; caller should fall back or surface an error.
  func synthesize(voiceId: String, text: String) async -> CloudAudio? {
    let parts = voiceId.split(separator: ":", maxSplits: 2).map(String.init)
    guard parts.count == 3, parts[0] == VOICE_ID_PREFIX else { return nil }
    guard let provider = providers.first(where: { $0.id == parts[1] }) else { return nil }
    let speaker = parts[2]
    do {
      switch provider.id {
      case CLOUD_PROVIDER_ELEVENLABS:
        return try await synthesizeElevenLabs(provider: provider, speaker: speaker, text: text)
      case CLOUD_PROVIDER_CLOVA:
        return try await synthesizeClova(provider: provider, speaker: speaker, text: text)
      default:
        return nil
      }
    } catch {
      return nil
    }
  }

  // MARK: - ElevenLabs

  /// POST text, request raw PCM (16-bit, 22.05 kHz, mono).
  private func synthesizeElevenLabs(
    provider: CloudTtsProvider,
    speaker: String,
    text: String
  ) async throws -> CloudAudio? {
    guard let url = URL(string: "\(provider.baseUrl)/v1/text-to-speech/\(speaker)?output_format=pcm_22050") else { return nil }
    var req = URLRequest(url: url, timeoutInterval: 30)
    req.httpMethod = "POST"
    req.setValue(provider.apiToken, forHTTPHeaderField: "xi-api-key")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("audio/pcm", forHTTPHeaderField: "Accept")
    let body: [String: Any] = ["text": text, "model_id": "eleven_multilingual_v2"]
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: req)
    guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
    return CloudAudio(samples: pcm16leToFloat(data), sampleRate: 22050)
  }

  // MARK: - Naver Clova

  /// Form POST, request WAV (PCM16) which we decode.
  private func synthesizeClova(
    provider: CloudTtsProvider,
    speaker: String,
    text: String
  ) async throws -> CloudAudio? {
    guard let url = URL(string: "\(provider.baseUrl)/tts-premium/v1/tts") else { return nil }
    var req = URLRequest(url: url, timeoutInterval: 30)
    req.httpMethod = "POST"
    req.setValue(provider.clientId, forHTTPHeaderField: "X-NCP-APIGW-API-KEY-ID")
    req.setValue(provider.apiToken, forHTTPHeaderField: "X-NCP-APIGW-API-KEY")
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    func enc(_ s: String) -> String {
      s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
    let form = "speaker=\(enc(speaker))&format=wav&sampleRate=24000&text=\(enc(text))"
    req.httpBody = form.data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: req)
    guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
    return parseWav(data)
  }

  // MARK: - PCM helpers

  private func pcm16leToFloat(_ data: Data) -> [Float] {
    let count = data.count / 2
    var out = [Float](repeating: 0, count: count)
    data.withUnsafeBytes { raw in
      let buf = raw.bindMemory(to: Int16.self)
      for i in 0..<count {
        out[i] = Float(Int16(littleEndian: buf[i])) / 32768.0
      }
    }
    return out
  }

  /// Minimal WAV (PCM16) parser: finds the `fmt ` sample rate and the `data` chunk.
  private func parseWav(_ data: Data) -> CloudAudio? {
    guard data.count >= 44 else { return nil }
    var pos = 12  // skip "RIFF"<size>"WAVE"
    var sampleRate = 24000
    var dataOffset = -1
    var dataLen = 0

    while pos + 8 <= data.count {
      let id = String(data[pos..<(pos+4)].map { Character(UnicodeScalar($0)) })
      let size = data.withUnsafeBytes { raw -> Int32 in
        raw.load(fromByteOffset: pos + 4, as: Int32.self).littleEndian
      }
      let body = pos + 8
      switch id {
      case "fmt ":
        if body + 8 <= data.count {
          sampleRate = Int(data.withUnsafeBytes { raw in
            raw.load(fromByteOffset: body + 4, as: Int32.self).littleEndian
          })
        }
      case "data":
        dataOffset = body
        dataLen = Int(size)
      default: break
      }
      let aligned = Int(size) + (Int(size) & 1)
      pos = body + aligned
    }

    guard dataOffset >= 0 else { return nil }
    let end = min(dataOffset + dataLen, data.count)
    guard end > dataOffset else { return nil }
    let slice = data[dataOffset..<end]
    return CloudAudio(samples: pcm16leToFloat(slice), sampleRate: sampleRate)
  }

  // MARK: - Default providers

  static func defaultSampleProviders() -> [CloudTtsProvider] {
    [
      CloudTtsProvider(
        id: CLOUD_PROVIDER_ELEVENLABS,
        name: "ElevenLabs",
        baseUrl: "https://api.elevenlabs.io",
        // SAMPLE — replace with a real ElevenLabs API key.
        apiToken: "2d4bd2df1fdd0f22fdcd16b6cf28df56",
        voices: [
          CloudTtsVoice(speakerId: "21m00Tcm4TlvDq8ikWAM", label: "Rachel"),
          CloudTtsVoice(speakerId: "AZnzlk1XvdvUeBnXmlld", label: "Domi"),
          CloudTtsVoice(speakerId: "EXAVITQu4vr4xnSDxMaL", label: "Sarah"),
          CloudTtsVoice(speakerId: "TxGEqnHWrfWFTfGW9XjX", label: "Josh"),
        ]
      ),
      CloudTtsProvider(
        id: CLOUD_PROVIDER_CLOVA,
        name: "Clova",
        baseUrl: "https://naveropenapi.apigw.ntruss.com",
        // SAMPLE — replace with real Naver Cloud Platform credentials.
        apiToken: "dxlo1m8imG9NVr6QOgRpmtiz5cVQtKH1zXm608Gm",
        clientId: "s3uz7c10rx",
        voices: [
          CloudTtsVoice(speakerId: "nara",       label: "나라 (여)"),
          CloudTtsVoice(speakerId: "nminyoung",  label: "민영 (여)"),
          CloudTtsVoice(speakerId: "nyejin",     label: "예진 (여)"),
          CloudTtsVoice(speakerId: "jinho",      label: "진호 (남)"),
        ]
      ),
    ]
  }
}
