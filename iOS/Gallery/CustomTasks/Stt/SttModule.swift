// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of customtasks/stt/SttModule.kt

import Foundation

/// Factory for the Speech-to-Text custom task.
///
/// Register this task by adding `SttModule.make()` to the `customTasks` array
/// in `AppContainer` (or wherever `FeatureTaskModules` wires tasks).
///
/// Do NOT edit `BuiltInTasks.swift`.
enum SttModule {
  /// Returns the Speech-to-Text `CustomTask` instance.
  static func make() -> any CustomTask {
    SttTask()
  }
}
