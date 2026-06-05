/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/llmsingleturn/VerticalSplitView.kt
//
// A vertically split layout with a draggable handle between two views.
// The user can drag the divider to resize the top/bottom panes within the
// specified min-height constraints.

import SwiftUI

struct VerticalSplitView<TopContent: View, BottomContent: View>: View {
  let topView: TopContent
  let bottomView: BottomContent
  private let initialRatio: CGFloat
  private let minTopHeight: CGFloat
  private let minBottomHeight: CGFloat
  private let handleThickness: CGFloat = 20

  @State private var splitRatio: CGFloat

  @Environment(\.customColors) private var customColors

  init(
    initialRatio: CGFloat = 0.5,
    minTopHeight: CGFloat = 250,
    minBottomHeight: CGFloat = 200,
    @ViewBuilder topView: () -> TopContent,
    @ViewBuilder bottomView: () -> BottomContent
  ) {
    self.topView = topView()
    self.bottomView = bottomView()
    self.initialRatio = initialRatio
    self.minTopHeight = minTopHeight
    self.minBottomHeight = minBottomHeight
    self._splitRatio = State(initialValue: initialRatio)
  }

  var body: some View {
    GeometryReader { geo in
      let height = geo.size.height
      let topHeight = max(minTopHeight,
                          min(height - minBottomHeight - handleThickness,
                              splitRatio * height))
      let bottomHeight = max(0, height - topHeight - handleThickness)

      VStack(spacing: 0) {
        topView
          .frame(height: topHeight)

        // Drag handle (mirrors Compose's Box with detectDragGestures).
        ZStack {
          customColors.agentBubbleBgColor
          Capsule()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 32, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: handleThickness)
        .gesture(
          DragGesture(minimumDistance: 1)
            .onChanged { value in
              guard height > 0 else { return }
              let newTopHeight = topHeight + value.translation.height
              let clamped = max(minTopHeight,
                                min(height - minBottomHeight - handleThickness, newTopHeight))
              splitRatio = clamped / height
            })

        bottomView
          .frame(height: bottomHeight)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
  }
}
