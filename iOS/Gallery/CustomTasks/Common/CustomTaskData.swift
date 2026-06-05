/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of customtasks/common/CustomTaskData.kt

import SwiftUI

/// Data passed to a custom task's `mainScreen`. Mirrors `CustomTaskData`.
struct CustomTaskData {
  let modelManagerViewModel: ModelManagerViewModel
  var bottomPadding: CGFloat = 0
  var setAppBarControlsDisabled: (Bool) -> Void = { _ in }
  var setTopBarVisible: (Bool) -> Void = { _ in }
  var setCustomNavigateUpCallback: ((() -> Void)?) -> Void = { _ in }
}

/// Data passed to the legacy built-in tasks. Mirrors `CustomTaskDataForBuiltinTask`.
struct CustomTaskDataForBuiltinTask {
  let modelManagerViewModel: ModelManagerViewModel
  let onNavUp: () -> Void
  /// Initial query to send to the model when the screen first loads.
  var initialQuery: String? = nil
}
