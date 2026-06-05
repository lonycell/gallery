/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/theme/ThemeSettings.kt
//
// Compose used a global `object ThemeSettings { val themeOverride: MutableState<Theme> }`.
// SwiftUI uses a shared ObservableObject so views recompose on theme changes.

import Foundation
import Combine

final class ThemeSettings: ObservableObject {
  static let shared = ThemeSettings()
  @Published var themeOverride: Theme = .themeAuto
  private init() {}
}
