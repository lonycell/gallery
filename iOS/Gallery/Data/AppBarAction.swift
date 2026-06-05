/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of data/AppBarAction.kt

import Foundation

enum AppBarActionType {
  case noAction
  case appSetting
  case downloadManager
  case navigateUp
  case menu
}

struct AppBarAction {
  let actionType: AppBarActionType
  let actionFn: () -> Void
}
