// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/tts/TtsModule.kt

import Foundation

/// Factory for the Text-to-Speech custom task.
///
/// Register this task by adding `TtsModule.make()` to the `customTasks` array
/// in `AppContainer` (or wherever `FeatureTaskModules` wires tasks).
///
/// Do NOT edit `BuiltInTasks.swift`.
enum TtsModule {
  /// Returns the Text-to-Speech `CustomTask` instance.
  static func make() -> any CustomTask {
    TtsTask()
  }
}
