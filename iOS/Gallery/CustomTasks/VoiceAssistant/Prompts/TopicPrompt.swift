// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Port of customtasks/voiceassistant/prompts/TopicPrompt.kt

import Foundation

/// A prompt bundle describing how the Voice Assistant should behave for a given topic.
struct TopicPrompt {
    /// A stable identifier (e.g. "general", "language_tutor").
    let topicId: String
    /// A short, human-readable title shown in the UI.
    let title: String
    /// The system instruction that primes the LLM for this topic.
    let systemPrompt: String
    /// Suggested opening utterances the user can tap.
    let starters: [String]
    /// Optional BCP-47 language tag (e.g. "ko-KR"). Nil means use the device default.
    let bcp47Language: String?

    static let GENERAL_TOPIC_ID = "general"

    init(topicId: String, title: String, systemPrompt: String,
         starters: [String] = [], bcp47Language: String? = nil) {
        self.topicId = topicId
        self.title = title
        self.systemPrompt = systemPrompt
        self.starters = starters
        self.bcp47Language = bcp47Language
    }
}
