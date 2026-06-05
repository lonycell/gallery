/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/llmsingleturn/LlmSingleTurnViewModel.kt
//
// Single-turn (Prompt Lab) view model. Unlike the chat VM, this one is NOT a
// subclass of ChatViewModel — it maintains its own per-model/per-template
// response map and tracks inProgress/preparing state directly.

import Foundation
import Combine

private let TAG = "AGLlmSingleTurnVM"

// MARK: - UI State

struct LlmSingleTurnUiState {
  var inProgress: Bool = false
  var preparing: Bool = false
  /// model.name → (templateLabel → response string)
  var responsesByModel: [String: [String: String]] = [:]
  var selectedPromptTemplateType: PromptTemplateType = PromptTemplateType.allCases[0]
}

// MARK: - LlmSingleTurnViewModel

@MainActor
final class LlmSingleTurnViewModel: ObservableObject {

  @Published private(set) var uiState = LlmSingleTurnUiState()

  /// Injected runtime — set by the task module's factory.
  var llmModelHelper: LlmModelHelper

  init(llmModelHelper: LlmModelHelper = StubLlmModelHelper()) {
    self.llmModelHelper = llmModelHelper
  }

  // MARK: - Inference

  func generateResponse(task: Task, model: Model, input: String) {
    let helper = llmModelHelper
    Task { [weak self] in
      guard let self else { return }
      self.setInProgress(true)
      self.setPreparing(true)

      // Wait for model instance.
      var waited = 0
      while model.instance == nil {
        try? await Task.sleep(nanoseconds: 100_000_000)
        waited += 1
        if waited > 600 { break }
      }

      // Reset conversation before each single-turn call (mirrors Android).
      helper.resetConversation(model: model)
      try? await Task.sleep(nanoseconds: 500_000_000) // 500 ms

      var firstRun = true
      var response = ""
      let templateType = self.uiState.selectedPromptTemplateType

      helper.runInference(
        model: model,
        input: input,
        resultListener: { [weak self] partialResult, done, _ in
          guard let self else { return }
          Task { @MainActor [weak self] in
            guard let self else { return }
            if firstRun {
              firstRun = false
              self.setPreparing(false)
            }
            response = processLlmResponse(response: "\(response)\(partialResult)")
            self.updateResponse(model: model, promptTemplateType: templateType, response: response)
            if done { self.setInProgress(false) }
          }
        },
        cleanUpListener: { [weak self] in
          Task { @MainActor [weak self] in
            self?.setPreparing(false)
            self?.setInProgress(false)
          }
        },
        onError: { [weak self] _ in
          Task { @MainActor [weak self] in
            self?.setPreparing(false)
            self?.setInProgress(false)
          }
        })
    }
  }

  // MARK: - State mutations

  func selectPromptTemplate(model: Model, promptTemplateType: PromptTemplateType) {
    print("\(TAG): selecting prompt template: \(promptTemplateType.label)")
    updateResponse(model: model, promptTemplateType: promptTemplateType, response: "")
    uiState.selectedPromptTemplateType = promptTemplateType
  }

  func setInProgress(_ inProgress: Bool) { uiState.inProgress = inProgress }
  func setPreparing(_ preparing: Bool)   { uiState.preparing = preparing }

  func updateResponse(model: Model, promptTemplateType: PromptTemplateType, response: String) {
    var byModel = uiState.responsesByModel
    var modelResponses = byModel[model.name] ?? [:]
    modelResponses[promptTemplateType.label] = response
    byModel[model.name] = modelResponses
    uiState.responsesByModel = byModel
  }

  func stopResponse(model: Model) {
    print("\(TAG): Stopping response for model \(model.name)...")
    setInProgress(false)
    llmModelHelper.stopResponse(model: model)
  }
}
