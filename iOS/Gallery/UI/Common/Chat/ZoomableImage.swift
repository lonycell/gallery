/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/ZoomableImage.kt

import SwiftUI

/// A zoomable and pannable image view backed by pinch-to-zoom and drag gestures.
struct ZoomableImage: View {
  let image: UIImage
  var minScale: CGFloat = 1.0
  var maxScale: CGFloat = 3.0

  @State private var scale: CGFloat = 1.0
  @State private var lastScale: CGFloat = 1.0
  @State private var offset: CGSize = .zero
  @State private var lastOffset: CGSize = .zero

  var body: some View {
    Image(uiImage: image)
      .resizable()
      .scaledToFit()
      .scaleEffect(scale)
      .offset(offset)
      .gesture(
        SimultaneousGesture(
          MagnificationGesture()
            .onChanged { value in
              let newScale = lastScale * value
              scale = min(maxScale, max(minScale, newScale))
            }
            .onEnded { _ in
              lastScale = scale
              if scale <= minScale {
                withAnimation(.spring()) {
                  scale = minScale
                  offset = .zero
                  lastOffset = .zero
                }
                lastScale = minScale
              }
            },
          DragGesture()
            .onChanged { value in
              if scale > 1 {
                offset = CGSize(
                  width: lastOffset.width + value.translation.width,
                  height: lastOffset.height + value.translation.height
                )
              }
            }
            .onEnded { _ in
              lastOffset = offset
            }
        )
      )
      .animation(.interactiveSpring(), value: scale)
  }
}
