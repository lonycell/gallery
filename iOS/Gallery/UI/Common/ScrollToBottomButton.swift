/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/ScrollToBottomButton.kt

import SwiftUI

/// Animated icon button that appears when the user is not at the bottom of a scroll view.
/// Mirrors `ScrollToBottomButton`.
struct ScrollToBottomButton: View {
  let isAtBottom: Bool
  let onClick: () -> Void

  @Environment(\.galleryColors) private var colors

  var body: some View {
    if !isAtBottom {
      Button(action: onClick) {
        Image(systemName: "arrow.down")
          .foregroundStyle(colors.onSecondaryContainer)
      }
      .buttonStyle(.plain)
      .frame(width: 40, height: 40)
      .background(colors.secondaryContainer)
      .clipShape(Circle())
      .accessibilityLabel("맨 아래로 스크롤")
      .transition(
        .scale(scale: 0.8)
          .combined(with: .opacity)
      )
    }
  }
}
