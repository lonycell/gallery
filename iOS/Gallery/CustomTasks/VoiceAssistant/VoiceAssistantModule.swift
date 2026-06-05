// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Port of customtasks/voiceassistant/VoiceAssistantModule.kt
//
// Exposes the factory functions the integrator wires into AppContainer.
// Do NOT edit BuiltInTasks.swift — just call VoiceAssistantModule.make() there.

import Foundation

/// Factory for the Voice Assistant custom task.
///
/// Integrator call:
/// ```swift
/// let vaTask = VoiceAssistantModule.make(
///     characterRepository: container.characterRepository
/// )
/// container.modelManagerViewModel = ModelManagerViewModel(
///     ...
///     customTasks: [vaTask, /* other tasks */]
/// )
/// ```
enum VoiceAssistantModule {

    /// Creates a fully wired `VoiceAssistantTask` ready to be registered in the app container.
    ///
    /// - Parameter characterRepository: The shared character repository (from AppContainer).
    /// - Returns: A `CustomTask` implementing the voice-assistant feature.
    static func make(characterRepository: CharacterRepository) -> VoiceAssistantTask {
        let entryParams = VoiceAssistantEntryParams()
        let historyStore = ChatHistoryStore()
        let promptSource = SampleVoiceAssistantPromptSource(characterRepository: characterRepository)
        return VoiceAssistantTask(
            promptSource: promptSource,
            entryParams: entryParams,
            characterRepository: characterRepository,
            chatHistoryStore: historyStore
        )
    }
}
