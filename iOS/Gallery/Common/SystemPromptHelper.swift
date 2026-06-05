/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of common/SystemPromptHelper.kt

import Foundation

/// Helper for system-prompt retrieval. Mirrors `object SystemPromptHelper`.
enum SystemPromptHelper {
  /// Returns the user-defined custom prompt from the repository if present,
  /// otherwise the task's default system prompt.
  static func getEffectiveSystemPrompt(repo: SystemPromptRepository?, task: Task) async -> String {
    guard let repo else { return task.defaultSystemPrompt }
    let custom = await repo.getCustomSystemPrompt(taskId: task.id)
    return custom ?? task.defaultSystemPrompt
  }
}
