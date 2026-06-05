/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/theme/Color.kt — Material 3 light/dark tonal palettes.

import SwiftUI

let primaryLight = Color(hex: 0x0B57D0)
let onPrimaryLight = Color(hex: 0xFFFFFF)
let primaryContainerLight = Color(hex: 0xD3E3FD)
let onPrimaryContainerLight = Color(hex: 0x0842A0)
let secondaryLight = Color(hex: 0x00639B)
let onSecondaryLight = Color(hex: 0xFFFFFF)
let secondaryContainerLight = Color(hex: 0xC2E7FF)
let onSecondaryContainerLight = Color(hex: 0x004A77)
let tertiaryLight = Color(hex: 0x146C2E)
let onTertiaryLight = Color(hex: 0xFFFFFF)
let tertiaryContainerLight = Color(hex: 0xC4EED0)
let onTertiaryContainerLight = Color(hex: 0x0F5223)
let errorLight = Color(hex: 0xB3261E)
let onErrorLight = Color(hex: 0xFFFFFF)
let errorContainerLight = Color(hex: 0xF9DEDC)
let onErrorContainerLight = Color(hex: 0x8C1D18)
let backgroundLight = Color(hex: 0xFFFFFF)
let onBackgroundLight = Color(hex: 0x1F1F1F)
let surfaceLight = Color(hex: 0xFFFFFF)
let onSurfaceLight = Color(hex: 0x1F1F1F)
let surfaceVariantLight = Color(hex: 0xE1E3E1)
let onSurfaceVariantLight = Color(hex: 0x444746)
let surfaceContainerLowestLight = Color(hex: 0xFFFFFF)
let surfaceContainerLowLight = Color(hex: 0xF8FAFD)
let surfaceContainerLight = Color(hex: 0xF0F4F9)
let surfaceContainerHighLight = Color(hex: 0xE9EEF6)
let surfaceContainerHighestLight = Color(hex: 0xDDE3EA)
let inverseSurfaceLight = Color(hex: 0x303030)
let inverseOnSurfaceLight = Color(hex: 0xF2F2F2)
let outlineLight = Color(hex: 0x747775)
let outlineVariantLight = Color(hex: 0xC4C7C5)
let inversePrimaryLight = Color(hex: 0xA8C7FA)
let surfaceDimLight = Color(hex: 0xD3DBE5)
let surfaceBrightLight = Color(hex: 0xFFFFFF)
let scrimLight = Color(hex: 0x000000)

let primaryDark = Color(hex: 0xA8C7FA)
let onPrimaryDark = Color(hex: 0x062E6F)
let primaryContainerDark = Color(hex: 0x0842A0)
let onPrimaryContainerDark = Color(hex: 0xD3E3FD)
let secondaryDark = Color(hex: 0x7FCFFF)
let onSecondaryDark = Color(hex: 0x003355)
let secondaryContainerDark = Color(hex: 0x004A77)
let onSecondaryContainerDark = Color(hex: 0xC2E7FF)
let tertiaryDark = Color(hex: 0x6DD58C)
let onTertiaryDark = Color(hex: 0x0A3818)
let tertiaryContainerDark = Color(hex: 0x0F5223)
let onTertiaryContainerDark = Color(hex: 0xC4EED0)
let errorDark = Color(hex: 0xF2B8B5)
let onErrorDark = Color(hex: 0x601410)
let errorContainerDark = Color(hex: 0x8C1D18)
let onErrorContainerDark = Color(hex: 0xF9DEDC)
let backgroundDark = Color(hex: 0x131314)
let onBackgroundDark = Color(hex: 0xE3E3E3)
let surfaceDark = Color(hex: 0x131314)
let onSurfaceDark = Color(hex: 0xE3E3E3)
let surfaceVariantDark = Color(hex: 0x444746)
let onSurfaceVariantDark = Color(hex: 0xC4C7C5)
let surfaceContainerLowestDark = Color(hex: 0x0E0E0E)
let surfaceContainerLowDark = Color(hex: 0x1B1B1B)
let surfaceContainerDark = Color(hex: 0x1E1F20)
let surfaceContainerHighDark = Color(hex: 0x282A2C)
let surfaceContainerHighestDark = Color(hex: 0x333537)
let inverseSurfaceDark = Color(hex: 0xE3E3E3)
let inverseOnSurfaceDark = Color(hex: 0x303030)
let outlineDark = Color(hex: 0x8E918F)
let outlineVariantDark = Color(hex: 0x444746)
let inversePrimaryDark = Color(hex: 0x0B57D0)
let surfaceDimDark = Color(hex: 0x131314)
let surfaceBrightDark = Color(hex: 0x37393B)
let scrimDark = Color(hex: 0x000000)

extension Color {
  /// Build a Color from a 0xRRGGBB int (optionally with 0xAARRGGBB).
  init(hex: UInt32) {
    let hasAlpha = hex > 0xFFFFFF
    let a = hasAlpha ? Double((hex >> 24) & 0xFF) / 255.0 : 1.0
    let r = Double((hex >> 16) & 0xFF) / 255.0
    let g = Double((hex >> 8) & 0xFF) / 255.0
    let b = Double(hex & 0xFF) / 255.0
    self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
  }

  /// Build a Color from 0xAARRGGBB (explicit alpha channel), matching the
  /// Compose `Color(0xAARRGGBB)` literals used in CustomColors.
  init(argb: UInt32) {
    let a = Double((argb >> 24) & 0xFF) / 255.0
    let r = Double((argb >> 16) & 0xFF) / 255.0
    let g = Double((argb >> 8) & 0xFF) / 255.0
    let b = Double(argb & 0xFF) / 255.0
    self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
  }
}
