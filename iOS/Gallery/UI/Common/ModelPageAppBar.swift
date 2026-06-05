/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/ModelPageAppBar.kt
//
// NOTE: The Android version called com.google.ai.edge.litertlm.Capabilities to
// check speculative-decoding support. On iOS that native library is not yet
// bridged; we conservatively hide the ENABLE_SPECULATIVE_DECODING config unless
// the task explicitly allows it and a future bridge sets a flag on the model.

import SwiftUI

// MARK: - TaskIconImage helper

/// Renders the icon for a task using either an SF Symbol or an asset-catalog image.
struct TaskIconImage: View {
  let task: Task
  var size: CGFloat = 24

  var body: some View {
    switch task.icon {
    case .system(let name):
      Image(systemName: name)
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
    case .asset(let name):
      Image(name)
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
    case nil:
      Image(systemName: "sparkles")
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
    }
  }
}

// MARK: - ModelPageAppBar

/// Top navigation bar used by every model-page screen.
/// Mirrors `ModelPageAppBar` composable.
struct ModelPageAppBar: View {
  let task: Task
  let model: Model
  let modelManagerViewModel: ModelManagerViewModel
  let onBackClicked: () -> Void
  let onModelSelected: (_ prev: Model, _ cur: Model) -> Void
  let inProgress: Bool
  let modelPreparing: Bool
  var hideModelSelector: Bool = false
  var useThemeColor: Bool = false
  var onConfigChanged: (_ old: [String: Any], _ new: [String: Any]) -> Void = { _, _ in }
  var allowEditingSystemPrompt: Bool = false
  var curSystemPrompt: String = ""
  var onSystemPromptChanged: (String) -> Void = { _ in }
  var shouldShowHistoryButton: Bool = false
  var onHistoryClicked: (Model) -> Void = { _ in }

  @State private var showConfigDialog: Bool = false

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  // MARK: Derived state

  private var curDownloadStatus: ModelDownloadStatus? {
    modelManagerViewModel.uiState.modelDownloadStatus[model.name]
  }
  private var modelInitStatus: ModelInitializationStatus? {
    modelManagerViewModel.uiState.modelInitializationStatus[model.name]
  }
  private var isModelInitializing: Bool { modelInitStatus?.status == .initializing }
  private var isModelInitialized: Bool { modelInitStatus?.status == .initialized }
  private var downloadSucceeded: Bool { curDownloadStatus?.status == .succeeded }

  private var tintColor: Color {
    useThemeColor
      ? colors.onSurface
      : getTaskIconColor(task: task, customColors: customColors)
  }

  // MARK: Body

  var body: some View {
    ZStack {
      // Back button (leading)
      HStack {
        Button {
          onBackClicked()
        } label: {
          Image(systemName: "arrow.backward")
            .imageScale(.medium)
            .foregroundStyle(colors.onSurface)
        }
        .disabled(isModelInitializing || inProgress)
        .opacity((isModelInitializing || inProgress) ? 0.5 : 1)
        .padding(.leading, 8)
        Spacer()
      }

      // Center: task icon + title + model picker
      VStack(spacing: 4) {
        HStack(spacing: 10) {
          TaskIconImage(task: task, size: 24)
            .foregroundStyle(tintColor)
          Text(task.label)
            .font(AppTypography.titleMedium)
            .foregroundStyle(tintColor)
        }
        if !hideModelSelector {
          ModelPickerChip(
            enabled: !isModelInitializing && !inProgress,
            task: task,
            initialModel: model,
            modelManagerViewModel: modelManagerViewModel,
            onModelSelected: onModelSelected
          )
        }
      }

      // Trailing: config + history buttons
      HStack {
        Spacer()
        if downloadSucceeded && !model.configs.isEmpty {
          let enableConfig = !isModelInitializing && !inProgress && isModelInitialized
          Button {
            showConfigDialog = true
          } label: {
            Image(systemName: "slider.horizontal.3")
              .imageScale(.medium)
              .foregroundStyle(colors.onSurface)
          }
          .disabled(!enableConfig)
          .opacity(enableConfig ? 1 : 0.5)
        }
        if downloadSucceeded && shouldShowHistoryButton {
          let enableHistory = !isModelInitializing && !modelPreparing && !inProgress && isModelInitialized
          Button {
            onHistoryClicked(model)
          } label: {
            Image(systemName: "clock.arrow.circlepath")
              .imageScale(.medium)
              .foregroundStyle(colors.onSurface)
          }
          .disabled(!enableHistory)
          .opacity(enableHistory ? 1 : 0.5)
        }
      }
      .padding(.trailing, 8)
    }
    .frame(height: 56)
    .background(colors.surface)
    // Config dialog overlay
    .overlay {
      if showConfigDialog {
        configDialogView
      }
    }
  }

  // MARK: Config dialog

  @ViewBuilder
  private var configDialogView: some View {
    let modelConfigs = filteredConfigs()
    ConfigDialog(
      title: "Configurations",
      configs: modelConfigs,
      initialValues: model.configValues,
      onDismissed: { showConfigDialog = false },
      onOk: { curConfigValues, oldSystemPrompt, newSystemPrompt in
        showConfigDialog = false

        // Check if values changed
        var changed = false
        var needReinit = false
        for config in modelConfigs {
          let key = config.key.label
          guard let oldAny = model.configValues[key],
                let newAny = curConfigValues[key] else { continue }
          let oldVal = convertValueToTargetType(value: oldAny, valueType: config.valueType)
          let newVal = convertValueToTargetType(value: newAny, valueType: config.valueType)
          if "\(oldVal)" != "\(newVal)" {
            changed = true
            if config.needReinitialization { needReinit = true }
            break
          }
        }

        if !changed {
          if newSystemPrompt != oldSystemPrompt { onSystemPromptChanged(newSystemPrompt) }
          return
        }

        let oldConfigValues = model.configValues
        model.prevConfigValues = oldConfigValues
        model.configValues = curConfigValues
        modelManagerViewModel.updateConfigValuesUpdateTrigger()

        if !task.handleModelConfigChangesInTask {
          if needReinit {
            modelManagerViewModel.initializeModel(task: task, model: model, force: true)
            if oldSystemPrompt != newSystemPrompt { onSystemPromptChanged(newSystemPrompt) }
          }
          onConfigChanged(oldConfigValues, model.configValues)
        }
      },
      showSystemPromptEditorTab: allowEditingSystemPrompt && model.runtimeType != .aicore,
      defaultSystemPrompt: task.defaultSystemPrompt,
      curSystemPrompt: curSystemPrompt
    )
  }

  private func filteredConfigs() -> [Config] {
    var configs = model.configs
    if task.id != BuiltInTaskId.LLM_TINY_GARDEN {
      configs.removeAll { $0.key == ConfigKeys.RESET_CONVERSATION_TURN_COUNT }
    }
    if !task.allowCapability(.llmThinking, model: model) {
      configs.removeAll { $0.key == ConfigKeys.ENABLE_THINKING }
    }
    // NOTE: Speculative-decoding capability check requires LiteRT native bridge.
    // Conservatively remove the config unless the task/model explicitly supports it.
    if !task.allowCapability(.speculativeDecoding, model: model) {
      configs.removeAll { $0.key == ConfigKeys.ENABLE_SPECULATIVE_DECODING }
    }
    return configs
  }
}
