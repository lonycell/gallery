/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyImage.kt

import SwiftUI

struct MessageBodyImage: View {
  let message: ChatMessageImage
  var onImageClicked: ([UIImage], Int) -> Void = { _, _ in }

  var body: some View {
    let images = message.images
    let count = images.count
    if count == 1 {
      singleImage(images[0], index: 0)
    } else {
      multiImageGrid(images)
    }
  }

  @ViewBuilder
  private func singleImage(_ img: UIImage, index: Int) -> some View {
    let maxSize = CGFloat(message.maxSize)
    let w = CGFloat(img.size.width)
    let h = CGFloat(img.size.height)
    let (dw, dh): (CGFloat, CGFloat) = {
      if w >= maxSize || h >= maxSize {
        if w >= h {
          return (maxSize, maxSize / w * h)
        } else {
          return (maxSize / h * w, maxSize)
        }
      }
      return (w, h)
    }()

    Image(uiImage: img)
      .resizable()
      .scaledToFit()
      .frame(width: dw, height: dh)
      .onTapGesture { onImageClicked(message.images, index) }
  }

  @ViewBuilder
  private func multiImageGrid(_ images: [UIImage]) -> some View {
    let colCount = images.count == 4 ? 2 : 3
    let rows = Int(ceil(Double(images.count) / Double(colCount)))
    VStack(alignment: .trailing, spacing: 2) {
      ForEach(0..<rows, id: \.self) { row in
        HStack(spacing: 2) {
          ForEach(0..<colCount, id: \.self) { col in
            let idx = row * colCount + col
            if idx < images.count {
              Image(uiImage: images[idx])
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipped()
                .onTapGesture { onImageClicked(message.images, idx) }
            }
          }
        }
      }
    }
  }
}
