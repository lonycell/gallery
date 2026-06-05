/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/llmsingleturn/LlmSingleTurnTaskModule.kt
//
// Exposes a single factory: `LlmSingleTurnTaskModule.make()` → LLM_PROMPT_LAB
//
// The implementation reuses `LlmChatModelHelper` for initialize/cleanUp,
// exactly as the Android port did (LlmSingleTurnTask delegated to
// LlmChatModelHelper). The `LlmSingleTurnViewModel` is constructed with the
// injected `LlmModelHelper` so inference flows through the same helper chain.

import SwiftUI

enum LlmSingleTurnTaskModule {
  static func make(llmModelHelper: LlmModelHelper = StubLlmModelHelper()) -> CustomTask {
    LlmSingleTurnCustomTask(llmModelHelper: llmModelHelper)
  }
}

// MARK: - LlmSingleTurnCustomTask (LLM_PROMPT_LAB)

private final class LlmSingleTurnCustomTask: CustomTask {
  let task: Task
  private let helper: LlmChatModelHelper

  init(llmModelHelper: LlmModelHelper) {
    self.helper = LlmChatModelHelper(delegate: llmModelHelper)
    self.task = Task(
      id: BuiltInTaskId.LLM_PROMPT_LAB,
      label: "Prompt Lab",
      category: Category.LLM,
      icon: .system("slider.horizontal.3"),
      description: "Single turn use cases with on-device large language models",
      shortDescription: "Single turn use cases",
      docUrl: "https://github.com/google-ai-edge/LiteRT-LM/blob/main/kotlin/README.md",
      sourceCodeUrl:
        "https://github.com/google-ai-edge/gallery/blob/main/Android/src/app/src/main/java/com/google/ai/edge/gallery/ui/llmchat/LlmChatModelHelper.kt",
      models: [],
      textInputPlaceHolder: Str.chatTextinputPlaceholder)
  }

  func initializeModelFn(
    model: Model,
    systemInstruction: Contents?,
    onDone: @escaping (_ error: String) -> Void
  ) {
    // Reuses LlmChatModelHelper — same as Android's LlmSingleTurnTask.
    helper.initialize(
      model: model,
      taskId: task.id,
      supportImage: false,
      supportAudio: false,
      systemInstruction: systemInstruction,
      onDone: onDone)
  }

  func cleanUpModelFn(model: Model, onDone: @escaping () -> Void) {
    helper.cleanUp(model: model, onDone: onDone)
  }

  @MainActor
  func mainScreen(data: Any) -> AnyView {
    guard let taskData = data as? CustomTaskDataForBuiltinTask else { return AnyView(EmptyView()) }
    return AnyView(LlmSingleTurnScreenEntry(taskData: taskData, helper: helper))
  }
}

// MARK: - Entry view

private struct LlmSingleTurnScreenEntry: View {
  let taskData: CustomTaskDataForBuiltinTask
  let helper: LlmChatModelHelper

  @StateObject private var viewModel: LlmSingleTurnViewModel

  init(taskData: CustomTaskDataForBuiltinTask, helper: LlmChatModelHelper) {
    self.taskData = taskData
    self.helper = helper
    self._viewModel = StateObject(
      wrappedValue: LlmSingleTurnViewModel(llmModelHelper: helper))
  }

  var body: some View {
    LlmSingleTurnScreen(
      modelManagerViewModel: taskData.modelManagerViewModel,
      navigateUp: taskData.onNavUp,
      viewModel: viewModel)
  }
}
