/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyImageWithHistory.kt

import SwiftUI

struct MessageBodyImageWithHistory: View {
  let message: ChatMessageImageWithHistory
  @Binding var curIndex: Int

  @GestureState private var dragOffset: CGFloat = 0
  @State private var savedIndex: Int = 0

  var body: some View {
    let images = message.images
    if images.isEmpty { return AnyView(EmptyView()) }
    let cur = images[curIndex]
    let w = cur.size.width
    let h = cur.size.height
    let displayW: CGFloat = w >= h ? 200 : (200 / h * w)
    let displayH: CGFloat = h >= w ? 200 : (200 / w * h)

    return AnyView(
      Image(uiImage: cur)
        .resizable()
        .scaledToFit()
        .frame(width: displayW, height: displayH)
        .gesture(
          DragGesture()
            .updating($dragOffset) { value, state, _ in state = value.translation.width }
            .onChanged { value in
              let delta = value.translation.width / 20.0
              let newIdx = (savedIndex + Int(delta))
                .clamped(to: 0...(images.count - 1))
              curIndex = newIdx
            }
            .onEnded { _ in savedIndex = curIndex }
        )
        .onAppear {
          curIndex = max(0, images.count - 1)
          savedIndex = curIndex
        }
    )
  }
}

private extension Int {
  func clamped(to range: ClosedRange<Int>) -> Int {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
