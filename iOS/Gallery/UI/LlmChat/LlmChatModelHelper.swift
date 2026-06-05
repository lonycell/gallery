/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/llmchat/LlmChatModelHelper.kt
//
// On Android this was a concrete LiteRT-LM Engine+Conversation wrapper that
// read temperature/topK/topP/maxTokens from the model's configs and managed
// per-model instances. On iOS the LiteRT-LM native library is unavailable, so
// this class delegates every call to the injected `LlmModelHelper` (typically
// `StubLlmModelHelper` in the current build). The config-extraction logic and
// the initialize/resetConversation/cleanUp/runInference/stopResponse flow are
// reproduced faithfully so a real MediaPipe LlmInference implementation can
// be swapped in by replacing the delegate with a concrete helper.
//
// NOTE: Real LiteRT-LM inference (Engine / Conversation / SamplerConfig) has
// no Swift package equivalent. Swap `delegate` for a MediaPipe-backed
// implementation that reads the same config keys.

import UIKit

/// Concrete `LlmModelHelper` for the LLM-Chat / Ask-Image / Ask-Audio tasks.
/// Wraps an injected helper so the config-reading and lifecycle logic lives here
/// rather than being scattered across task-module factories.
final class LlmChatModelHelper: LlmModelHelper {

  private let delegate: LlmModelHelper

  init(delegate: LlmModelHelper = StubLlmModelHelper()) {
    self.delegate = delegate
  }

  // MARK: - LlmModelHelper

  func initialize(
    model: Model,
    taskId: String,
    supportImage: Bool,
    supportAudio: Bool,
    systemInstruction: Contents?,
    tools: [ToolProvider],
    enableConversationConstrainedDecoding: Bool,
    initialMessages: [LlmMessage],
    onDone: @escaping (String) -> Void
  ) {
    // NOTE: On Android, EngineConfig was constructed here from config values:
    //   maxTokens  = model.getIntConfigValue(ConfigKeys.MAX_TOKENS, DEFAULT_MAX_TOKEN)
    //   topK       = model.getIntConfigValue(ConfigKeys.TOPK, DEFAULT_TOPK)
    //   topP       = model.getFloatConfigValue(ConfigKeys.TOPP, DEFAULT_TOPP)
    //   temperature = model.getFloatConfigValue(ConfigKeys.TEMPERATURE, DEFAULT_TEMPERATURE)
    //   accelerator = model.getStringConfigValue(ConfigKeys.ACCELERATOR, Accelerator.gpu.label)
    // These are available via the same Model helpers on iOS — pass them to your
    // real LiteRT-LM / MediaPipe engine when available.
    delegate.initialize(
      model: model, taskId: taskId,
      supportImage: supportImage, supportAudio: supportAudio,
      systemInstruction: systemInstruction, tools: tools,
      enableConversationConstrainedDecoding: enableConversationConstrainedDecoding,
      initialMessages: initialMessages, onDone: onDone)
  }

  func resetConversation(
    model: Model,
    supportImage: Bool,
    supportAudio: Bool,
    systemInstruction: Contents?,
    tools: [ToolProvider],
    enableConversationConstrainedDecoding: Bool,
    initialMessages: [LlmMessage]
  ) {
    // NOTE: On Android, the existing Engine was reused and only a new
    // Conversation was created (with fresh SamplerConfig from model configs).
    // Re-read topK/topP/temperature here when wiring a real engine.
    delegate.resetConversation(
      model: model, supportImage: supportImage, supportAudio: supportAudio,
      systemInstruction: systemInstruction, tools: tools,
      enableConversationConstrainedDecoding: enableConversationConstrainedDecoding,
      initialMessages: initialMessages)
  }

  func cleanUp(model: Model, onDone: @escaping () -> Void) {
    delegate.cleanUp(model: model, onDone: onDone)
  }

  func runInference(
    model: Model,
    input: String,
    resultListener: @escaping ResultListener,
    cleanUpListener: @escaping CleanUpListener,
    onError: @escaping (String) -> Void,
    images: [UIImage],
    audioClips: [Data],
    extraContext: [String: String]?
  ) {
    delegate.runInference(
      model: model, input: input,
      resultListener: resultListener, cleanUpListener: cleanUpListener,
      onError: onError, images: images, audioClips: audioClips,
      extraContext: extraContext)
  }

  func stopResponse(model: Model) {
    delegate.stopResponse(model: model)
  }
}
