// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Port of customtasks/voiceassistant/prompts/VoiceAssistantPromptSource.kt

import Foundation

/// Supplies the system prompts / topic metadata used by the Voice Assistant.
///
/// Designed as a protocol so the prompt source can evolve (remote API, DataStore,
/// downloaded prompt pack) without changing callers.
protocol VoiceAssistantPromptSource: AnyObject {
    /// Returns the prompt bundle for the given `topic`.
    ///
    /// When `topic` is nil or doesn't match a curated topic, implementations should
    /// return a usable default that still incorporates the raw `topic` text.
    func getPromptForTopic(_ topic: String?) async -> TopicPrompt

    /// Returns the list of curated topics that can be offered to the user.
    func listTopics() async -> [TopicPrompt]
}
