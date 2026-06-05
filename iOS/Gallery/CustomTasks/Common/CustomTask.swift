/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of customtasks/common/CustomTask.kt
//
// A CustomTask is a pluggable feature module surfaced on the home screen. On
// Android tasks were bound into a Hilt @IntoSet; on iOS they are registered in
// `AppContainer.customTasks`. `mainScreen` returns an erased SwiftUI view, the
// analogue of the `@Composable fun MainScreen(data: Any)`.

import SwiftUI

protocol CustomTask: AnyObject {
  /// Metadata for this task and its models. See `Task`.
  var task: Task { get }

  /// Initialize/prepare a model with an optional system instruction.
  func initializeModelFn(model: Model, systemInstruction: Contents?, onDone: @escaping (_ error: String) -> Void)

  /// Clean up resources associated with a model.
  func cleanUpModelFn(model: Model, onDone: @escaping () -> Void)

  /// The main SwiftUI screen for this task's detail view. `data` is a `CustomTaskData`
  /// (or `CustomTaskDataForBuiltinTask` for legacy built-in tasks).
  @MainActor func mainScreen(data: Any) -> AnyView
}
