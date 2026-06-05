/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/theme/Theme.kt
//
// Compose used MaterialTheme.colorScheme + a CustomColors CompositionLocal.
// SwiftUI mirrors that with a `GalleryColors` struct (the Material color roles)
// and a `CustomColors` struct, both injected through the Environment and read as
// `@Environment(\.galleryColors)` / `@Environment(\.customColors)`.

import SwiftUI

/// Material 3 color roles. Mirrors `androidx.compose.material3.ColorScheme`.
struct GalleryColors {
  let primary, onPrimary, primaryContainer, onPrimaryContainer: Color
  let secondary, onSecondary, secondaryContainer, onSecondaryContainer: Color
  let tertiary, onTertiary, tertiaryContainer, onTertiaryContainer: Color
  let error, onError, errorContainer, onErrorContainer: Color
  let background, onBackground: Color
  let surface, onSurface, surfaceVariant, onSurfaceVariant: Color
  let surfaceContainerLowest, surfaceContainerLow, surfaceContainer: Color
  let surfaceContainerHigh, surfaceContainerHighest: Color
  let inverseSurface, inverseOnSurface, inversePrimary: Color
  let outline, outlineVariant, scrim, surfaceDim, surfaceBright: Color
}

let lightScheme = GalleryColors(
  primary: primaryLight, onPrimary: onPrimaryLight,
  primaryContainer: primaryContainerLight, onPrimaryContainer: onPrimaryContainerLight,
  secondary: secondaryLight, onSecondary: onSecondaryLight,
  secondaryContainer: secondaryContainerLight, onSecondaryContainer: onSecondaryContainerLight,
  tertiary: tertiaryLight, onTertiary: onTertiaryLight,
  tertiaryContainer: tertiaryContainerLight, onTertiaryContainer: onTertiaryContainerLight,
  error: errorLight, onError: onErrorLight,
  errorContainer: errorContainerLight, onErrorContainer: onErrorContainerLight,
  background: backgroundLight, onBackground: onBackgroundLight,
  surface: surfaceLight, onSurface: onSurfaceLight,
  surfaceVariant: surfaceVariantLight, onSurfaceVariant: onSurfaceVariantLight,
  surfaceContainerLowest: surfaceContainerLowestLight, surfaceContainerLow: surfaceContainerLowLight,
  surfaceContainer: surfaceContainerLight, surfaceContainerHigh: surfaceContainerHighLight,
  surfaceContainerHighest: surfaceContainerHighestLight,
  inverseSurface: inverseSurfaceLight, inverseOnSurface: inverseOnSurfaceLight,
  inversePrimary: inversePrimaryLight,
  outline: outlineLight, outlineVariant: outlineVariantLight, scrim: scrimLight,
  surfaceDim: surfaceDimLight, surfaceBright: surfaceBrightLight)

let darkScheme = GalleryColors(
  primary: primaryDark, onPrimary: onPrimaryDark,
  primaryContainer: primaryContainerDark, onPrimaryContainer: onPrimaryContainerDark,
  secondary: secondaryDark, onSecondary: onSecondaryDark,
  secondaryContainer: secondaryContainerDark, onSecondaryContainer: onSecondaryContainerDark,
  tertiary: tertiaryDark, onTertiary: onTertiaryDark,
  tertiaryContainer: tertiaryContainerDark, onTertiaryContainer: onTertiaryContainerDark,
  error: errorDark, onError: onErrorDark,
  errorContainer: errorContainerDark, onErrorContainer: onErrorContainerDark,
  background: backgroundDark, onBackground: onBackgroundDark,
  surface: surfaceDark, onSurface: onSurfaceDark,
  surfaceVariant: surfaceVariantDark, onSurfaceVariant: onSurfaceVariantDark,
  surfaceContainerLowest: surfaceContainerLowestDark, surfaceContainerLow: surfaceContainerLowDark,
  surfaceContainer: surfaceContainerDark, surfaceContainerHigh: surfaceContainerHighDark,
  surfaceContainerHighest: surfaceContainerHighestDark,
  inverseSurface: inverseSurfaceDark, inverseOnSurface: inverseOnSurfaceDark,
  inversePrimary: inversePrimaryDark,
  outline: outlineDark, outlineVariant: outlineVariantDark, scrim: scrimDark,
  surfaceDim: surfaceDimDark, surfaceBright: surfaceBrightDark)

/// App-specific extra palette. Mirrors `ui/theme/Theme.kt#CustomColors`.
struct CustomColors {
  var appTitleGradientColors: [Color] = []
  var tabHeaderBgColor: Color = .clear
  var taskCardBgColor: Color = .clear
  var taskBgColors: [Color] = []
  var taskBgGradientColors: [[Color]] = []
  var taskIconColors: [Color] = []
  var taskIconShapeBgColor: Color = .clear
  var homeBottomGradient: [Color] = []
  var userBubbleBgColor: Color = .clear
  var agentBubbleBgColor: Color = .clear
  var linkColor: Color = .clear
  var successColor: Color = .clear
  var recordButtonBgColor: Color = .clear
  var waveFormBgColor: Color = .clear
  var modelInfoIconColor: Color = .clear
  var warningContainerColor: Color = .clear
  var warningTextColor: Color = .clear
  var errorContainerColor: Color = .clear
  var errorTextColor: Color = .clear
  var newFeatureContainerColor: Color = .clear
  var newFeatureTextColor: Color = .clear
  var bgStarColor: Color = .clear
  var promoBannerBgColors: [Color] = []
  var promoBannerIconBgColors: [Color] = []
}

let lightCustomColors = CustomColors(
  appTitleGradientColors: [Color(argb: 0xFF85B1F8), Color(argb: 0xFF3174F1)],
  tabHeaderBgColor: Color(argb: 0xFF3174F1),
  taskCardBgColor: surfaceContainerLowestLight,
  taskBgColors: [Color(argb: 0xFFFFF5F5), Color(argb: 0xFFF4FBF6), Color(argb: 0xFFF1F6FE), Color(argb: 0xFFFFFBF0)],
  taskBgGradientColors: [
    [Color(argb: 0xFFE25F57), Color(argb: 0xFFDB372D)],
    [Color(argb: 0xFF41A15F), Color(argb: 0xFF128937)],
    [Color(argb: 0xFF669DF6), Color(argb: 0xFF3174F1)],
    [Color(argb: 0xFFFDD45D), Color(argb: 0xFFCAA12A)],
  ],
  taskIconColors: [Color(argb: 0xFFDB372D), Color(argb: 0xFF128937), Color(argb: 0xFF3174F1), Color(argb: 0xFFCAA12A)],
  taskIconShapeBgColor: .white,
  homeBottomGradient: [Color(argb: 0x00F8F9FF), Color(argb: 0xFFFFEFC9)],
  userBubbleBgColor: Color(argb: 0xFF32628D),
  agentBubbleBgColor: Color(argb: 0xFFE9EEF6),
  linkColor: Color(argb: 0xFF32628D),
  successColor: Color(argb: 0xFF3D860B),
  recordButtonBgColor: Color(argb: 0xFFEE675C),
  waveFormBgColor: Color(argb: 0xFFAAAAAA),
  modelInfoIconColor: Color(argb: 0xFFCCCCCC),
  warningContainerColor: Color(argb: 0xFFFEF7E0),
  warningTextColor: Color(argb: 0xFFE37400),
  errorContainerColor: Color(argb: 0xFFFCE8E6),
  errorTextColor: Color(argb: 0xFFD93025),
  newFeatureContainerColor: Color(argb: 0xFFEEDCFE),
  newFeatureTextColor: Color(argb: 0xFF400B84),
  bgStarColor: Color(argb: 0x3A669AF5),
  promoBannerBgColors: [Color(argb: 0x42ACB7FF), Color(argb: 0x422D96FF), Color(argb: 0x423C6BFF)],
  promoBannerIconBgColors: [Color(argb: 0x3B446EFF), Color(argb: 0x3B2E96FF), Color(argb: 0x3BB1C5FF)])

let darkCustomColors = CustomColors(
  appTitleGradientColors: [Color(argb: 0xFF85B1F8), Color(argb: 0xFF3174F1)],
  tabHeaderBgColor: Color(argb: 0xFF3174F1),
  taskCardBgColor: surfaceContainerHighDark,
  taskBgColors: [Color(argb: 0xFF181210), Color(argb: 0xFF131711), Color(argb: 0xFF191924), Color(argb: 0xFF1A1813)],
  taskBgGradientColors: [
    [Color(argb: 0xFFE25F57), Color(argb: 0xFFDB372D)],
    [Color(argb: 0xFF41A15F), Color(argb: 0xFF128937)],
    [Color(argb: 0xFF669DF6), Color(argb: 0xFF3174F1)],
    [Color(argb: 0xFFFDD45D), Color(argb: 0xFFCAA12A)],
  ],
  taskIconColors: [Color(argb: 0xFFE25F57), Color(argb: 0xFF41A15F), Color(argb: 0xFF669DF6), Color(argb: 0xFFCAA12A)],
  taskIconShapeBgColor: Color(argb: 0xFF202124),
  homeBottomGradient: [Color(argb: 0x00F8F9FF), Color(argb: 0x1AF6AD01)],
  userBubbleBgColor: Color(argb: 0xFF1F3760),
  agentBubbleBgColor: Color(argb: 0xFF1B1C1D),
  linkColor: Color(argb: 0xFF9DCAFC),
  successColor: Color(argb: 0xFFA1CE83),
  recordButtonBgColor: Color(argb: 0xFFEE675C),
  waveFormBgColor: Color(argb: 0xFFAAAAAA),
  modelInfoIconColor: Color(argb: 0xFFCCCCCC),
  warningContainerColor: Color(argb: 0xFF554C33),
  warningTextColor: Color(argb: 0xFFFCC934),
  errorContainerColor: Color(argb: 0xFF523A3B),
  errorTextColor: Color(argb: 0xFFEE675C),
  newFeatureContainerColor: Color(argb: 0xFFEEDCFE),
  newFeatureTextColor: Color(argb: 0xFF400B84),
  bgStarColor: Color(argb: 0x19346BF0),
  promoBannerBgColors: [Color(argb: 0x82183570), Color(argb: 0x820A122D)],
  promoBannerIconBgColors: [Color(argb: 0x6F0F41F8), Color(argb: 0x6F1685F8), Color(argb: 0x6F809EF3)])

// MARK: - Environment plumbing

private struct GalleryColorsKey: EnvironmentKey {
  static let defaultValue: GalleryColors = lightScheme
}
private struct CustomColorsKey: EnvironmentKey {
  static let defaultValue: CustomColors = lightCustomColors
}

extension EnvironmentValues {
  var galleryColors: GalleryColors {
    get { self[GalleryColorsKey.self] }
    set { self[GalleryColorsKey.self] = newValue }
  }
  var customColors: CustomColors {
    get { self[CustomColorsKey.self] }
    set { self[CustomColorsKey.self] = newValue }
  }
}

/// Root theme wrapper. Mirrors the `GalleryTheme { content }` composable: resolves
/// dark/light from the system setting + the user's `ThemeSettings.themeOverride`,
/// then injects color schemes and the Nunito-based default font.
struct GalleryTheme<Content: View>: View {
  @ObservedObject private var themeSettings = ThemeSettings.shared
  @Environment(\.colorScheme) private var systemScheme
  let content: () -> Content

  init(@ViewBuilder content: @escaping () -> Content) {
    self.content = content
  }

  private var isDark: Bool {
    let override = themeSettings.themeOverride
    return (systemScheme == .dark || override == .themeDark) && override != .themeLight
  }

  var body: some View {
    let colors = isDark ? darkScheme : lightScheme
    let custom = isDark ? darkCustomColors : lightCustomColors
    content()
      .environment(\.galleryColors, colors)
      .environment(\.customColors, custom)
      .tint(colors.primary)
      .preferredColorScheme(
        themeSettings.themeOverride == .themeLight ? .light
          : themeSettings.themeOverride == .themeDark ? .dark : nil)
  }
}
