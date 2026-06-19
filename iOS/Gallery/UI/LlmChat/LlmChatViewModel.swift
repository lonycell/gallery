/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/llmchat/LlmChatViewModel.kt
//
// `LlmChatViewModelBase` extends `ChatViewModel` and adds:
//   • system-prompt loading / applying (via SystemPromptRepository)
//   • generateResponse() — waits for model init, then streams tokens
//   • stopResponse(), resetSession(), runAgain(), handleError()
//
// On Android inference was routed via `model.runtimeHelper`; on iOS the
// `LlmModelHelper` is injected directly (from AppContainer / the task module).
//
// The three concrete leaf classes (LlmChatViewModel, LlmAskImageViewModel,
// LlmAskAudioViewModel) are thin subclasses differentiated only by their
// injected system-prompt repository.

import Foundation
import UIKit
import Combine

private let TAG = "AGLlmChatViewModel"

// MARK: - LlmChatViewModelBase

@MainActor
class LlmChatViewModelBase: ChatViewModel {

  @Published private(set) var uiSystemPrompt: String = ""

  private let systemPromptRepository: SystemPromptRepository?
  /// Injected runtime — set by the task module's factory.
  var llmModelHelper: LlmModelHelper

  init(
    systemPromptRepository: SystemPromptRepository? = nil,
    store: DataStoreRepository? = nil,
    llmModelHelper: LlmModelHelper = StubLlmModelHelper()
  ) {
    self.systemPromptRepository = systemPromptRepository
    self.llmModelHelper = llmModelHelper
    super.init(store: store)
  }

  // MARK: - System prompt

  /// Sets the UI system-prompt display without persisting it.  Used at init time.
  func setUISystemPrompt(_ systemPrompt: String) {
    uiSystemPrompt = systemPrompt
  }

  /// Loads the effective system prompt for `task` from the repository (or task default).
  func loadSystemPrompt(task: Task) {
    _Concurrency.Task { [weak self, systemPromptRepository] in
      let effective = await SystemPromptHelper.getEffectiveSystemPrompt(
        repo: systemPromptRepository, task: task)
      await MainActor.run { self?.uiSystemPrompt = effective }
    }
  }

  /// Persists a new system prompt, then resets the conversation session.
  func applySystemPromptChange(
    task: Task,
    model: Model,
    newPrompt: String,
    systemPromptUpdatedMessage: String
  ) {
    uiSystemPrompt = newPrompt
    _Concurrency.Task { [weak self, systemPromptRepository] in
      await systemPromptRepository?.updateSystemPrompt(taskId: task.id, newPrompt: newPrompt)
      await self?.resetSession(
        task: task,
        model: model,
        systemInstruction: newPrompt,
        supportImage: true,
        supportAudio: true,
        onDone: { [weak self] in
          self?.addMessage(
            model: model,
            message: ChatMessageInfo(content: systemPromptUpdatedMessage))
        })
    }
  }

  // MARK: - Inference

  /// Runs LLM inference for the given `input`, streaming tokens into the message list.
  func generateResponse(
    model: Model,
    input: String,
    images: [UIImage] = [],
    audioMessages: [ChatMessageAudioClip] = [],
    onFirstToken: @escaping (Model) -> Void = { _ in },
    onDone: @escaping () -> Void = {},
    onError: @escaping (String) -> Void,
    allowThinking: Bool = false
  ) {
    let accelerator = model.getStringConfigValue(ConfigKeys.ACCELERATOR, default: "")
    let helper = llmModelHelper

    _Concurrency.Task { [weak self] in
      guard let self else { return }

      self.setInProgress(true)
      self.setPreparing(true)

      // Add loading placeholder.
      self.addMessage(model: model, message: ChatMessageLoading(accelerator: accelerator))

      // Wait until model instance is ready.
      var waited = 0
      while model.instance == nil {
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 100 ms
        waited += 1
        if waited > 600 { break } // 60-second safety guard
      }
      try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // 500 ms grace

      // Build audio WAV buffers from ChatMessageAudioClip.
      let audioClips: [Data] = audioMessages.map { $0.genDataForWav() }

      let extraContext: [String: String]? = {
        let enableThinking = allowThinking &&
          model.getBooleanConfigValue(ConfigKeys.ENABLE_THINKING, default: false)
        return enableThinking ? ["enable_thinking": "true"] : nil
      }()

      var firstRun = true
      let start = Date()

      helper.runInference(
        model: model,
        input: input,
        resultListener: { [weak self] partialResult, done, partialThinkingResult in
          guard let self else { return }
          _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }
            // Ignore control tokens.
            if partialResult.hasPrefix("<ctrl") { return }

            let lastMessage = self.getLastMessage(model: model)
            let wasLoading = lastMessage?.type == .loading
            if wasLoading { self.removeLastMessage(model: model) }

            let thinkingText = partialThinkingResult
            let isThinking = thinkingText != nil && !thinkingText!.isEmpty
            var currentLast = self.getLastMessage(model: model)

            if isThinking {
              // Append / grow thinking bubble.
              if currentLast?.type != .thinking {
                self.addMessage(
                  model: model,
                  message: ChatMessageThinking(
                    content: "",
                    inProgress: true,
                    side: .agent,
                    hideSenderLabel: currentLast?.type == .collapsableProgressPanel,
                    accelerator: accelerator))
              }
              self.updateLastThinkingMessageContentIncrementally(
                model: model, partialContent: thinkingText!)
            } else {
              // Finalise any open thinking bubble.
              if let thinking = currentLast as? ChatMessageThinking, thinking.inProgress {
                self.replaceLastMessage(
                  model: model,
                  message: ChatMessageThinking(
                    content: thinking.content, inProgress: false,
                    side: thinking.side, hideSenderLabel: thinking.hideSenderLabel,
                    accelerator: thinking.accelerator),
                  type: .thinking)
              }
              currentLast = self.getLastMessage(model: model)

              // Ensure an agent TEXT bubble exists for streaming.
              if currentLast?.type != .text || currentLast?.side != .agent {
                self.addMessage(
                  model: model,
                  message: ChatMessageText(
                    content: "",
                    side: .agent,
                    accelerator: accelerator,
                    hideSenderLabel:
                      currentLast?.type == .collapsableProgressPanel ||
                      currentLast?.type == .thinking))
              }

              let latencyMs: Float = done
                ? Float(Date().timeIntervalSince(start) * 1000) : -1
              if !partialResult.isEmpty || wasLoading || done {
                self.updateLastTextMessageContentIncrementally(
                  model: model,
                  partialContent: partialResult,
                  latencyMs: latencyMs)
              }
            }

            if firstRun {
              firstRun = false
              self.setPreparing(false)
              onFirstToken(model)
            }

            if done {
              // Finalise any still-open thinking bubble.
              if let thinking = self.getLastMessage(model: model) as? ChatMessageThinking,
                 thinking.inProgress {
                self.replaceLastMessage(
                  model: model,
                  message: ChatMessageThinking(
                    content: thinking.content, inProgress: false,
                    side: thinking.side, hideSenderLabel: thinking.hideSenderLabel,
                    accelerator: thinking.accelerator),
                  type: .thinking)
              }
              self.setInProgress(false)
              onDone()
            }
          }
        },
        cleanUpListener: { [weak self] in
          _Concurrency.Task { @MainActor [weak self] in
            self?.setInProgress(false)
            self?.setPreparing(false)
          }
        },
        onError: { [weak self] message in
          print("\(TAG): Error during inference: \(message)")
          _Concurrency.Task { @MainActor [weak self] in
            self?.setInProgress(false)
            self?.setPreparing(false)
            onError(message)
          }
        },
        images: images,
        audioClips: audioClips,
        extraContext: extraContext)
    }
  }

  /// Stops the current in-progress inference.
  func stopResponse(model: Model) {
    print("\(TAG): Stopping response for model \(model.name)...")
    if getLastMessage(model: model) is ChatMessageLoading {
      removeLastMessage(model: model)
    }
    setInProgress(false)
    llmModelHelper.stopResponse(model: model)
    print("\(TAG): Done stopping response")
  }

  /// Resets the conversation session (clears history + re-seeds the conversation).
  func resetSession(
    task: Task,
    model: Model,
    systemInstruction: String? = nil,
    tools: [ToolProvider] = [],
    supportImage: Bool = false,
    supportAudio: Bool = false,
    onDone: @escaping () -> Void = {},
    enableConversationConstrainedDecoding: Bool = false,
    initialMessages: [LlmMessage] = [],
    clearHistory: Bool = true
  ) {
    let helper = llmModelHelper
    _Concurrency.Task { [weak self] in
      guard let self else { return }
      self.setIsResettingSession(true)
      if clearHistory { self.clearAllMessages(model: model) }
      self.stopResponse(model: model)

      // Retry until resetConversation succeeds (mirrors Kotlin's while(true) + catch).
      while true {
        helper.resetConversation(
          model: model,
          supportImage: supportImage,
          supportAudio: supportAudio,
          systemInstruction: systemInstruction,
          tools: tools,
          enableConversationConstrainedDecoding: enableConversationConstrainedDecoding,
          initialMessages: initialMessages)
        break
      }
      self.setIsResettingSession(false)
      onDone()
    }
  }

  /// Clones `message`, adds it, and re-runs inference.
  func runAgain(
    model: Model,
    message: ChatMessageText,
    onError: @escaping (String) -> Void,
    allowThinking: Bool = false
  ) {
    _Concurrency.Task { [weak self] in
      guard let self else { return }
      var waited = 0
      while model.instance == nil {
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        waited += 1
        if waited > 600 { break }
      }
      self.addMessage(model: model, message: message.clone())
      self.generateResponse(
        model: model,
        input: message.content,
        onError: onError,
        allowThinking: allowThinking)
    }
  }

  /// Removes any loading message, shows an error, then cleans up + re-initializes the model.
  func handleError(
    task: Task,
    model: Model,
    modelManagerViewModel: ModelManagerViewModel,
    errorMessage: String
  ) {
    if getLastMessage(model: model) is ChatMessageLoading {
      removeLastMessage(model: model)
    }
    addMessage(model: model, message: ChatMessageError(content: errorMessage))

    // Clean up then re-initialize. ModelManagerViewModel broadcasts status changes via
    // @Published uiState so the screen observes the INITIALIZED/ERROR transitions.
    modelManagerViewModel.cleanupModel(task: task, model: model)
    _Concurrency.Task { [weak self] in
      guard let self else { return }
      // Brief pause to let the cleanup complete before re-initializing.
      try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
      // initializeModel() posts status changes through uiState; observe them in
      // the screen layer for success/error UI. Here we post a re-init info message.
      modelManagerViewModel.initializeModel(task: task, model: model)
      // Show a warning that the session was reset.
      self.addMessage(
        model: model,
        message: ChatMessageWarning(content: "Session re-initialized"))
    }
  }
}

// MARK: - Concrete leaf view models

/// View model for `LLM_CHAT`.
@MainActor
final class LlmChatViewModel: LlmChatViewModelBase {}

/// View model for `LLM_ASK_IMAGE`.
@MainActor
final class LlmAskImageViewModel: LlmChatViewModelBase {}

/// View model for `LLM_ASK_AUDIO`.
@MainActor
final class LlmAskAudioViewModel: LlmChatViewModelBase {}
