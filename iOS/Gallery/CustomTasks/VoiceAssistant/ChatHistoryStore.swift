// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Port of customtasks/voiceassistant/ChatHistoryStore.kt

import Foundation

private let TAG = "AGChatHistoryStore"
/// Cap on stored messages per conversation to keep storage and LLM context bounded.
private let MAX_STORED_MESSAGES = 100

/// Persists the voice chat history on disk, one conversation per character,
/// as a small JSON file. Used both to restore on-screen messages and to seed
/// the LLM's context when a character is (re)selected.
final class ChatHistoryStore {

    private lazy var dir: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("voice_chat_history", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private func fileFor(_ conversationId: String) -> URL {
        let safe = conversationId.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "_",
            options: .regularExpression
        )
        return dir.appendingPathComponent("\(safe).json")
    }

    /// Loads the stored messages for `conversationId` (empty if none).
    func load(_ conversationId: String) -> [VoiceMessage] {
        guard !conversationId.isEmpty else { return [] }
        let file = fileFor(conversationId)
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }
        return arr.compactMap { obj -> VoiceMessage? in
            guard let r = obj["r"], let t = obj["t"] else { return nil }
            let role: VoiceMessage.Role = (r == "u") ? .user : .assistant
            return VoiceMessage(role: role, text: t)
        }
    }

    /// Saves `messages` for `conversationId` (keeps only the most recent ones).
    func save(_ conversationId: String, messages: [VoiceMessage]) {
        guard !conversationId.isEmpty else { return }
        let arr = messages.suffix(MAX_STORED_MESSAGES)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { ["r": ($0.role == .user ? "u" : "a"), "t": $0.text] }
        guard let data = try? JSONSerialization.data(withJSONObject: arr) else { return }
        try? data.write(to: fileFor(conversationId))
    }
}
