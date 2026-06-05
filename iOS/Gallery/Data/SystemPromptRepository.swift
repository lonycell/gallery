/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of data/SystemPromptRepository.kt
//
// On Android prompts were stored in the UserData proto's `secrets` map. iOS keeps
// the same shape via DataStoreRepository's UserData store.

import Foundation

/// Repository for per-task custom system prompts. Mirrors `SystemPromptRepository`.
class SystemPromptRepository {
  private let store: DataStoreRepository
  init(store: DataStoreRepository) { self.store = store }

  private func key(_ taskId: String) -> String { "system_prompt_\(taskId)" }

  func updateSystemPrompt(taskId: String, newPrompt: String) async {
    await store.updateUserData { data in
      data.secrets[self.key(taskId)] = newPrompt
    }
  }

  func getCustomSystemPrompt(taskId: String) async -> String? {
    await store.readUserData().secrets[key(taskId)]
  }

  func clearCustomSystemPrompt(taskId: String) async {
    await store.updateUserData { data in
      data.secrets.removeValue(forKey: self.key(taskId))
    }
  }
}
