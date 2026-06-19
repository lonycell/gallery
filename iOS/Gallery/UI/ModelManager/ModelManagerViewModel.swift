/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/modelmanager/ModelManagerViewModel.kt
//
// The central app-state object: owns the task list, per-model download &
// initialization status, the selected model, text-input history, and the model
// allowlist load. Compose used a Hilt @HiltViewModel exposing a StateFlow; iOS
// uses an ObservableObject whose @Published `uiState` drives the SwiftUI tree.

import Foundation
import Combine

private let TAG = "AGModelManagerViewModel"
private let TEXT_INPUT_HISTORY_MAX_SIZE = 50
private let MODEL_ALLOWLIST_FILENAME = "model_allowlist.json"
private let ALLOWLIST_BASE_URL =
  "https://raw.githubusercontent.com/google-ai-edge/gallery/refs/heads/main/model_allowlists"

struct ModelInitializationStatus {
  let status: ModelInitializationStatusType
  var error: String = ""
  var initializedBackends: Set<String> = []

  func isFirstInitialization(model: Model) -> Bool {
    let backend = model.getStringConfigValue(ConfigKeys.ACCELERATOR, default: Accelerator.gpu.label)
    return !initializedBackends.contains(backend)
  }
}

enum ModelInitializationStatusType {
  case notInitialized
  case initializing
  case initialized
  case error
}

enum TokenStatus { case notStored, expired, notExpired }
enum TokenRequestResultType { case failed, succeeded, userCancelled }
struct TokenStatusAndData { let status: TokenStatus; let data: AccessTokenData? }
struct TokenRequestResult { let status: TokenRequestResultType; var errorMessage: String? = nil }

/// Mirrors `data class ModelManagerUiState`.
struct ModelManagerUiState {
  var tasks: [Task] = []
  var tasksByCategory: [String: [Task]] = [:]
  var modelDownloadStatus: [String: ModelDownloadStatus] = [:]
  var modelInitializationStatus: [String: ModelInitializationStatus] = [:]
  var loadingModelAllowlist: Bool = true
  var loadingModelAllowlistError: String = ""
  var selectedModel: Model = EMPTY_MODEL
  var textInputHistory: [String] = []
  var configValuesUpdateTrigger: Int64 = 0
  var modelImportingUpdateTrigger: Int64 = 0

  func isModelInitialized(_ model: Model) -> Bool {
    modelInitializationStatus[model.name]?.status == .initialized
  }
  func isModelInitializing(_ model: Model) -> Bool {
    modelInitializationStatus[model.name]?.status == .initializing
  }
}

@MainActor
final class ModelManagerViewModel: ObservableObject {
  @Published var uiState = ModelManagerUiState()

  let dataStoreRepository: DataStoreRepository
  let downloadRepository: DownloadRepository
  let systemPromptRepository: SystemPromptRepository
  private let llmModelHelper: LlmModelHelper
  /// Registered custom tasks (Hilt @IntoSet equivalent), keyed by task id.
  private(set) var customTasks: [CustomTask]

  private var appInForeground = true
  /// Flat list of `AllowedModel` items from the most recently loaded allowlist.
  /// Used by GlobalModelManager to sort the model list in allowlist order.
  var allowlistModels: [AllowedModel] = []

  init(dataStoreRepository: DataStoreRepository,
       downloadRepository: DownloadRepository,
       systemPromptRepository: SystemPromptRepository,
       llmModelHelper: LlmModelHelper,
       customTasks: [CustomTask]) {
    self.dataStoreRepository = dataStoreRepository
    self.downloadRepository = downloadRepository
    self.systemPromptRepository = systemPromptRepository
    self.llmModelHelper = llmModelHelper
    self.customTasks = customTasks
    uiState.textInputHistory = dataStoreRepository.readTextInputHistory()
  }

  // MARK: - Task / model lookup

  func getTaskById(_ id: String) -> Task? { uiState.tasks.first { $0.id == id } }
  func getTasksByIds(_ ids: Set<String>) -> [Task] { uiState.tasks.filter { ids.contains($0.id) } }
  func getCustomTaskByTaskId(_ id: String) -> CustomTask? { customTasks.first { $0.task.id == id } }
  func getActiveCustomTasks() -> [CustomTask] { customTasks }
  func getSelectedModel() -> Model? { uiState.selectedModel }

  func getModelByName(_ name: String) -> Model? {
    for task in uiState.tasks {
      if let m = task.models.first(where: { $0.name == name }) { return m }
    }
    return nil
  }

  func getAllModels() -> [Model] {
    var seen = Set<String>()
    var result: [Model] = []
    for task in uiState.tasks {
      for m in task.models where !seen.contains(m.name) {
        seen.insert(m.name); result.append(m)
      }
    }
    return result
  }

  func getAllDownloadedModels() -> [Model] {
    getAllModels().filter { isModelDownloaded($0) }
  }

  func isModelDownloaded(_ model: Model) -> Bool {
    uiState.modelDownloadStatus[model.name]?.status == .succeeded
  }

  func isModelInitialized(_ model: Model) -> Bool { uiState.isModelInitialized(model) }
  func isModelInitializing(_ model: Model) -> Bool { uiState.isModelInitializing(model) }

  // MARK: - Task processing

  /// Registers tasks from the custom-task list, assigns indices, groups by category,
  /// pre-processes models and seeds their download status. Mirrors `processTasks()`.
  func processTasks() {
    var tasks: [Task] = customTasks.map { $0.task }
    for (i, task) in tasks.enumerated() {
      task.index = i
      for model in task.models { model.preProcess() }
    }
    var byCategory: [String: [Task]] = [:]
    for task in tasks { byCategory[task.category.id, default: []].append(task) }

    var downloadStatus = uiState.modelDownloadStatus
    var initStatus = uiState.modelInitializationStatus
    for task in tasks {
      for model in task.models where downloadStatus[model.name] == nil {
        downloadStatus[model.name] = ModelDownloadStatus(
          status: isModelPartiallyDownloaded(model) ? .notDownloaded : .notDownloaded,
          totalBytes: model.totalBytes)
        initStatus[model.name] = ModelInitializationStatus(status: .notInitialized)
      }
    }
    uiState.tasks = tasks
    uiState.tasksByCategory = byCategory
    uiState.modelDownloadStatus = downloadStatus
    uiState.modelInitializationStatus = initStatus
  }

  private func isModelPartiallyDownloaded(_ model: Model) -> Bool {
    FileManager.default.fileExists(atPath: model.getPath())
  }

  func updateConfigValuesUpdateTrigger() {
    uiState.configValuesUpdateTrigger = currentTimeMillis()
  }

  // MARK: - Selection / download / init

  func selectModel(_ model: Model) {
    uiState.selectedModel = model
  }

  func cancelDownloadModel(_ model: Model) {
    downloadRepository.cancelDownloadModel(model: model)
    setDownloadStatus(curModel: model, status: ModelDownloadStatus(status: .notDownloaded))
  }

  func downloadModel(task: Task, model: Model) {
    setDownloadStatus(curModel: model, status: ModelDownloadStatus(status: .inProgress, totalBytes: model.totalBytes))
    downloadRepository.downloadModel(task: task, model: model) { [weak self] m, status in
      self?.setDownloadStatus(curModel: m, status: status)
    }
  }

  func deleteModel(_ model: Model) {
    try? FileManager.default.removeItem(atPath: model.getPath())
    setDownloadStatus(curModel: model, status: ModelDownloadStatus(status: .notDownloaded))
  }

  /// Initialize a model via its custom task (or the LLM helper for legacy tasks).
  func initializeModel(task: Task, model: Model, force: Bool = false) {
    if !force && (isModelInitialized(model) || isModelInitializing(model)) { return }
    setInitializationStatus(model: model, status: ModelInitializationStatus(status: .initializing))
    let onDone: (String) -> Void = { [weak self] error in
      guard let self else { return }
      if error.isEmpty {
        var backends = self.uiState.modelInitializationStatus[model.name]?.initializedBackends ?? []
        backends.insert(model.getStringConfigValue(ConfigKeys.ACCELERATOR, default: Accelerator.gpu.label))
        self.setInitializationStatus(model: model,
          status: ModelInitializationStatus(status: .initialized, initializedBackends: backends))
      } else {
        self.setInitializationStatus(model: model, status: ModelInitializationStatus(status: .error, error: error))
      }
    }
    if let custom = getCustomTaskByTaskId(task.id) {
      custom.initializeModelFn(model: model, systemInstruction: nil, onDone: onDone)
    } else {
      llmModelHelper.initialize(model: model, taskId: task.id, onDone: onDone)
    }
  }

  func cleanupModel(task: Task, model: Model, instanceToCleanUp: Any? = nil) {
    if let custom = getCustomTaskByTaskId(task.id) {
      custom.cleanUpModelFn(model: model) { [weak self] in
        self?.setInitializationStatus(model: model, status: ModelInitializationStatus(status: .notInitialized))
      }
    } else {
      llmModelHelper.cleanUp(model: model) { [weak self] in
        self?.setInitializationStatus(model: model, status: ModelInitializationStatus(status: .notInitialized))
      }
    }
  }

  func setDownloadStatus(curModel: Model, status: ModelDownloadStatus) {
    uiState.modelDownloadStatus[curModel.name] = status
  }

  func setInitializationStatus(model: Model, status: ModelInitializationStatus) {
    uiState.modelInitializationStatus[model.name] = status
  }

  // MARK: - Text input history

  func addTextInputHistory(_ text: String) {
    var history = uiState.textInputHistory
    history.removeAll { $0 == text }
    history.insert(text, at: 0)
    if history.count > TEXT_INPUT_HISTORY_MAX_SIZE { history = Array(history.prefix(TEXT_INPUT_HISTORY_MAX_SIZE)) }
    uiState.textInputHistory = history
    dataStoreRepository.saveTextInputHistory(history)
  }

  func promoteTextInputHistoryItem(_ text: String) {
    var history = uiState.textInputHistory
    history.removeAll { $0 == text }
    history.insert(text, at: 0)
    uiState.textInputHistory = history
    dataStoreRepository.saveTextInputHistory(history)
  }

  func deleteTextInputHistory(_ text: String) {
    var history = uiState.textInputHistory
    history.removeAll { $0 == text }
    uiState.textInputHistory = history
    dataStoreRepository.saveTextInputHistory(history)
  }

  func clearTextInputHistory() {
    uiState.textInputHistory = []
    dataStoreRepository.saveTextInputHistory([])
  }

  // MARK: - Theme

  func readThemeOverride() -> Theme { dataStoreRepository.readTheme() }
  func saveThemeOverride(_ theme: Theme) {
    dataStoreRepository.saveTheme(theme)
    ThemeSettings.shared.themeOverride = theme
  }

  // MARK: - App lifecycle

  func setAppInForeground(foreground: Bool) { appInForeground = foreground }

  // MARK: - Allowlist

  /// Loads and parses the model allowlist, building tasks' model lists from it.
  /// Mirrors `loadModelAllowlist()` (network fetch with bundled fallback).
  func loadModelAllowlist() {
    uiState.loadingModelAllowlist = true
    _Concurrency.Task { @MainActor in
      let allowlist = await Self.fetchAllowlist()
      if let allowlist {
        self.applyAllowlist(allowlist)
        self.uiState.loadingModelAllowlistError = ""
      } else {
        self.uiState.loadingModelAllowlistError = "Failed to load model list"
      }
      self.processTasks()
      self.uiState.loadingModelAllowlist = false
    }
  }

  func clearLoadModelAllowlistError() { uiState.loadingModelAllowlistError = "" }

  private static func fetchAllowlist() async -> ModelAllowlist? {
    // Try the remote allowlist, then the bundled copy (model_allowlist.json).
    let urlStr = "\(ALLOWLIST_BASE_URL)/\(MODEL_ALLOWLIST_FILENAME)"
    if let url = URL(string: urlStr),
       let (data, _) = try? await URLSession.shared.data(from: url),
       let parsed = try? JSONDecoder().decode(ModelAllowlist.self, from: data) {
      return parsed
    }
    if let bundled = Bundle.main.url(forResource: "model_allowlist", withExtension: "json"),
       let data = try? Data(contentsOf: bundled),
       let parsed = try? JSONDecoder().decode(ModelAllowlist.self, from: data) {
      return parsed
    }
    return nil
  }

  private func applyAllowlist(_ allowlist: ModelAllowlist) {
    let models = allowlist.models.filter { $0.disabled != true }.map { $0.toModel() }
    allowlistModels = allowlist.models.filter { $0.disabled != true }
    for task in uiState.tasks {
      // Attach allowlist models whose taskTypes include this task id, or that the
      // task explicitly names in `modelNames`.
      let matching = allowlist.models.enumerated().filter { (_, am) in
        am.taskTypes.contains(task.id) || task.modelNames.contains(am.name)
      }.map { models[$0.offset] }
      if !matching.isEmpty { task.models = matching }
      for m in task.models { m.preProcess() }
    }
  }
}
