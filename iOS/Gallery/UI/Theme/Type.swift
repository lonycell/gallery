/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/theme/Type.kt — Nunito font family + Material-style text styles.

import SwiftUI

/// The Nunito family registered via Info.plist `UIAppFonts`. Mirrors `appFontFamily`.
enum AppFont {
  static let regular = "Nunito-Regular"
  static let extraLight = "Nunito-ExtraLight"
  static let light = "Nunito-Light"
  static let medium = "Nunito-Medium"
  static let semiBold = "Nunito-SemiBold"
  static let bold = "Nunito-Bold"
  static let extraBold = "Nunito-ExtraBold"
  static let black = "Nunito-Black"

  /// Resolve a Nunito font for the given SwiftUI weight, falling back gracefully.
  static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    let name: String
    switch weight {
    case .black: name = black
    case .heavy: name = extraBold
    case .bold: name = bold
    case .semibold: name = semiBold
    case .medium: name = medium
    case .light: name = light
    case .ultraLight, .thin: name = extraLight
    default: name = regular
    }
    return .custom(name, size: size)
  }
}

/// Material 3 type scale approximated with Nunito. Mirrors `AppTypography`
/// and the extra named styles in Type.kt.
enum AppTypography {
  static let displayLarge = AppFont.font(size: 57)
  static let displayMedium = AppFont.font(size: 45)
  static let displaySmall = AppFont.font(size: 36)
  static let headlineLarge = AppFont.font(size: 32)
  static let headlineMedium = AppFont.font(size: 28)
  static let headlineSmall = AppFont.font(size: 24)
  static let titleLarge = AppFont.font(size: 22)
  static let titleMedium = AppFont.font(size: 16, weight: .medium)
  static let titleSmall = AppFont.font(size: 14, weight: .medium)
  static let bodyLarge = AppFont.font(size: 16)
  static let bodyMedium = AppFont.font(size: 14)
  static let bodySmall = AppFont.font(size: 12)
  static let labelLarge = AppFont.font(size: 14, weight: .medium)
  static let labelMedium = AppFont.font(size: 12, weight: .medium)
  static let labelSmall = AppFont.font(size: 11, weight: .medium)

  // Extra named styles from Type.kt.
  static let titleMediumNarrow = AppFont.font(size: 16, weight: .medium)
  static let titleSmaller = AppFont.font(size: 12, weight: .bold)
  static let labelSmallNarrow = AppFont.font(size: 11)
  static let labelSmallNarrowMedium = AppFont.font(size: 11, weight: .medium)
  static let bodySmallNarrow = AppFont.font(size: 12)
  static let bodySmallMediumNarrow = AppFont.font(size: 14)
  static let bodySmallMediumNarrowBold = AppFont.font(size: 14, weight: .bold)
  static let homePageTitleStyle = AppFont.font(size: 48, weight: .medium)
  static let bodyLargeNarrow = AppFont.font(size: 16)
  static let bodyMediumMedium = AppFont.font(size: 14, weight: .medium)
  static let headlineLargeMedium = AppFont.font(size: 32, weight: .medium)
  static let emptyStateTitle = AppFont.font(size: 37)
  static let emptyStateContent = AppFont.font(size: 16)
}
