/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of data/ModelAllowlist.kt — the HuggingFace-backed allowlist parsed from
// the remote `model_allowlist.json`, plus `AllowedModel.toModel()`.

import Foundation

/// Device helpers (Android checked Pixel SoC; on iOS these are best-effort).
enum Device {
  static func isPixelDevice() -> Bool { false }
  static func isPixel10() -> Bool { false }
}

struct DefaultConfig: Codable {
  var topK: Int?
  var topP: Float?
  var temperature: Float?
  var accelerators: String?
  var visionAccelerator: String?
  var maxContextLength: Int?
  var maxTokens: Int?
}

/// A model file on HF for a specific SOC.
struct SocModelFile: Codable {
  var modelFile: String?
  var url: String?
  var commitHash: String?
  var sizeInBytes: Int64?
}

/// A model in the model allowlist. Mirrors `AllowedModel`.
struct AllowedModel: Codable {
  let name: String
  let modelId: String
  let modelFile: String
  let commitHash: String
  let description: String
  let sizeInBytes: Int64
  let defaultConfig: DefaultConfig
  let taskTypes: [String]
  var disabled: Bool?
  var llmSupportImage: Bool?
  var llmSupportAudio: Bool?
  var llmSupportTinyGarden: Bool?
  var llmSupportMobileActions: Bool?
  var capabilities: [ModelCapability]?
  var minDeviceMemoryInGb: Int?
  var bestForTaskTypes: [String]?
  var localModelFilePathOverride: String?
  var url: String?
  var socToModelFiles: [String: SocModelFile]?
  var runtimeType: RuntimeType?
  var aicoreReleaseStage: AICoreModelReleaseStage?
  var aicorePreference: AICoreModelPreference?
  var parentModelName: String?
  var variantLabel: String?
  // Keyed by ModelCapability rawValue ("llm_thinking", "speculative_decoding") for
  // clean JSON decoding; converted to a typed map in toModel().
  var capabilityToTaskTypes: [String: [String]]?
  var updatableModelFiles: [ModelFile]?
  var updateInfo: String?

  func toModel() -> Model {
    var version = commitHash
    var downloadedFileName = modelFile
    var downloadUrl = url ?? "https://huggingface.co/\(modelId)/resolve/\(commitHash)/\(modelFile)?download=true"
    var size = sizeInBytes

    if let socMap = socToModelFiles, !socMap.isEmpty, let info = socMap[SOC] {
      version = info.commitHash ?? "-"
      downloadedFileName = info.modelFile ?? "-"
      downloadUrl = info.url ?? "https://huggingface.co/\(modelId)/resolve/\(info.commitHash ?? "")/\(info.modelFile ?? "")?download=true"
      size = info.sizeInBytes ?? -1
    }

    let isLlmModel =
      taskTypes.contains(BuiltInTaskId.LLM_CHAT) ||
      taskTypes.contains(BuiltInTaskId.LLM_PROMPT_LAB) ||
      taskTypes.contains(BuiltInTaskId.LLM_ASK_AUDIO) ||
      taskTypes.contains(BuiltInTaskId.LLM_ASK_IMAGE) ||
      taskTypes.contains(BuiltInTaskId.LLM_MOBILE_ACTIONS) ||
      taskTypes.contains(BuiltInTaskId.LLM_TINY_GARDEN)

    var configs: [Config] = []
    var llmMaxToken = 1024
    var accelerators: [Accelerator] = DEFAULT_ACCELERATORS
    var visionAccelerator: Accelerator = DEFAULT_VISION_ACCELERATOR

    var finalDescription = description
    var acceleratorsStr = defaultConfig.accelerators
    if Device.isPixelDevice() {
      finalDescription = description.replacingOccurrences(of: "NPU", with: "TPU")
      acceleratorsStr = acceleratorsStr?.replacingOccurrences(of: "npu", with: "tpu")
    }

    if isLlmModel {
      let defaultTopK = defaultConfig.topK ?? DEFAULT_TOPK
      let defaultTopP = defaultConfig.topP ?? DEFAULT_TOPP
      let defaultTemperature = defaultConfig.temperature ?? DEFAULT_TEMPERATURE
      llmMaxToken = defaultConfig.maxTokens ?? 1024
      let llmMaxContextLength = defaultConfig.maxContextLength
      if let accStr = acceleratorsStr {
        accelerators = []
        for item in accStr.split(separator: ",").map(String.init) {
          switch item {
          case "cpu": accelerators.append(.cpu)
          case "gpu": accelerators.append(.gpu)
          case "npu": accelerators.append(.npu)
          case "tpu": accelerators.append(.tpu)
          default: break
          }
        }
        if Device.isPixel10() { accelerators.removeAll { $0 == .gpu } }
      }
      if let va = defaultConfig.visionAccelerator {
        switch va {
        case "cpu": visionAccelerator = .cpu
        case "gpu": visionAccelerator = .gpu
        case "npu": visionAccelerator = .npu
        default: break
        }
      }
      let npuOnly = accelerators.count == 1 && (accelerators[0] == .npu || accelerators[0] == .tpu)
      if runtimeType == .aicore {
        configs = createAICoreConfigs(
          defaultMaxToken: llmMaxToken,
          defaultTopK: defaultTopK,
          defaultTemperature: defaultTemperature > 1.0 ? 1.0 : defaultTemperature,
          accelerators: accelerators)
      } else if npuOnly {
        configs = createLlmChatConfigsForNpuModel(defaultMaxToken: llmMaxToken, accelerators: accelerators)
      } else {
        configs = createLlmChatConfigs(
          defaultMaxToken: llmMaxToken,
          defaultMaxContextLength: llmMaxContextLength,
          defaultTopK: defaultTopK,
          defaultTopP: defaultTopP,
          defaultTemperature: defaultTemperature,
          accelerators: accelerators,
          supportThinking: capabilities?.contains(.llmThinking) == true,
          supportSpeculativeDecoding: capabilities?.contains(.speculativeDecoding) == true)
      }
    }

    var learnMoreUrl = "https://huggingface.co/\(modelId)"
    if runtimeType == .aicore {
      downloadUrl = ""
      learnMoreUrl = "https://developers.google.com/ml-kit/terms"
    }

    var showBenchmarkButton = true
    var showRunAgainButton = true
    if isLlmModel {
      showBenchmarkButton = false
      showRunAgainButton = false
    }

    return Model(
      name: name,
      info: finalDescription,
      configs: configs,
      learnMoreUrl: learnMoreUrl,
      bestForTaskIds: bestForTaskTypes ?? [],
      minDeviceMemoryInGb: minDeviceMemoryInGb,
      url: downloadUrl,
      sizeInBytes: size,
      downloadFileName: downloadedFileName,
      version: version,
      isLlm: isLlmModel,
      aicoreReleaseStage: aicoreReleaseStage,
      aicorePreference: aicorePreference,
      parentModelName: parentModelName,
      variantLabel: variantLabel,
      updatableModelFiles: updatableModelFiles ?? [],
      updateInfo: updateInfo ?? "",
      runtimeType: runtimeType ?? .litertLm,
      localModelFilePathOverride: localModelFilePathOverride ?? "",
      showRunAgainButton: showRunAgainButton,
      showBenchmarkButton: showBenchmarkButton,
      llmSupportImage: llmSupportImage == true,
      llmSupportAudio: llmSupportAudio == true,
      llmSupportTinyGarden: llmSupportTinyGarden == true,
      llmSupportMobileActions: llmSupportMobileActions == true,
      capabilities: capabilities ?? [],
      llmMaxToken: llmMaxToken,
      accelerators: accelerators,
      visionAccelerator: visionAccelerator,
      capabilityToTaskTypes: typedCapabilityToTaskTypes())
  }

  private func typedCapabilityToTaskTypes() -> [ModelCapability: [String]] {
    var result: [ModelCapability: [String]] = [:]
    for (k, v) in capabilityToTaskTypes ?? [:] {
      if let cap = ModelCapability(rawValue: k) { result[cap] = v }
    }
    return result
  }
}

// ModelFile is Codable for allowlist parsing.
extension ModelFile: Codable {}

struct NamedDeviceGroup: Codable {
  let groupName: String
  var description: String?
  let deviceModels: [String]
}

struct DeviceRequirements: Codable {
  var allowedDeviceGroups: [NamedDeviceGroup]?
}

/// The model allowlist. Mirrors `ModelAllowlist`.
struct ModelAllowlist: Codable {
  let models: [AllowedModel]
  var aicoreRequirements: DeviceRequirements?
}
