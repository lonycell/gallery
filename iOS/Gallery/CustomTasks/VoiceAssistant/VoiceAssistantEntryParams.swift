// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Port of customtasks/voiceassistant/VoiceAssistantEntryParams.kt

import Foundation
import Combine

/// Holds the optional entry "topic"/"problem" parameter for the Voice Assistant.
///
/// The Voice Assistant can be opened either:
/// - from the home-screen task card (no topic → general assistant), or
/// - programmatically with a specific subject. Callers should call `setTopic(_:)`
///   BEFORE navigating into the task; it is consumed once so it doesn't persist.
///
/// A process-wide singleton is used (rather than nav arguments) because custom tasks
/// are launched through the shared CustomTask framework, which doesn't thread per-task
/// parameters through.
final class VoiceAssistantEntryParams: ObservableObject {
    @Published private(set) var topic: String? = nil

    func setTopic(_ topic: String?) {
        let trimmed = topic?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.topic = (trimmed?.isEmpty == true) ? nil : trimmed
    }

    /// Returns the current topic and clears it so it is only applied once.
    func consumeTopic() -> String? {
        let current = topic
        topic = nil
        return current
    }
}
