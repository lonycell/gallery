/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/llmchat/LlmChatTaskModule.kt
//
// Defines three `CustomTask` factories:
//   makeChat()     → LLM_CHAT
//   makeAskImage() → LLM_ASK_IMAGE
//   makeAskAudio() → LLM_ASK_AUDIO
//
// Each factory creates the `Task` metadata and wires up initialize/cleanUp/
// mainScreen using `LlmChatModelHelper` (which delegates to the injected
// `LlmModelHelper` runtime).  The integrator adds these to BuiltInTasks.swift
// or CustomTaskRegistry without touching this file.

import SwiftUI

// MARK: - LlmChatTaskModule

enum LlmChatTaskModule {

  // MARK: AI Chat

  static func makeChat(llmModelHelper: LlmModelHelper = StubLlmModelHelper()) -> CustomTask {
    LlmChatCustomTask(llmModelHelper: llmModelHelper)
  }

  // MARK: Ask Image

  static func makeAskImage(llmModelHelper: LlmModelHelper = StubLlmModelHelper()) -> CustomTask {
    LlmAskImageCustomTask(llmModelHelper: llmModelHelper)
  }

  // MARK: Ask Audio

  static func makeAskAudio(llmModelHelper: LlmModelHelper = StubLlmModelHelper()) -> CustomTask {
    LlmAskAudioCustomTask(llmModelHelper: llmModelHelper)
  }
}

// MARK: - LlmChatCustomTask (LLM_CHAT)

private final class LlmChatCustomTask: CustomTask {
  let task: Task
  private let helper: LlmChatModelHelper

  init(llmModelHelper: LlmModelHelper) {
    self.helper = LlmChatModelHelper(delegate: llmModelHelper)
    self.task = Task(
      id: BuiltInTaskId.LLM_CHAT,
      label: "AI Chat",
      category: Category.LLM,
      icon: .system("bubble.left.and.bubble.right"),
      description: "Chat with on-device large language models",
      shortDescription: "Chat with an on-device LLM",
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
    return AnyView(LlmChatScreenEntry(taskData: taskData, helper: helper))
  }
}

/// Entry view for LLM_CHAT that owns the view model lifecycle.
private struct LlmChatScreenEntry: View {
  let taskData: CustomTaskDataForBuiltinTask
  let helper: LlmChatModelHelper

  @StateObject private var viewModel: LlmChatViewModel
  @State private var systemPrompt: String = ""
  @State private var systemPromptLoaded = false

  init(taskData: CustomTaskDataForBuiltinTask, helper: LlmChatModelHelper) {
    self.taskData = taskData
    self.helper = helper
    self._viewModel = StateObject(
      wrappedValue: LlmChatViewModel(
        systemPromptRepository: taskData.modelManagerViewModel.systemPromptRepository,
        store: taskData.modelManagerViewModel.dataStoreRepository,
        llmModelHelper: helper))
  }

  var body: some View {
    LlmChatScreen(
      modelManagerViewModel: taskData.modelManagerViewModel,
      navigateUp: taskData.onNavUp,
      taskId: BuiltInTaskId.LLM_CHAT,
      viewModel: viewModel,
      allowEditingSystemPrompt: true,
      curSystemPrompt: systemPrompt,
      onSystemPromptChanged: { newPrompt in
        let selectedModel = taskData.modelManagerViewModel.uiState.selectedModel
        guard let task = taskData.modelManagerViewModel.getTaskById(BuiltInTaskId.LLM_CHAT) else { return }
        viewModel.applySystemPromptChange(
          task: task,
          model: selectedModel,
          newPrompt: newPrompt,
          systemPromptUpdatedMessage: Str.systemPromptUpdated)
      },
      emptyStateView: { _ in
        AnyView(
          VStack(spacing: 12) {
            Spacer()
            Text(Str.aichatEmptystateTitle)
              .font(AppTypography.titleMedium)
              .multilineTextAlignment(.center)
            Text(Str.aichatEmptystateContent)
              .font(AppTypography.bodyMedium)
              .multilineTextAlignment(.center)
              .foregroundStyle(.secondary)
            Spacer()
          }
          .padding(.horizontal, 48)
          .padding(.bottom, 48)
        )
      },
      showImagePicker: false,
      showAudioPicker: false)
    .task {
      guard !systemPromptLoaded,
            let task = taskData.modelManagerViewModel.getTaskById(BuiltInTaskId.LLM_CHAT)
      else { return }
      systemPromptLoaded = true
      viewModel.loadSystemPrompt(task: task)
    }
    .onReceive(viewModel.$uiSystemPrompt) { prompt in
      systemPrompt = prompt
    }
  }
}

// MARK: - LlmAskImageCustomTask (LLM_ASK_IMAGE)

private final class LlmAskImageCustomTask: CustomTask {
  let task: Task
  private let helper: LlmChatModelHelper

  init(llmModelHelper: LlmModelHelper) {
    self.helper = LlmChatModelHelper(delegate: llmModelHelper)
    self.task = Task(
      id: BuiltInTaskId.LLM_ASK_IMAGE,
      label: "Ask Image",
      category: Category.LLM,
      icon: .system("photo.on.rectangle.angled"),
      description: "Ask questions about images with on-device large language models",
      shortDescription: "Ask questions about images",
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
    helper.initialize(
      model: model,
      taskId: task.id,
      supportImage: true,
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
    return AnyView(LlmAskImageScreenEntry(taskData: taskData, helper: helper))
  }
}

private struct LlmAskImageScreenEntry: View {
  let taskData: CustomTaskDataForBuiltinTask
  let helper: LlmChatModelHelper

  @StateObject private var viewModel: LlmAskImageViewModel
  @State private var systemPrompt: String = ""

  init(taskData: CustomTaskDataForBuiltinTask, helper: LlmChatModelHelper) {
    self.taskData = taskData
    self.helper = helper
    self._viewModel = StateObject(
      wrappedValue: LlmAskImageViewModel(
        systemPromptRepository: taskData.modelManagerViewModel.systemPromptRepository,
        store: taskData.modelManagerViewModel.dataStoreRepository,
        llmModelHelper: helper))
  }

  var body: some View {
    LlmAskImageScreen(
      modelManagerViewModel: taskData.modelManagerViewModel,
      navigateUp: taskData.onNavUp,
      viewModel: viewModel,
      allowEditingSystemPrompt: true,
      curSystemPrompt: systemPrompt,
      onSystemPromptChanged: { newPrompt in
        let selectedModel = taskData.modelManagerViewModel.uiState.selectedModel
        guard let task = taskData.modelManagerViewModel.getTaskById(BuiltInTaskId.LLM_ASK_IMAGE) else { return }
        viewModel.applySystemPromptChange(
          task: task,
          model: selectedModel,
          newPrompt: newPrompt,
          systemPromptUpdatedMessage: Str.systemPromptUpdated)
      })
    .task {
      guard let task = taskData.modelManagerViewModel.getTaskById(BuiltInTaskId.LLM_ASK_IMAGE) else { return }
      viewModel.loadSystemPrompt(task: task)
    }
    .onReceive(viewModel.$uiSystemPrompt) { prompt in
      systemPrompt = prompt
    }
  }
}

// MARK: - LlmAskAudioCustomTask (LLM_ASK_AUDIO)

private final class LlmAskAudioCustomTask: CustomTask {
  let task: Task
  private let helper: LlmChatModelHelper

  init(llmModelHelper: LlmModelHelper) {
    self.helper = LlmChatModelHelper(delegate: llmModelHelper)
    self.task = Task(
      id: BuiltInTaskId.LLM_ASK_AUDIO,
      label: "Audio Scribe",
      category: Category.LLM,
      icon: .system("mic"),
      description:
        "Instantly transcribe and/or translate audio clips using on-device large language models",
      shortDescription: "Transcribe and translate audio",
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
    helper.initialize(
      model: model,
      taskId: task.id,
      supportImage: false,
      supportAudio: true,
      systemInstruction: systemInstruction,
      onDone: onDone)
  }

  func cleanUpModelFn(model: Model, onDone: @escaping () -> Void) {
    helper.cleanUp(model: model, onDone: onDone)
  }

  @MainActor
  func mainScreen(data: Any) -> AnyView {
    guard let taskData = data as? CustomTaskDataForBuiltinTask else { return AnyView(EmptyView()) }
    return AnyView(LlmAskAudioScreenEntry(taskData: taskData, helper: helper))
  }
}

private struct LlmAskAudioScreenEntry: View {
  let taskData: CustomTaskDataForBuiltinTask
  let helper: LlmChatModelHelper

  @StateObject private var viewModel: LlmAskAudioViewModel
  @State private var systemPrompt: String = ""

  init(taskData: CustomTaskDataForBuiltinTask, helper: LlmChatModelHelper) {
    self.taskData = taskData
    self.helper = helper
    self._viewModel = StateObject(
      wrappedValue: LlmAskAudioViewModel(
        systemPromptRepository: taskData.modelManagerViewModel.systemPromptRepository,
        store: taskData.modelManagerViewModel.dataStoreRepository,
        llmModelHelper: helper))
  }

  var body: some View {
    LlmAskAudioScreen(
      modelManagerViewModel: taskData.modelManagerViewModel,
      navigateUp: taskData.onNavUp,
      viewModel: viewModel,
      allowEditingSystemPrompt: true,
      curSystemPrompt: systemPrompt,
      onSystemPromptChanged: { newPrompt in
        let selectedModel = taskData.modelManagerViewModel.uiState.selectedModel
        guard let task = taskData.modelManagerViewModel.getTaskById(BuiltInTaskId.LLM_ASK_AUDIO) else { return }
        viewModel.applySystemPromptChange(
          task: task,
          model: selectedModel,
          newPrompt: newPrompt,
          systemPromptUpdatedMessage: Str.systemPromptUpdated)
      })
    .task {
      guard let task = taskData.modelManagerViewModel.getTaskById(BuiltInTaskId.LLM_ASK_AUDIO) else { return }
      viewModel.loadSystemPrompt(task: task)
    }
    .onReceive(viewModel.$uiSystemPrompt) { prompt in
      systemPrompt = prompt
    }
  }
}
