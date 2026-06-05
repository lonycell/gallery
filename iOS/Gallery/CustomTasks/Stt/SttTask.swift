// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/stt/SttTask.kt

import Foundation
import SwiftUI

// MARK: - SttModelInstance

/// Wraps an initialized STT engine so it can be stored on `Model.instance`.
final class SttModelInstance {
  let engine: NeuralSttEngine
  init(engine: NeuralSttEngine) { self.engine = engine }
}

// MARK: - Config keys

/// Config key letting the user hint the spoken language for the multilingual models.
let STT_CONFIG_KEY_LANGUAGE = ConfigKey(id: "stt_language", label: "Language")

/// "auto" lets the model detect the language; the rest map to language codes.
private let SENSE_VOICE_LANGUAGES = ["auto", "en", "ko", "ja", "zh", "yue"]
private let WHISPER_LANGUAGES     = ["ko", "auto", "en", "ja", "zh"]

private let SENSE_VOICE_CONFIGS: [Config] = [
  SegmentedButtonConfig(
    key: STT_CONFIG_KEY_LANGUAGE,
    defaultValue: "auto",
    options: SENSE_VOICE_LANGUAGES
  )
]

private let WHISPER_KO_CONFIGS: [Config] = [
  SegmentedButtonConfig(
    key: STT_CONFIG_KEY_LANGUAGE,
    defaultValue: "ko",
    options: WHISPER_LANGUAGES
  )
]

// MARK: - Model name constants

let STT_MODEL_SENSE_VOICE      = NEURAL_STT_MODEL_NAME
let STT_MODEL_WHISPER_TINY_EN  = "Whisper-tiny (en)"
let STT_MODEL_WHISPER_BASE_KO  = "Whisper base (multilingual)"
let STT_MODEL_WHISPER_SMALL_KO = WHISPER_KO_STT_MODEL_NAME

// Download base URLs
private let SENSE_VOICE_BASE_URL =
  "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main"
private let WHISPER_TINY_EN_BASE_URL =
  "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main"
private let WHISPER_BASE_ML_URL =
  "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/main"
private let WHISPER_SMALL_ML_URL =
  "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/main"

private let WHISPER_BASE_ENCODER = "base-encoder.int8.onnx"
private let WHISPER_BASE_DECODER = "base-decoder.int8.onnx"
private let WHISPER_BASE_TOKENS  = "base-tokens.txt"

// MARK: - SttTask

/// A custom task that transcribes recorded microphone audio to text.
///
/// On Android this used `sherpa-onnx` ASR models.
/// On iOS the working engine is `SFSpeechRecognizer`; real on-device neural recognizers
/// slot in by conforming to `NeuralSttEngine` — see `KoreanNeuralStt.swift`.
final class SttTask: CustomTask {
  let task: Task = Task(
    id: "speech_stt",
    label: "Speech to Text",
    category: SpeechCategory,
    icon: .system("waveform"),
    description:
      "Downloadable 온디바이스 음성 인식(STT). 모델을 선택하고 **녹음**을 탭해 말한 뒤 **정지**를 탭하면 텍스트로 변환합니다.\n\n" +
      "[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) ASR 모델 기반.",
    shortDescription: "온디바이스 음성 텍스트 변환",
    docUrl: "https://k2-fsa.github.io/sherpa/onnx/pretrained_models/index.html",
    sourceCodeUrl:
      "https://github.com/google-ai-edge/gallery/blob/main/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/stt",
    models: [
      Model(
        name: STT_MODEL_SENSE_VOICE,
        info:
          "다국어 음성 인식 (zh/en/ja/ko/yue). 설정 메뉴에서 언어를 설정하거나 \"auto\"로 자동 감지하세요.",
        learnMoreUrl:
          "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17",
        url: "\(SENSE_VOICE_BASE_URL)/model.int8.onnx",
        sizeInBytes: 239_233_841,
        downloadFileName: "model.int8.onnx",
        extraDataFiles: [
          ModelDataFile(
            name: "tokens",
            url: "\(SENSE_VOICE_BASE_URL)/tokens.txt",
            downloadFileName: "tokens.txt",
            sizeInBytes: 315_894
          )
        ],
        configs: SENSE_VOICE_CONFIGS
      ),
      Model(
        name: STT_MODEL_WHISPER_TINY_EN,
        info: "경량 영어 전용 음성 인식 (OpenAI Whisper tiny.en 기반).",
        learnMoreUrl: "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en",
        url: "\(WHISPER_TINY_EN_BASE_URL)/tiny.en-encoder.int8.onnx",
        sizeInBytes: 12_937_772,
        downloadFileName: "tiny.en-encoder.int8.onnx",
        extraDataFiles: [
          ModelDataFile(
            name: "decoder",
            url: "\(WHISPER_TINY_EN_BASE_URL)/tiny.en-decoder.int8.onnx",
            downloadFileName: "tiny.en-decoder.int8.onnx",
            sizeInBytes: 89_853_865
          ),
          ModelDataFile(
            name: "tokens",
            url: "\(WHISPER_TINY_EN_BASE_URL)/tiny.en-tokens.txt",
            downloadFileName: "tiny.en-tokens.txt",
            sizeInBytes: 835_554
          ),
        ]
      ),
      Model(
        name: STT_MODEL_WHISPER_BASE_KO,
        info:
          "다국어 음성 인식 (OpenAI Whisper base). 한국어 지원이 우수하며 small보다 빠릅니다. " +
          "설정 메뉴에서 언어를 변경할 수 있습니다 (기본값: 한국어).",
        learnMoreUrl: "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base",
        url: "\(WHISPER_BASE_ML_URL)/\(WHISPER_BASE_ENCODER)",
        sizeInBytes: 29_120_534,
        downloadFileName: WHISPER_BASE_ENCODER,
        extraDataFiles: [
          ModelDataFile(
            name: "decoder",
            url: "\(WHISPER_BASE_ML_URL)/\(WHISPER_BASE_DECODER)",
            downloadFileName: WHISPER_BASE_DECODER,
            sizeInBytes: 130_672_026
          ),
          ModelDataFile(
            name: "tokens",
            url: "\(WHISPER_BASE_ML_URL)/\(WHISPER_BASE_TOKENS)",
            downloadFileName: WHISPER_BASE_TOKENS,
            sizeInBytes: 816_730
          ),
        ],
        configs: WHISPER_KO_CONFIGS
      ),
      Model(
        name: STT_MODEL_WHISPER_SMALL_KO,
        info:
          "다국어 음성 인식 (OpenAI Whisper small). base보다 한국어 정확도가 높지만 더 큰 다운로드와 " +
          "느린 디코딩이 필요합니다. Voice Assistant에서도 사용됩니다.",
        learnMoreUrl: "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small",
        url: "\(WHISPER_SMALL_ML_URL)/\(WHISPER_SMALL_ENCODER)",
        sizeInBytes: 112_442_483,
        downloadFileName: WHISPER_SMALL_ENCODER,
        extraDataFiles: [
          ModelDataFile(
            name: "decoder",
            url: "\(WHISPER_SMALL_ML_URL)/\(WHISPER_SMALL_DECODER)",
            downloadFileName: WHISPER_SMALL_DECODER,
            sizeInBytes: 262_226_114
          ),
          ModelDataFile(
            name: "tokens",
            url: "\(WHISPER_SMALL_ML_URL)/\(WHISPER_SMALL_TOKENS)",
            downloadFileName: WHISPER_SMALL_TOKENS,
            sizeInBytes: 816_730
          ),
        ],
        configs: WHISPER_KO_CONFIGS
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

      let result = Self.buildEngine(model: model)
      await MainActor.run {
        switch result {
        case .success(let engine):
          model.instance = SttModelInstance(engine: engine)
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
    return AnyView(SttScreen(modelManagerViewModel: customTaskData.modelManagerViewModel))
  }

  // MARK: - Engine factory

  private static func buildEngine(model: Model) -> NeuralSttLoadResult {
    switch model.name {
    case STT_MODEL_SENSE_VOICE:
      let languageHint = model.getStringConfigValue(STT_CONFIG_KEY_LANGUAGE, default: "auto")
      return KoreanNeuralStt.load(model: model, languageHint: languageHint)

    case STT_MODEL_WHISPER_TINY_EN:
      return WhisperNeuralStt.load(
        model: model,
        encoderFileName: "tiny.en-encoder.int8.onnx",
        decoderFileName: "tiny.en-decoder.int8.onnx",
        tokensFileName: "tiny.en-tokens.txt",
        language: "en"
      )

    case STT_MODEL_WHISPER_BASE_KO:
      let lang = model.getStringConfigValue(STT_CONFIG_KEY_LANGUAGE, default: "ko")
      return WhisperNeuralStt.load(
        model: model,
        encoderFileName: WHISPER_BASE_ENCODER,
        decoderFileName: WHISPER_BASE_DECODER,
        tokensFileName: WHISPER_BASE_TOKENS,
        language: lang == "auto" ? "" : lang
      )

    default: // STT_MODEL_WHISPER_SMALL_KO
      let lang = model.getStringConfigValue(STT_CONFIG_KEY_LANGUAGE, default: "ko")
      return WhisperNeuralStt.load(
        model: model,
        encoderFileName: WHISPER_SMALL_ENCODER,
        decoderFileName: WHISPER_SMALL_DECODER,
        tokensFileName: WHISPER_SMALL_TOKENS,
        language: lang == "auto" ? "" : lang
      )
    }
  }

  // MARK: - Helpers

  private func cleanUp(model: Model) {
    if let instance = model.instance as? SttModelInstance {
      instance.engine.release()
    }
    model.instance = nil
  }
}
