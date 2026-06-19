/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/ChatViewModel.kt — the abstract chat state base class.
// Feature view models (LlmChatViewModel, AgentChatViewModel, ...) subclass this.

import Foundation
import Combine

/// Mirrors `fun processLlmResponse` in common/Utils.kt.
func processLlmResponse(response: String) -> String {
  response.replacingOccurrences(of: "\\n", with: "\n")
}

/// Mirrors `data class ChatUiState`.
struct ChatUiState {
  var inProgress: Bool = false
  var isResettingSession: Bool = false
  var preparing: Bool = false
  var messagesByModel: [String: [ChatMessage]] = [:]
  var streamingMessagesByModel: [String: ChatMessage] = [:]
}

/// Base view model managing chat UI state. Mirrors `abstract class ChatViewModel`.
@MainActor
class ChatViewModel: ObservableObject {
  @Published var uiState = ChatUiState()
  @Published var historySessions: [ChatSessionProto] = []

  var currentSessionId: String = UUID().uuidString
  let store: DataStoreRepository?

  init(store: DataStoreRepository? = nil) {
    self.store = store
    reloadHistorySessions()
  }

  func reloadHistorySessions() {
    historySessions = (store?.readUserData().chatSessions ?? [])
      .sorted { $0.timestampMs > $1.timestampMs }
  }

  // MARK: - Message list mutations

  func addMessage(model: Model, message: ChatMessage) {
    var messages = uiState.messagesByModel[model.name] ?? []
    if let last = messages.last, last.type == .promptTemplates { messages.removeLast() }
    messages.append(message)
    uiState.messagesByModel[model.name] = messages
  }

  func insertMessageAfter(model: Model, anchorMessage: ChatMessage, messageToAdd: ChatMessage) {
    var messages = uiState.messagesByModel[model.name] ?? []
    if let idx = messages.firstIndex(where: { $0 === anchorMessage }) {
      messages.insert(messageToAdd, at: idx + 1)
    }
    uiState.messagesByModel[model.name] = messages
  }

  func removeMessageAt(model: Model, index: Int) {
    guard var messages = uiState.messagesByModel[model.name] else { return }
    if index >= 0 && index < messages.count { messages.remove(at: index) }
    uiState.messagesByModel[model.name] = messages
  }

  func removeLastMessage(model: Model) {
    var messages = uiState.messagesByModel[model.name] ?? []
    if !messages.isEmpty { messages.removeLast() }
    uiState.messagesByModel[model.name] = messages
  }

  func clearAllMessages(model: Model) { uiState.messagesByModel[model.name] = [] }

  func getLastMessage(model: Model) -> ChatMessage? { uiState.messagesByModel[model.name]?.last }

  func getLastMessageWithType(model: Model, type: ChatMessageType) -> ChatMessage? {
    uiState.messagesByModel[model.name]?.last { $0.type == type }
  }

  func getLastMessageWithTypeAndSide(model: Model, type: ChatMessageType, side: ChatSide) -> ChatMessage? {
    uiState.messagesByModel[model.name]?.last { $0.type == type && $0.side == side }
  }

  func updateLastThinkingMessageContentIncrementally(model: Model, partialContent: String) {
    var messages = uiState.messagesByModel[model.name] ?? []
    if let last = messages.last as? ChatMessageThinking {
      let newContent = processLlmResponse(response: last.content + partialContent)
      messages[messages.count - 1] = ChatMessageThinking(
        content: newContent, inProgress: last.inProgress, side: last.side,
        hideSenderLabel: last.hideSenderLabel, accelerator: last.accelerator)
    }
    uiState.messagesByModel[model.name] = messages
  }

  func updateLastTextMessageContentIncrementally(model: Model, partialContent: String, latencyMs: Float) {
    var messages = uiState.messagesByModel[model.name] ?? []
    if let last = messages.last as? ChatMessageText {
      let newContent = processLlmResponse(response: last.content + partialContent)
      messages[messages.count - 1] = ChatMessageText(
        content: newContent, side: last.side, latencyMs: latencyMs,
        accelerator: last.accelerator, hideSenderLabel: last.hideSenderLabel)
    }
    uiState.messagesByModel[model.name] = messages
  }

  func updateLastTextMessageLlmBenchmarkResult(model: Model, llmBenchmarkResult: ChatMessageBenchmarkLlmResult) {
    var messages = uiState.messagesByModel[model.name] ?? []
    if let last = messages.last as? ChatMessageText {
      last.llmBenchmarkResult = llmBenchmarkResult
      messages[messages.count - 1] = last
    }
    uiState.messagesByModel[model.name] = messages
  }

  func replaceLastMessage(model: Model, message: ChatMessage, type: ChatMessageType) {
    var messages = uiState.messagesByModel[model.name] ?? []
    if let idx = messages.lastIndex(where: { $0.type == type }) { messages[idx] = message }
    uiState.messagesByModel[model.name] = messages
  }

  func replaceMessage(model: Model, index: Int, message: ChatMessage) {
    var messages = uiState.messagesByModel[model.name] ?? []
    if index >= 0 && index < messages.count { messages[index] = message }
    uiState.messagesByModel[model.name] = messages
  }

  func updateStreamingMessage(model: Model, message: ChatMessage) {
    uiState.streamingMessagesByModel[model.name] = message
  }

  func updateCollapsableProgressPanelMessage(
    model: Model, title: String, inProgress: Bool, doneIcon: String,
    addItemTitle: String, addItemDescription: String, customData: Any? = nil) {
    let accelerator = model.getStringConfigValue(ConfigKeys.ACCELERATOR, default: "")
    var messages = uiState.messagesByModel[model.name] ?? []

    func makeNew() -> ChatMessageCollapsableProgressPanel {
      ChatMessageCollapsableProgressPanel(
        title: title, inProgress: inProgress, accelerator: accelerator, doneIcon: doneIcon,
        items: addItemTitle.isEmpty ? [] : [ProgressPanelItem(title: addItemTitle, description: addItemDescription)],
        customData: customData)
    }

    if let last = messages.last, last is ChatMessageLoading {
      messages.removeLast(); messages.append(makeNew())
    } else {
      let lastPanel = getLastMessageWithType(model: model, type: .collapsableProgressPanel)
      let lastPanelIndex = lastPanel.flatMap { p in messages.firstIndex { $0 === p } } ?? -1
      let lastUserText = getLastMessageWithTypeAndSide(model: model, type: .text, side: .user)
      let lastUserTextIndex = lastUserText.flatMap { p in messages.firstIndex { $0 === p } } ?? -1

      if lastPanel != nil && lastUserText != nil && lastUserTextIndex > lastPanelIndex {
        messages.insert(makeNew(), at: lastUserTextIndex + 1)
      } else if let panel = lastPanel as? ChatMessageCollapsableProgressPanel {
        let newItems = panel.items + (addItemTitle.isEmpty ? [] : [ProgressPanelItem(title: addItemTitle, description: addItemDescription)])
        messages[lastPanelIndex] = ChatMessageCollapsableProgressPanel(
          title: title, inProgress: inProgress, accelerator: accelerator, doneIcon: doneIcon,
          items: newItems, logMessages: panel.logMessages, customData: panel.customData)
      } else {
        messages.append(makeNew())
      }
    }
    uiState.messagesByModel[model.name] = messages
  }

  func addLogMessageToLastCollapsableProgressPanel(model: Model, logMessage: LogMessage) {
    var messages = uiState.messagesByModel[model.name] ?? []
    if let idx = messages.lastIndex(where: { $0 is ChatMessageCollapsableProgressPanel }),
       let panel = messages[idx] as? ChatMessageCollapsableProgressPanel {
      messages[idx] = ChatMessageCollapsableProgressPanel(
        title: panel.title, inProgress: panel.inProgress, accelerator: panel.accelerator,
        doneIcon: panel.doneIcon, items: panel.items,
        logMessages: panel.logMessages + [logMessage], customData: panel.customData)
    }
    uiState.messagesByModel[model.name] = messages
  }

  func setInProgress(_ inProgress: Bool) { uiState.inProgress = inProgress }
  func setIsResettingSession(_ value: Bool) { uiState.isResettingSession = value }
  func setPreparing(_ preparing: Bool) { uiState.preparing = preparing }

  func addConfigChangedMessage(oldConfigValues: [String: Any], newConfigValues: [String: Any], model: Model) {
    addMessage(model: model, message: ChatMessageConfigValuesChange(
      model: model, oldValues: oldConfigValues, newValues: newConfigValues))
  }

  func getMessageIndex(model: Model, message: ChatMessage) -> Int {
    uiState.messagesByModel[model.name]?.firstIndex { $0 === message } ?? -1
  }

  // MARK: - Session persistence (UserData.chatSessions)

  func saveSession(sessionId: String, messages: [ChatMessage], originalModel: String, taskId: String) {
    let snapshot = messages
    _Concurrency.Task.detached { [store] in
      let firstText = snapshot.compactMap { $0 as? ChatMessageText }.first?.content
      let title: String = {
        guard let t = firstText else { return "New Chat Session" }
        let trimmed = String(t.prefix(30))
        return trimmed.count == 30 ? trimmed + "..." : trimmed
      }()
      let protos: [ChatMessageProto] = snapshot.compactMap { Self.toProto($0, sessionId: sessionId) }
      let session = ChatSessionProto(
        sessionId: sessionId, title: title, timestampMs: currentTimeMillis(),
        originalModel: originalModel, taskId: taskId, messages: protos)
      await store?.updateUserData { data in
        data.chatSessions.removeAll { $0.sessionId == sessionId }
        data.chatSessions.append(session)
      }
      await MainActor.run { [weak self] in self?.reloadHistorySessions() }
    }
  }

  func deleteSession(sessionId: String) {
    _Concurrency.Task.detached { [store] in
      await store?.updateUserData { data in data.chatSessions.removeAll { $0.sessionId == sessionId } }
      await MainActor.run { [weak self] in self?.reloadHistorySessions() }
    }
  }

  func clearAllSessions() {
    _Concurrency.Task.detached { [store] in
      await store?.updateUserData { data in data.chatSessions = [] }
      await MainActor.run { [weak self] in self?.reloadHistorySessions() }
    }
  }

  private nonisolated static func toProto(_ msg: ChatMessage, sessionId: String) -> ChatMessageProto? {
    var p = ChatMessageProto()
    switch msg {
    case let m as ChatMessageText:
      p.messageType = "TEXT"; p.content = m.content; p.side = mapChatSide(m.side)
      p.latencyMs = m.latencyMs; p.accelerator = m.accelerator
      p.hideSenderLabel = m.hideSenderLabel; p.isMarkdown = m.isMarkdown
    case let m as ChatMessageThinking:
      p.messageType = "THINKING"; p.content = m.content; p.side = mapChatSide(m.side)
      p.inProgress = m.inProgress; p.accelerator = m.accelerator; p.hideSenderLabel = m.hideSenderLabel
    case let m as ChatMessageInfo:
      p.messageType = "INFO"; p.content = m.content; p.side = mapChatSide(m.side)
    case let m as ChatMessageWarning:
      p.messageType = "WARNING"; p.content = m.content; p.side = mapChatSide(m.side)
    case let m as ChatMessageError:
      p.messageType = "ERROR"; p.content = m.content; p.side = mapChatSide(m.side)
    case let m as ChatMessageImage:
      p.messageType = "IMAGE"; p.side = mapChatSide(m.side); p.latencyMs = m.latencyMs
      p.imageFilePaths = m.persistedPaths ?? []
    case let m as ChatMessageAudioClip:
      p.messageType = "AUDIO_CLIP"; p.side = mapChatSide(m.side); p.latencyMs = m.latencyMs
      if let path = m.persistedPath {
        p.audioClips = [AudioMessageProto(filePath: path, sampleRate: Int32(m.sampleRate))]
      }
    default:
      return nil
    }
    return p
  }

  private nonisolated static func mapChatSide(_ side: ChatSide) -> ChatSideProto {
    switch side {
    case .user: return .user
    case .agent: return .model
    case .system: return .system
    }
  }
}
