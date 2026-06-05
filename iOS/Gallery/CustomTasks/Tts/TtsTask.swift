// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/tts/TtsTask.kt

import AVFoundation
import Foundation
import SwiftUI

// MARK: - TtsModelInstance

/// Wraps an initialized TTS engine so it can be stored on `Model.instance`.
///
/// `speakerNames` are optional human-readable labels for multi-speaker models (in sid order).
/// When absent the UI falls back to numbered voices ("음성 1", "음성 2", …).
/// `avEngine` is the fallback `AVSpeechSynthesizerTtsEngine` used when the
/// `NeuralTtsEngine.generate()` returns nil (i.e. the system TTS path).
final class TtsModelInstance {
  let engine: NeuralTtsEngine
  let speakerNames: [String]

  var numSpeakers: Int { engine.numSpeakers }

  init(engine: NeuralTtsEngine, speakerNames: [String] = []) {
    self.engine = engine
    self.speakerNames = speakerNames
  }
}

// MARK: - Config keys

/// Config key controlling the synthesis speed (1.0 = normal).
let TTS_CONFIG_KEY_SPEED = ConfigKey(id: "tts_speed", label: "Speed")

private let TTS_CONFIGS: [Config] = [
  NumberSliderConfig(
    key: TTS_CONFIG_KEY_SPEED,
    sliderMin: 0.5,
    sliderMax: 2.0,
    defaultValue: 1.0,
    valueType: .float,
    needReinitialization: false
  )
]

// MARK: - Model name constants

let TTS_MODEL_VITS_LJSPEECH = "VITS-LJSpeech (en)"
let TTS_MODEL_VITS_KSS_KO   = KOREAN_TTS_MODEL_NAME
let TTS_MODEL_MELO_KO        = MELO_TTS_MODEL_NAME

// Download URLs
private let VITS_LJS_BASE_URL = "https://huggingface.co/csukuangfj/vits-ljs/resolve/main"
private let VITS_KSS_KO_ARCHIVE = "vits-mimic3-ko_KO-kss_low.tar.bz2"
private let VITS_KSS_KO_URL =
  "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/\(VITS_KSS_KO_ARCHIVE)"
private let MELO_KO_ARCHIVE = "\(MELO_TTS_DIR).tar.bz2"
private let MELO_KO_URL = "https://models.utopsoft.co.kr/tts/melo/onnx/vits-melo-tts-ko.tar.bz2"
private let MELO_KO_SIZE_BYTES: Int64 = 162_377_762

// MARK: - TtsTask

/// A custom task that performs on-device text-to-speech.
///
/// On Android this used `sherpa-onnx` VITS models.
/// On iOS the working engine is `AVSpeechSynthesizer`; real on-device neural voices
/// slot in by conforming to `NeuralTtsEngine` — see `KoreanNeuralTts.swift`.
final class TtsTask: CustomTask {
  let task: Task = Task(
    id: "speech_tts",
    label: "Text to Speech",
    category: SpeechCategory,
    icon: .system("record.circle"),
    description:
      "Downloadable 온디바이스 음성 합성(TTS). 텍스트를 입력하고 모델을 선택한 뒤 **말하기**를 탭하세요.\n\n" +
      "[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) VITS 모델 기반.",
    shortDescription: "온디바이스 텍스트 음성 변환",
    docUrl: "https://k2-fsa.github.io/sherpa/onnx/tts/index.html",
    sourceCodeUrl:
      "https://github.com/google-ai-edge/gallery/blob/main/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/tts",
    models: [
      Model(
        name: TTS_MODEL_VITS_LJSPEECH,
        info:
          "A single-speaker English VITS voice (LJSpeech) exported for sherpa-onnx. " +
          "Uses a lexicon for pronunciation.",
        learnMoreUrl: "https://huggingface.co/csukuangfj/vits-ljs",
        url: "\(VITS_LJS_BASE_URL)/vits-ljs.int8.onnx",
        sizeInBytes: 37_423_560,
        downloadFileName: "vits-ljs.int8.onnx",
        extraDataFiles: [
          ModelDataFile(
            name: "tokens",
            url: "\(VITS_LJS_BASE_URL)/tokens.txt",
            downloadFileName: "tokens.txt",
            sizeInBytes: 1_084
          ),
          ModelDataFile(
            name: "lexicon",
            url: "\(VITS_LJS_BASE_URL)/lexicon.txt",
            downloadFileName: "lexicon.txt",
            sizeInBytes: 3_708_181
          ),
        ],
        configs: TTS_CONFIGS
      ),
      Model(
        name: TTS_MODEL_VITS_KSS_KO,
        info:
          "한국어 단일 화자 VITS 음성(KSS 데이터셋, mimic3에서 변환). " +
          "espeak-ng 음소화 데이터를 포함해 하나의 압축 파일로 내려받은 뒤 기기에서 자동으로 해제합니다.",
        learnMoreUrl: "https://huggingface.co/csukuangfj/vits-mimic3-ko_KO-kss_low",
        url: VITS_KSS_KO_URL,
        sizeInBytes: 66_838_474,
        downloadFileName: VITS_KSS_KO_ARCHIVE,
        configs: TTS_CONFIGS
      ),
      Model(
        name: TTS_MODEL_MELO_KO,
        info:
          "MeloTTS(MyShell.ai)의 한국어 음성. 매우 자연스러운 한국어 발화를 제공합니다. " +
          "sherpa-onnx에서는 VITS 모델로 동작하며, 모델·토큰·렉시콘을 하나의 압축 파일로 내려받습니다.",
        learnMoreUrl: "https://huggingface.co/myshell-ai/MeloTTS-Korean",
        url: MELO_KO_URL,
        sizeInBytes: MELO_KO_SIZE_BYTES,
        downloadFileName: MELO_KO_ARCHIVE,
        configs: TTS_CONFIGS
      ),
    ]
  )

  func initializeModelFn(
    model: Model,
    systemInstruction: Contents?,
    onDone: @escaping (String) -> Void
  ) {
    Task.detached {
      self.cleanUp(model: model)

      let result: NeuralTtsLoadResult
      switch model.name {
      case TTS_MODEL_VITS_KSS_KO:
        result = KoreanNeuralTts.load(model: model)
      case TTS_MODEL_MELO_KO:
        let meloResult = MeloNeuralTts.load(model: model)
        switch meloResult {
        case .success(let engine):   result = .success(engine)
        case .notDownloaded:         result = .notDownloaded
        case .failure(let m, let r): result = .failure(message: m, recoverable: r)
        }
      default:
        // LJSpeech and future lexicon-based models: fall back to system TTS.
        let engine = AVSpeechSynthesizerTtsEngine(languageCode: "en-US")
        result = .success(engine)
      }

      await MainActor.run {
        switch result {
        case .success(let engine):
          let speakerNames = Self.readSpeakerNames(model: model)
          model.instance = TtsModelInstance(engine: engine, speakerNames: speakerNames)
          onDone("")
        case .notDownloaded:
          onDone("모델 파일이 아직 다운로드되지 않았습니다.")
        case .failure(let message, _):
          onDone(message)
        }
      }
    }
  }

  func cleanUpModelFn(model: Model, onDone: @escaping () -> Void) {
    cleanUp(model: model)
    onDone()
  }

  @MainActor func mainScreen(data: Any) -> AnyView {
    let customTaskData = data as! CustomTaskData
    return AnyView(TtsScreen(modelManagerViewModel: customTaskData.modelManagerViewModel))
  }

  // MARK: - Helpers

  private func cleanUp(model: Model) {
    if let instance = model.instance as? TtsModelInstance {
      instance.engine.release()
    }
    model.instance = nil
  }

  /// Reads optional friendly voice labels from a `speakers.txt` next to the model file
  /// (one per line, in sid order). Returns empty when the file is absent.
  private static func readSpeakerNames(model: Model) -> [String] {
    let modelPath = model.getPath()
    let dir = URL(fileURLWithPath: modelPath).deletingLastPathComponent()
    let file = dir.appendingPathComponent("speakers.txt")
    guard let content = try? String(contentsOf: file, encoding: .utf8) else { return [] }
    return content.components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }
}
