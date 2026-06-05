/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of data/Model.kt
//
// Kotlin uses a `data class Model` whose `var` fields are mutated in place while
// the instance is held inside `Task.models`. Swift models that with a reference
// type (`final class`) so `model.instance`, `model.configValues`, etc. mutate
// the shared object exactly like the Android app.

import Foundation

struct ModelDataFile {
  let name: String
  let url: String
  let downloadFileName: String
  let sizeInBytes: Int64
}

let IMPORTS_DIR = "__imports"
private let NORMALIZE_NAME_REGEX = try! NSRegularExpression(pattern: "[^a-zA-Z0-9]")

struct PromptTemplate {
  let title: String
  let description: String
  let prompt: String
}

enum ModelCapability: String, Codable {
  case llmThinking = "llm_thinking"
  case speculativeDecoding = "speculative_decoding"
}

enum RuntimeType: String, Codable {
  case unknown
  case litertLm = "litert_lm"
  case aicore
}

enum AICoreModelReleaseStage: String, Codable {
  case stable
  case preview
}

enum AICoreModelPreference: String, Codable {
  case fast
  case full
}

struct ModelFile: Equatable {
  let fileName: String
  let commitHash: String
}

/// A model for a `Task`. Mirrors `data.Model`.
final class Model {
  let name: String
  let displayName: String
  let info: String
  var configs: [Config]
  let learnMoreUrl: String
  let bestForTaskIds: [String]
  let minDeviceMemoryInGb: Int?

  // Download-related.
  let url: String
  let sizeInBytes: Int64
  var downloadFileName: String
  var version: String
  let extraDataFiles: [ModelDataFile]
  let isLlm: Bool
  let aicoreReleaseStage: AICoreModelReleaseStage?
  let aicorePreference: AICoreModelPreference?
  let parentModelName: String?
  let variantLabel: String?
  let updatableModelFiles: [ModelFile]
  let updateInfo: String

  let runtimeType: RuntimeType
  let localFileRelativeDirPathOverride: String
  let localModelFilePathOverride: String

  // Built-in task fields.
  let showRunAgainButton: Bool
  let showBenchmarkButton: Bool
  let isZip: Bool
  let unzipDir: String
  let llmPromptTemplates: [PromptTemplate]
  let llmSupportImage: Bool
  let llmSupportAudio: Bool
  let llmSupportTinyGarden: Bool
  let llmSupportMobileActions: Bool
  let capabilities: [ModelCapability]
  let llmMaxToken: Int
  let accelerators: [Accelerator]
  let visionAccelerator: Accelerator
  let imported: Bool
  let capabilityToTaskTypes: [ModelCapability: [String]]

  // App-managed fields.
  var normalizedName: String = ""
  var instance: Any?
  var initializing: Bool = false
  var cleanUpAfterInit: Bool = false
  var configValues: [String: Any] = [:]
  var prevConfigValues: [String: Any] = [:]
  var totalBytes: Int64 = 0
  var accessToken: String?
  var updatable: Bool = false
  var latestModelFile: ModelFile?

  init(
    name: String,
    displayName: String = "",
    info: String = "",
    configs: [Config] = [],
    learnMoreUrl: String = "",
    bestForTaskIds: [String] = [],
    minDeviceMemoryInGb: Int? = nil,
    url: String = "",
    sizeInBytes: Int64 = 0,
    downloadFileName: String = "_",
    version: String = "_",
    extraDataFiles: [ModelDataFile] = [],
    isLlm: Bool = false,
    aicoreReleaseStage: AICoreModelReleaseStage? = nil,
    aicorePreference: AICoreModelPreference? = nil,
    parentModelName: String? = nil,
    variantLabel: String? = nil,
    updatableModelFiles: [ModelFile] = [],
    updateInfo: String = "",
    runtimeType: RuntimeType = .unknown,
    localFileRelativeDirPathOverride: String = "",
    localModelFilePathOverride: String = "",
    showRunAgainButton: Bool = true,
    showBenchmarkButton: Bool = true,
    isZip: Bool = false,
    unzipDir: String = "",
    llmPromptTemplates: [PromptTemplate] = [],
    llmSupportImage: Bool = false,
    llmSupportAudio: Bool = false,
    llmSupportTinyGarden: Bool = false,
    llmSupportMobileActions: Bool = false,
    capabilities: [ModelCapability] = [],
    llmMaxToken: Int = 0,
    accelerators: [Accelerator] = [],
    visionAccelerator: Accelerator = .gpu,
    imported: Bool = false,
    capabilityToTaskTypes: [ModelCapability: [String]] = [:]
  ) {
    self.name = name
    self.displayName = displayName
    self.info = info
    self.configs = configs
    self.learnMoreUrl = learnMoreUrl
    self.bestForTaskIds = bestForTaskIds
    self.minDeviceMemoryInGb = minDeviceMemoryInGb
    self.url = url
    self.sizeInBytes = sizeInBytes
    self.downloadFileName = downloadFileName
    self.version = version
    self.extraDataFiles = extraDataFiles
    self.isLlm = isLlm
    self.aicoreReleaseStage = aicoreReleaseStage
    self.aicorePreference = aicorePreference
    self.parentModelName = parentModelName
    self.variantLabel = variantLabel
    self.updatableModelFiles = updatableModelFiles
    self.updateInfo = updateInfo
    self.runtimeType = runtimeType
    self.localFileRelativeDirPathOverride = localFileRelativeDirPathOverride
    self.localModelFilePathOverride = localModelFilePathOverride
    self.showRunAgainButton = showRunAgainButton
    self.showBenchmarkButton = showBenchmarkButton
    self.isZip = isZip
    self.unzipDir = unzipDir
    self.llmPromptTemplates = llmPromptTemplates
    self.llmSupportImage = llmSupportImage
    self.llmSupportAudio = llmSupportAudio
    self.llmSupportTinyGarden = llmSupportTinyGarden
    self.llmSupportMobileActions = llmSupportMobileActions
    self.capabilities = capabilities
    self.llmMaxToken = llmMaxToken
    self.accelerators = accelerators
    self.visionAccelerator = visionAccelerator
    self.imported = imported
    self.capabilityToTaskTypes = capabilityToTaskTypes
    self.normalizedName = Model.normalize(name)
  }

  static func normalize(_ name: String) -> String {
    let range = NSRange(name.startIndex..., in: name)
    return NORMALIZE_NAME_REGEX.stringByReplacingMatches(in: name, range: range, withTemplate: "_")
  }

  func preProcess() {
    var values: [String: Any] = [:]
    for config in configs {
      values[config.key.label] = config.defaultValue
    }
    configValues = values
    totalBytes = sizeInBytes + extraDataFiles.reduce(0) { $0 + $1.sizeInBytes }
  }

  /// On Android this resolves a path under getExternalFilesDir(); on iOS we use
  /// the app's Application Support directory as the per-app private file root.
  func getPath(fileName: String? = nil) -> String {
    let fileName = fileName ?? downloadFileName
    let base = FileSystem.appFilesDir.path
    if imported {
      return [base, fileName].joined(separator: "/")
    }
    if !localModelFilePathOverride.isEmpty {
      return localModelFilePathOverride
    }
    if !localFileRelativeDirPathOverride.isEmpty {
      return [base, localFileRelativeDirPathOverride, fileName].joined(separator: "/")
    }
    let baseDir = [base, normalizedName, version].joined(separator: "/")
    if isZip && !unzipDir.isEmpty {
      return [baseDir, unzipDir].joined(separator: "/")
    }
    return [baseDir, fileName].joined(separator: "/")
  }

  func getIntConfigValue(_ key: ConfigKey, default def: Int = 0) -> Int {
    convertValueToTargetType(value: configValues[key.label] ?? def, valueType: .int) as? Int ?? def
  }

  func getFloatConfigValue(_ key: ConfigKey, default def: Float = 0) -> Float {
    convertValueToTargetType(value: configValues[key.label] ?? def, valueType: .float) as? Float ?? def
  }

  func getBooleanConfigValue(_ key: ConfigKey, default def: Bool = false) -> Bool {
    convertValueToTargetType(value: configValues[key.label] ?? def, valueType: .boolean) as? Bool ?? def
  }

  func getStringConfigValue(_ key: ConfigKey, default def: String = "") -> String {
    convertValueToTargetType(value: configValues[key.label] ?? def, valueType: .string) as? String ?? def
  }

  func getExtraDataFile(name: String) -> ModelDataFile? {
    extraDataFiles.first { $0.name == name }
  }
}

extension Model: Identifiable, Hashable {
  var id: String { name }
  static func == (lhs: Model, rhs: Model) -> Bool { lhs === rhs }
  func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

enum ModelDownloadStatusType {
  case notDownloaded
  case partiallyDownloaded
  case inProgress
  case unzipping
  case succeeded
  case failed
}

struct ModelDownloadStatus {
  let status: ModelDownloadStatusType
  var totalBytes: Int64 = 0
  var receivedBytes: Int64 = 0
  var errorMessage: String = ""
  var bytesPerSecond: Int64 = 0
  var remainingMs: Int64 = 0
}

let EMPTY_MODEL = Model(name: "empty", downloadFileName: "empty.tflite", url: "", sizeInBytes: 0)
