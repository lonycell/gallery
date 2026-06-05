// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/AgentChatTaskModule.kt (ViewModel portion)
// The Android version reused LlmChatViewModel; we create a thin subclass here.

import Foundation
import SwiftUI

// MARK: - AgentChatViewModel

/// Subclass of ChatViewModel providing agent-chat-specific helpers.
/// Mirrors the usage of `LlmChatViewModel` in `AgentChatScreen.kt`.
@MainActor
final class AgentChatViewModel: ChatViewModel {
    @Published var uiSystemPrompt: String = ""

    /// Queued initial query — consumed by ChatView on first render.
    @Published var pendingQuery: String? = nil

    func loadSystemPrompt(task: Task) {
        uiSystemPrompt = task.defaultSystemPrompt
    }

    func applySystemPromptChange(task: Task, model: Model, newPrompt: String) {
        uiSystemPrompt = newPrompt
        // Persist via DataStoreRepository if needed (SystemPromptRepository handles this on Android)
    }

    func queueInitialQuery(_ query: String) {
        pendingQuery = query
    }

    // MARK: - Progress panel helpers

    func updateCollapsableProgressPanelMessage(model: Model, title: String, inProgress: Bool, addItemTitle: String = "", addItemDescription: String = "", customData: Any? = nil) {
        // NOTE: Mirrors `LlmChatViewModel.updateCollapsableProgressPanelMessage`.
        // Locate the last ChatMessageCollapsableProgressPanel and update it.
        guard var messages = uiState.messagesByModel[model.name] else { return }
        if let last = messages.last as? ChatMessageCollapsableProgressPanel {
            var items = last.items
            if !addItemTitle.isEmpty {
                items.append(CollapsableProgressItem(title: addItemTitle, description: addItemDescription, customData: customData))
            }
            messages[messages.count - 1] = ChatMessageCollapsableProgressPanel(
                title: title, inProgress: inProgress, items: items, side: last.side,
                hideSenderLabel: last.hideSenderLabel, customData: customData)
        } else {
            // No existing panel — create one
            let panel = ChatMessageCollapsableProgressPanel(
                title: title, inProgress: inProgress,
                items: addItemTitle.isEmpty ? [] : [CollapsableProgressItem(title: addItemTitle, description: addItemDescription, customData: customData)],
                side: .agent, hideSenderLabel: true, customData: customData)
            messages.append(panel)
        }
        uiState.messagesByModel[model.name] = messages
    }

    func addLogMessageToLastCollapsableProgressPanel(model: Model, logMessage: LogMessage) {
        guard var messages = uiState.messagesByModel[model.name],
              let last = messages.last as? ChatMessageCollapsableProgressPanel else { return }
        var updated = last
        updated.logMessages.append(logMessage)
        messages[messages.count - 1] = updated
        uiState.messagesByModel[model.name] = messages
    }

    // MARK: - Session reset

    func resetSession(task: Task, model: Model, systemInstruction: String, clearHistory: Bool, initialMessages: [ChatMessage], onDone: @escaping () -> Void) {
        uiState.isResettingSession = true
        // NOTE: LiteRT-LM session reset is stubbed. Replace with LlmModelHelper.resetSession call.
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if clearHistory { clearAllMessages(model: model) }
            for msg in initialMessages { addMessage(model: model, message: msg) }
            uiState.isResettingSession = false
            onDone()
        }
    }
}
