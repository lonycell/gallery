/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/llmchat/LlmChatScreen.kt
//
// Three screens — LlmChatScreen, LlmAskImageScreen, LlmAskAudioScreen — all
// delegate to the shared `ChatViewWrapper` helper which embeds the foundation
// `ChatView` and wires up the `LlmChatViewModelBase` inference callbacks.

import SwiftUI
import UIKit

// MARK: - LlmChatScreen

struct LlmChatScreen: View {
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  let navigateUp: () -> Void

  // Optional customization hooks (mirrors Kotlin defaults).
  var taskId: String = BuiltInTaskId.LLM_CHAT
  var onFirstToken: (Model) -> Void = { _ in }
  var onGenerateResponseDone: (Model) -> Void = { _ in }
  var onSkillClicked: () -> Void = {}
  var onMcpClicked: () -> Void = {}
  var onResetSessionClickedOverride: ((Task, Model, [ChatMessage], Bool, () -> Void) -> Void)? = nil
  var composableBelowMessageList: ((Model) -> AnyView)? = nil
  var allowEditingSystemPrompt: Bool = false
  var curSystemPrompt: String = ""
  var onSystemPromptChanged: (String) -> Void = { _ in }
  var emptyStateView: ((Model) -> AnyView)? = nil
  var sendMessageTrigger: SendMessageTrigger? = nil
  var showImagePicker: Bool = false
  var showAudioPicker: Bool = false
  var skillCount: Int = 0
  var mcpCount: Int = 0

  @StateObject private var viewModel: LlmChatViewModel

  init(
    modelManagerViewModel: ModelManagerViewModel,
    navigateUp: @escaping () -> Void,
    taskId: String = BuiltInTaskId.LLM_CHAT,
    viewModel: LlmChatViewModel,
    allowEditingSystemPrompt: Bool = false,
    curSystemPrompt: String = "",
    onSystemPromptChanged: @escaping (String) -> Void = { _ in },
    emptyStateView: ((Model) -> AnyView)? = nil,
    sendMessageTrigger: SendMessageTrigger? = nil,
    showImagePicker: Bool = false,
    showAudioPicker: Bool = false,
    onFirstToken: @escaping (Model) -> Void = { _ in },
    onGenerateResponseDone: @escaping (Model) -> Void = { _ in },
    onSkillClicked: @escaping () -> Void = {},
    onMcpClicked: @escaping () -> Void = {},
    onResetSessionClickedOverride: ((Task, Model, [ChatMessage], Bool, () -> Void) -> Void)? = nil,
    composableBelowMessageList: ((Model) -> AnyView)? = nil,
    skillCount: Int = 0,
    mcpCount: Int = 0
  ) {
    self.modelManagerViewModel = modelManagerViewModel
    self.navigateUp = navigateUp
    self.taskId = taskId
    self._viewModel = StateObject(wrappedValue: viewModel)
    self.allowEditingSystemPrompt = allowEditingSystemPrompt
    self.curSystemPrompt = curSystemPrompt
    self.onSystemPromptChanged = onSystemPromptChanged
    self.emptyStateView = emptyStateView
    self.sendMessageTrigger = sendMessageTrigger
    self.showImagePicker = showImagePicker
    self.showAudioPicker = showAudioPicker
    self.onFirstToken = onFirstToken
    self.onGenerateResponseDone = onGenerateResponseDone
    self.onSkillClicked = onSkillClicked
    self.onMcpClicked = onMcpClicked
    self.onResetSessionClickedOverride = onResetSessionClickedOverride
    self.composableBelowMessageList = composableBelowMessageList
    self.skillCount = skillCount
    self.mcpCount = mcpCount
  }

  var body: some View {
    ChatViewWrapper(
      viewModel: viewModel,
      modelManagerViewModel: modelManagerViewModel,
      taskId: taskId,
      navigateUp: navigateUp,
      onSkillClicked: onSkillClicked,
      onMcpClicked: onMcpClicked,
      onFirstToken: onFirstToken,
      onGenerateResponseDone: onGenerateResponseDone,
      onResetSessionClickedOverride: onResetSessionClickedOverride,
      composableBelowMessageList: composableBelowMessageList,
      emptyStateView: emptyStateView,
      allowEditingSystemPrompt: allowEditingSystemPrompt,
      curSystemPrompt: curSystemPrompt,
      onSystemPromptChanged: onSystemPromptChanged,
      sendMessageTrigger: sendMessageTrigger,
      showImagePicker: showImagePicker,
      showAudioPicker: showAudioPicker,
      skillCount: skillCount,
      mcpCount: mcpCount)
  }
}

// MARK: - LlmAskImageScreen

struct LlmAskImageScreen: View {
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  let navigateUp: () -> Void
  var allowEditingSystemPrompt: Bool = false
  var curSystemPrompt: String = ""
  var onSystemPromptChanged: (String) -> Void = { _ in }

  @StateObject private var viewModel: LlmAskImageViewModel

  init(
    modelManagerViewModel: ModelManagerViewModel,
    navigateUp: @escaping () -> Void,
    viewModel: LlmAskImageViewModel,
    allowEditingSystemPrompt: Bool = false,
    curSystemPrompt: String = "",
    onSystemPromptChanged: @escaping (String) -> Void = { _ in }
  ) {
    self.modelManagerViewModel = modelManagerViewModel
    self.navigateUp = navigateUp
    self._viewModel = StateObject(wrappedValue: viewModel)
    self.allowEditingSystemPrompt = allowEditingSystemPrompt
    self.curSystemPrompt = curSystemPrompt
    self.onSystemPromptChanged = onSystemPromptChanged
  }

  var body: some View {
    ChatViewWrapper(
      viewModel: viewModel,
      modelManagerViewModel: modelManagerViewModel,
      taskId: BuiltInTaskId.LLM_ASK_IMAGE,
      navigateUp: navigateUp,
      emptyStateView: { _ in
        AnyView(
          VStack(spacing: 12) {
            Spacer()
            Text(Str.askimageEmptystateTitle)
              .font(AppTypography.titleMedium)
              .multilineTextAlignment(.center)
            Text(Str.askimageEmptystateContent)
              .font(AppTypography.bodyMedium)
              .multilineTextAlignment(.center)
              .foregroundStyle(.secondary)
            Spacer()
          }
          .padding(.horizontal, 48)
          .padding(.bottom, 48)
        )
      },
      allowEditingSystemPrompt: allowEditingSystemPrompt,
      curSystemPrompt: curSystemPrompt,
      onSystemPromptChanged: onSystemPromptChanged,
      showImagePicker: true,
      showAudioPicker: false)
  }
}

// MARK: - LlmAskAudioScreen

struct LlmAskAudioScreen: View {
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  let navigateUp: () -> Void
  var allowEditingSystemPrompt: Bool = false
  var curSystemPrompt: String = ""
  var onSystemPromptChanged: (String) -> Void = { _ in }

  @StateObject private var viewModel: LlmAskAudioViewModel

  init(
    modelManagerViewModel: ModelManagerViewModel,
    navigateUp: @escaping () -> Void,
    viewModel: LlmAskAudioViewModel,
    allowEditingSystemPrompt: Bool = false,
    curSystemPrompt: String = "",
    onSystemPromptChanged: @escaping (String) -> Void = { _ in }
  ) {
    self.modelManagerViewModel = modelManagerViewModel
    self.navigateUp = navigateUp
    self._viewModel = StateObject(wrappedValue: viewModel)
    self.allowEditingSystemPrompt = allowEditingSystemPrompt
    self.curSystemPrompt = curSystemPrompt
    self.onSystemPromptChanged = onSystemPromptChanged
  }

  var body: some View {
    ChatViewWrapper(
      viewModel: viewModel,
      modelManagerViewModel: modelManagerViewModel,
      taskId: BuiltInTaskId.LLM_ASK_AUDIO,
      navigateUp: navigateUp,
      emptyStateView: { _ in
        AnyView(
          VStack(spacing: 12) {
            Spacer()
            Text(Str.askaudioEmptystateTitle)
              .font(AppTypography.titleMedium)
              .multilineTextAlignment(.center)
            Text(Str.askaudioEmptystateContent)
              .font(AppTypography.bodyMedium)
              .multilineTextAlignment(.center)
              .foregroundStyle(.secondary)
            Spacer()
          }
          .padding(.horizontal, 48)
          .padding(.bottom, 48)
        )
      },
      allowEditingSystemPrompt: allowEditingSystemPrompt,
      curSystemPrompt: curSystemPrompt,
      onSystemPromptChanged: onSystemPromptChanged,
      showImagePicker: false,
      showAudioPicker: true)
  }
}

// MARK: - ChatViewWrapper

/// Shared helper that wires a `LlmChatViewModelBase` into `ChatView`.
/// Mirrors `@Composable fun ChatViewWrapper(...)`.
struct ChatViewWrapper: View {
  @ObservedObject var viewModel: LlmChatViewModelBase
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  let taskId: String
  let navigateUp: () -> Void

  var onSkillClicked: () -> Void = {}
  var onMcpClicked: () -> Void = {}
  var onFirstToken: (Model) -> Void = { _ in }
  var onGenerateResponseDone: (Model) -> Void = { _ in }
  var onResetSessionClickedOverride: ((Task, Model, [ChatMessage], Bool, () -> Void) -> Void)? = nil
  var composableBelowMessageList: ((Model) -> AnyView)? = nil
  var emptyStateView: ((Model) -> AnyView)? = nil
  var allowEditingSystemPrompt: Bool = false
  var curSystemPrompt: String = ""
  var onSystemPromptChanged: (String) -> Void = { _ in }
  var sendMessageTrigger: SendMessageTrigger? = nil
  var showImagePicker: Bool = false
  var showAudioPicker: Bool = false
  var skillCount: Int = 0
  var mcpCount: Int = 0

  @Environment(\.customColors) private var customColors

  private var task: Task? { modelManagerViewModel.getTaskById(taskId) }

  var body: some View {
    if let task {
      ChatView(
        task: task,
        viewModel: viewModel,
        modelManagerViewModel: modelManagerViewModel,
        onSendMessage: { model, messages in
          // Add each incoming message to the chat.
          for message in messages { viewModel.addMessage(model: model, message: message) }

          // Extract text, images, and audio from the batch.
          var text = ""
          var images: [UIImage] = []
          var audioMessages: [ChatMessageAudioClip] = []
          for message in messages {
            if let txt = message as? ChatMessageText { text = txt.content }
            else if let img = message as? ChatMessageImage { images.append(contentsOf: img.images) }
            else if let aud = message as? ChatMessageAudioClip { audioMessages.append(aud) }
          }

          guard !text.isEmpty || !audioMessages.isEmpty else { return }
          if !text.isEmpty { modelManagerViewModel.addTextInputHistory(text) }

          let enableThinking = task.allowCapability(.llmThinking,
                                                    model: modelManagerViewModel.uiState.selectedModel)
          viewModel.generateResponse(
            model: model,
            input: text,
            images: images,
            audioMessages: audioMessages,
            onFirstToken: onFirstToken,
            onDone: { onGenerateResponseDone(model) },
            onError: { errorMessage in
              viewModel.handleError(
                task: task,
                model: model,
                modelManagerViewModel: modelManagerViewModel,
                errorMessage: errorMessage)
            },
            allowThinking: enableThinking)
        },
        onRunAgainClicked: { model, message in
          if let txtMsg = message as? ChatMessageText {
            let enableThinking = task.allowCapability(.llmThinking, model: model)
            viewModel.runAgain(
              model: model,
              message: txtMsg,
              onError: { errorMessage in
                viewModel.handleError(
                  task: task,
                  model: model,
                  modelManagerViewModel: modelManagerViewModel,
                  errorMessage: errorMessage)
              },
              allowThinking: enableThinking)
          }
        },
        onBenchmarkClicked: { _, _, _, _ in },
        navigateUp: navigateUp,
        skillCount: skillCount,
        mcpCount: mcpCount,
        onResetSessionClicked: { model, chatMessages, clearHistory, onDone in
          // Convert chat history to LlmMessage for session seeding.
          let llmMessages = chatMessages.compactMap { convertToLlmMessage($0) }
          if let override = onResetSessionClickedOverride {
            override(task, model, chatMessages, clearHistory, onDone)
          } else {
            viewModel.resetSession(
              task: task,
              model: model,
              systemInstruction: curSystemPrompt.isEmpty ? nil : curSystemPrompt,
              supportImage: showImagePicker,
              supportAudio: showAudioPicker,
              onDone: onDone,
              initialMessages: llmMessages,
              clearHistory: clearHistory)
          }
        },
        onStopButtonClicked: { model in viewModel.stopResponse(model: model) },
        onSkillClicked: onSkillClicked,
        onMcpClicked: onMcpClicked,
        showStopButtonInInputWhenInProgress: true,
        composableBelowMessageList: composableBelowMessageList,
        showImagePicker: showImagePicker,
        showAudioPicker: showAudioPicker,
        emptyStateView: emptyStateView,
        allowEditingSystemPrompt: allowEditingSystemPrompt,
        curSystemPrompt: curSystemPrompt,
        onSystemPromptChanged: onSystemPromptChanged,
        sendMessageTrigger: sendMessageTrigger)
    }
  }
}

// MARK: - Helpers

/// Converts a ChatMessage to an LlmMessage for session history seeding.
/// Mirrors `fun convertToLitertMessage(chatMessage: ChatMessage): Message?`.
///
/// NOTE: Image and audio messages are intentionally skipped (same rationale
/// as Android: the encoders can stall session reset). Support can be added
/// once a chunked-encoding path is available.
private func convertToLlmMessage(_ chatMessage: ChatMessage) -> LlmMessage? {
  guard let txt = chatMessage as? ChatMessageText else { return nil }
  switch txt.side {
  case .user:   return LlmMessage(role: .user, text: txt.content)
  case .agent:  return LlmMessage(role: .model, text: txt.content)
  case .system: return nil // TODO: support system once system-prompt merging is resolved.
  }
}
