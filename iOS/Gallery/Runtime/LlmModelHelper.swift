/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of runtime/LlmModelHelper.kt + the litertlm runtime surface.
//
// Android ran inference on-device through `com.google.ai.edge.litertlm` (LiteRT-LM)
// and `mlkit.genai` (AICore). Those native runtimes have no drop-in Swift package,
// so iOS defines the same protocol surface and ships a `StubLlmModelHelper` that
// streams a placeholder response. To run real on-device inference, drop in the
// MediaPipe `LlmInference` (MediaPipeTasksGenAI) pod and implement this protocol
// against it — every call site already targets `LlmModelHelper`.

import Foundation
import UIKit

/// (partialResult, done, partialThinkingResult). Mirrors Kotlin `ResultListener`.
typealias ResultListener = (_ partialResult: String, _ done: Bool, _ partialThinkingResult: String?) -> Void
typealias CleanUpListener = () -> Void

/// A unit of model input/context. Mirrors litertlm `Contents`/`Message` loosely.
struct LlmMessage {
  enum Role { case system, user, model }
  let role: Role
  let text: String
}
typealias Contents = String          // system instruction text (litertlm.Contents)
typealias ToolProvider = AnyObject   // litertlm.ToolProvider (function-calling tools)

/// Base interface for all LLM runtimes. Mirrors `interface LlmModelHelper`.
protocol LlmModelHelper {
  func initialize(
    model: Model,
    taskId: String,
    supportImage: Bool,
    supportAudio: Bool,
    systemInstruction: Contents?,
    tools: [ToolProvider],
    enableConversationConstrainedDecoding: Bool,
    initialMessages: [LlmMessage],
    onDone: @escaping (String) -> Void)

  func resetConversation(
    model: Model,
    supportImage: Bool,
    supportAudio: Bool,
    systemInstruction: Contents?,
    tools: [ToolProvider],
    enableConversationConstrainedDecoding: Bool,
    initialMessages: [LlmMessage])

  func cleanUp(model: Model, onDone: @escaping () -> Void)

  func runInference(
    model: Model,
    input: String,
    resultListener: @escaping ResultListener,
    cleanUpListener: @escaping CleanUpListener,
    onError: @escaping (String) -> Void,
    images: [UIImage],
    audioClips: [Data],
    extraContext: [String: String]?)

  func stopResponse(model: Model)
}

// Default-argument conveniences mirroring Kotlin's parameter defaults.
extension LlmModelHelper {
  func initialize(model: Model, taskId: String, supportImage: Bool = false,
                  supportAudio: Bool = false, systemInstruction: Contents? = nil,
                  tools: [ToolProvider] = [], enableConversationConstrainedDecoding: Bool = false,
                  initialMessages: [LlmMessage] = [], onDone: @escaping (String) -> Void) {
    initialize(model: model, taskId: taskId, supportImage: supportImage, supportAudio: supportAudio,
               systemInstruction: systemInstruction, tools: tools,
               enableConversationConstrainedDecoding: enableConversationConstrainedDecoding,
               initialMessages: initialMessages, onDone: onDone)
  }

  func resetConversation(model: Model, supportImage: Bool = false, supportAudio: Bool = false,
                         systemInstruction: Contents? = nil, tools: [ToolProvider] = [],
                         enableConversationConstrainedDecoding: Bool = false,
                         initialMessages: [LlmMessage] = []) {
    resetConversation(model: model, supportImage: supportImage, supportAudio: supportAudio,
                      systemInstruction: systemInstruction, tools: tools,
                      enableConversationConstrainedDecoding: enableConversationConstrainedDecoding,
                      initialMessages: initialMessages)
  }

  func runInference(model: Model, input: String, resultListener: @escaping ResultListener,
                    cleanUpListener: @escaping CleanUpListener, onError: @escaping (String) -> Void = { _ in },
                    images: [UIImage] = [], audioClips: [Data] = [],
                    extraContext: [String: String]? = nil) {
    runInference(model: model, input: input, resultListener: resultListener,
                 cleanUpListener: cleanUpListener, onError: onError, images: images,
                 audioClips: audioClips, extraContext: extraContext)
  }
}

/// The opaque per-model runtime handle stored in `Model.instance`. On Android this
/// was a `LlmModelInstance` wrapping the litertlm Engine + Session.
final class LlmModelInstance {
  var engine: Any?
  var session: Any?
  init(engine: Any? = nil, session: Any? = nil) { self.engine = engine; self.session = session }
}

/// Placeholder runtime. Streams a canned response so the full UI flow works
/// without the native LiteRT-LM library. Swap for a MediaPipe-backed engine.
final class StubLlmModelHelper: LlmModelHelper {
  private var cancelled = Set<ObjectIdentifier>()

  func initialize(model: Model, taskId: String, supportImage: Bool, supportAudio: Bool,
                  systemInstruction: Contents?, tools: [ToolProvider],
                  enableConversationConstrainedDecoding: Bool, initialMessages: [LlmMessage],
                  onDone: @escaping (String) -> Void) {
    model.instance = LlmModelInstance()
    onDone("")
  }

  func resetConversation(model: Model, supportImage: Bool, supportAudio: Bool,
                         systemInstruction: Contents?, tools: [ToolProvider],
                         enableConversationConstrainedDecoding: Bool, initialMessages: [LlmMessage]) {}

  func cleanUp(model: Model, onDone: @escaping () -> Void) {
    model.instance = nil
    onDone()
  }

  func runInference(model: Model, input: String, resultListener: @escaping ResultListener,
                    cleanUpListener: @escaping CleanUpListener, onError: @escaping (String) -> Void,
                    images: [UIImage], audioClips: [Data], extraContext: [String: String]?) {
    cancelled.remove(ObjectIdentifier(model))
    let response = "[stub:\(model.name)] The native LiteRT-LM runtime is not bundled in this " +
      "iOS port. This is a placeholder streamed response to exercise the chat UI."
    let words = response.split(separator: " ").map(String.init)
    DispatchQueue.global().async { [weak self] in
      for (i, w) in words.enumerated() {
        if let self, self.cancelled.contains(ObjectIdentifier(model)) { break }
        usleep(40_000)
        let partial = w + (i == words.count - 1 ? "" : " ")
        DispatchQueue.main.async { resultListener(partial, false, nil) }
      }
      DispatchQueue.main.async {
        resultListener("", true, nil)
        cleanUpListener()
      }
    }
  }

  func stopResponse(model: Model) { cancelled.insert(ObjectIdentifier(model)) }
}
