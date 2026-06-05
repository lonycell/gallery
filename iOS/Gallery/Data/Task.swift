/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of data/Tasks.kt

import Foundation

/// How a task's tile icon is rendered. On Android this was either a Compose
/// `ImageVector` (`icon`) or a vector drawable resource (`iconVectorResourceId`).
/// On iOS we map both onto an SF Symbol name or an asset-catalog image name.
enum TaskIconSpec: Equatable {
  case system(String)   // SF Symbol name
  case asset(String)    // Asset catalog image name
}

/// A task displayed on the home screen. Mirrors `data.Task`.
///
/// Reference type because the app mutates `index` and bumps `updateTrigger`
/// in place while the task lives inside the model-manager's task list.
final class Task: Identifiable, ObservableObject {
  let id: String
  let label: String
  let category: CategoryInfo
  let icon: TaskIconSpec?
  /// Asset/SF-symbol name taking precedence over `icon` (was `iconVectorResourceId`).
  let iconVectorAssetName: String?
  let description: String
  let shortDescription: String
  let docUrl: String
  let sourceCodeUrl: String
  var models: [Model]
  let modelNames: [String]
  let handleModelConfigChangesInTask: Bool
  let experimental: Bool
  let newFeature: Bool
  let useThemeColor: Bool
  let defaultSystemPrompt: String

  // Built-in task fields.
  let agentName: String
  let textInputPlaceHolder: String

  // App-managed.
  var index: Int = -1
  /// Equivalent of Kotlin's `MutableState<Long>` redraw trigger.
  @Published var updateTrigger: Int64 = 0

  init(
    id: String,
    label: String,
    category: CategoryInfo,
    icon: TaskIconSpec? = nil,
    iconVectorAssetName: String? = nil,
    description: String,
    shortDescription: String = "",
    docUrl: String = "",
    sourceCodeUrl: String = "",
    models: [Model],
    modelNames: [String] = [],
    handleModelConfigChangesInTask: Bool = false,
    experimental: Bool = false,
    newFeature: Bool = false,
    useThemeColor: Bool = false,
    defaultSystemPrompt: String = "",
    agentName: String = Str.chatGenericAgentName,
    textInputPlaceHolder: String = Str.chatTextinputPlaceholder
  ) {
    self.id = id
    self.label = label
    self.category = category
    self.icon = icon
    self.iconVectorAssetName = iconVectorAssetName
    self.description = description
    self.shortDescription = shortDescription
    self.docUrl = docUrl
    self.sourceCodeUrl = sourceCodeUrl
    self.models = models
    self.modelNames = modelNames
    self.handleModelConfigChangesInTask = handleModelConfigChangesInTask
    self.experimental = experimental
    self.newFeature = newFeature
    self.useThemeColor = useThemeColor
    self.defaultSystemPrompt = defaultSystemPrompt
    self.agentName = agentName
    self.textInputPlaceHolder = textInputPlaceHolder
  }

  func allowCapability(_ capability: ModelCapability, model: Model) -> Bool {
    model.capabilityToTaskTypes[capability]?.contains(id) == true
  }

  /// SF Symbol name for the tile icon (used by `TaskIcon`). Resolves the
  /// `iconVectorAssetName`/`icon` spec to a system symbol when one applies.
  var sfSymbol: String? {
    if case .system(let name)? = icon { return name }
    if let asset = iconVectorAssetName { return asset }
    return nil
  }
}

/// Reserved ids for built-in tasks. Mirrors `object BuiltInTaskId`.
enum BuiltInTaskId {
  static let LLM_CHAT = "llm_chat"
  static let LLM_PROMPT_LAB = "llm_prompt_lab"
  static let LLM_ASK_IMAGE = "llm_ask_image"
  static let LLM_ASK_AUDIO = "llm_ask_audio"
  static let LLM_MOBILE_ACTIONS = "llm_mobile_actions"
  static let LLM_TINY_GARDEN = "llm_tiny_garden"
  static let MP_SCRAPBOOK = "mp_scrapbook"
  static let LLM_AGENT_CHAT = "llm_agent_chat"
}

private let allLegacyTaskIds: Set<String> = [
  BuiltInTaskId.LLM_CHAT,
  BuiltInTaskId.LLM_PROMPT_LAB,
  BuiltInTaskId.LLM_ASK_IMAGE,
  BuiltInTaskId.LLM_ASK_AUDIO,
  BuiltInTaskId.LLM_AGENT_CHAT,
]

func isLegacyTasks(_ id: String) -> Bool {
  allLegacyTaskIds.contains(id)
}
