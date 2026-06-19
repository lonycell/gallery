/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/llmsingleturn/LlmSingleTurnScreen.kt
//
// The Prompt Lab screen. Combines a draggable VerticalSplitView with a
// PromptTemplatesPanel (top) and ResponsePanel (bottom), with the same
// model-download overlay and error dialog as the Android original.

import SwiftUI

private let TAG = "AGLlmSingleTurnScreen"

struct LlmSingleTurnScreen: View {
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  let navigateUp: () -> Void

  @StateObject private var viewModel: LlmSingleTurnViewModel

  @State private var showErrorDialog = false
  @State private var navigatingUp = false

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  init(
    modelManagerViewModel: ModelManagerViewModel,
    navigateUp: @escaping () -> Void,
    viewModel: LlmSingleTurnViewModel
  ) {
    self.modelManagerViewModel = modelManagerViewModel
    self.navigateUp = navigateUp
    self._viewModel = StateObject(wrappedValue: viewModel)
  }

  private var task: Task? { modelManagerViewModel.getTaskById(BuiltInTaskId.LLM_PROMPT_LAB) }
  private var uiState: ModelManagerUiState { modelManagerViewModel.uiState }
  private var selectedModel: Model { uiState.selectedModel }
  private var curDownloadStatus: ModelDownloadStatus? { uiState.modelDownloadStatus[selectedModel.name] }
  private var modelDownloaded: Bool { curDownloadStatus?.status == .succeeded }
  private var modelInitializationStatus: ModelInitializationStatus? {
    uiState.modelInitializationStatus[selectedModel.name]
  }

  var body: some View {
    Group {
      if let task {
        ZStack {
          mainContent(task: task)

          // Download overlay — shown when model is not yet available.
          if !modelDownloaded {
            ModelDownloadStatusInfoPanel(
              model: selectedModel,
              task: task,
              modelManagerViewModel: modelManagerViewModel)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
            .zIndex(1)
          }
        }
        .errorDialog(
          error: showErrorDialog ? (modelInitializationStatus?.error ?? "") : nil,
          onDismiss: { showErrorDialog = false })
        // Model-initialization-status observer.
        .onChange(of: modelInitializationStatus?.status) { _, status in
          showErrorDialog = status == .error
        }
        // Auto-initialize when download completes.
        .onChange(of: curDownloadStatus?.status) { _, status in
          guard !navigatingUp, status == .succeeded else { return }
          print("\(TAG): Initializing model '\(selectedModel.name)' after download")
          modelManagerViewModel.initializeModel(task: task, model: selectedModel)
        }
        .onAppear {
          if modelDownloaded {
            modelManagerViewModel.initializeModel(task: task, model: selectedModel)
          }
        }
      } else {
        EmptyView()
      }
    }
  }

  @ViewBuilder
  private func mainContent(task: Task) -> some View {
    VStack(spacing: 0) {
      // App bar.
      ModelPageAppBar(
        task: task,
        model: selectedModel,
        modelManagerViewModel: modelManagerViewModel,
        onBackClicked: {
          handleNavigateUp(task: task)
        },
        onModelSelected: { prevModel, newModel in
          if prevModel.name != newModel.name {
            modelManagerViewModel.cleanupModel(task: task, model: prevModel)
          }
          modelManagerViewModel.selectModel(newModel)
        },
        inProgress: viewModel.uiState.inProgress,
        modelPreparing: viewModel.uiState.preparing,
        onConfigChanged: { _, _ in })

      // Main split layout (fades in when model is downloaded).
      VerticalSplitView(
        topView: {
          PromptTemplatesPanel(
            model: selectedModel,
            viewModel: viewModel,
            modelManagerViewModel: modelManagerViewModel,
            onSend: { fullPrompt in
              viewModel.generateResponse(
                task: task,
                model: selectedModel,
                input: fullPrompt)
            },
            onStopButtonClicked: { model in
              viewModel.stopResponse(model: model)
            })
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        },
        bottomView: {
          ResponsePanel(
            task: task,
            model: selectedModel,
            viewModel: viewModel,
            modelManagerViewModel: modelManagerViewModel)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        })
      .opacity(modelDownloaded ? 1 : 0)
      .animation(.easeInOut(duration: 0.2), value: modelDownloaded)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func handleNavigateUp(task: Task) {
    navigatingUp = true
    navigateUp()
    // Clean up all models on nav-up (mirrors Android scope.launch cleanup).
    _Concurrency.Task {
      for model in task.models {
        modelManagerViewModel.cleanupModel(task: task, model: model)
      }
    }
  }
}
