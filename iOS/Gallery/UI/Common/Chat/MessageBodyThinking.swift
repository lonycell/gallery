/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyThinking.kt

import SwiftUI

struct MessageBodyThinking: View {
  let thinkingText: String
  let inProgress: Bool
  var onCopyClicked: (String) -> Void = { _ in }

  @State private var isExpanded = false
  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header toggle row
      Button {
        withAnimation { isExpanded.toggle() }
      } label: {
        HStack(spacing: 4) {
          Text(Str.showThinking)
            .font(.subheadline).fontWeight(.medium)
            .foregroundColor(colors.onSurface)
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.caption)
            .foregroundColor(colors.onSurface)
        }
        .padding(.vertical, 4)
      }
      .buttonStyle(.plain)

      // Expandable content
      if isExpanded || inProgress {
        LongPressCopyContainer(copyText: thinkingText, onCopyClicked: onCopyClicked) {
          Text(thinkingText)
            .font(.caption)
            .foregroundColor(colors.onSurfaceVariant)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .padding(.leading, 12)
            .overlay(
              Rectangle()
                .fill(colors.outlineVariant)
                .frame(width: 2),
              alignment: .leading
            )
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .onChange(of: inProgress) { val in
      if val { withAnimation { isExpanded = true } }
    }
    .onAppear { if inProgress { isExpanded = true } }
  }
}
