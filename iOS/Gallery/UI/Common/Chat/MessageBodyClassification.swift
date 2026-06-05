/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyClassification.kt

import SwiftUI

/// A single classification result with label, score, and progress bar.
struct MessageBodyClassification: View {
  let message: ChatMessageClassification
  var oneLineLabel: Bool = false

  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(message.classifications, id: \.label) { c in
        HStack(alignment: .bottom) {
          Text(c.label)
            .font(.caption)
            .lineLimit(oneLineLabel ? 1 : nil)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
          Text(String(format: "%.2f", c.score))
            .font(.caption)
        }
        // Score bar
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
              .fill(colors.surfaceDim)
              .frame(height: 8)
            RoundedRectangle(cornerRadius: 4)
              .fill(c.color)
              .frame(width: geo.size.width * CGFloat(c.score), height: 8)
          }
        }
        .frame(height: 8)
      }
    }
    .padding(12)
  }
}

// Classification is defined in Common/Types.swift — do not redeclare here.
