// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/home/SquareDrawerItem.kt

import SwiftUI

/// Square drawer tile with icon, label and description.
/// Mirrors `SquareDrawerItem`.
struct SquareDrawerItem: View {
  let label: String
  let description: String
  let systemImage: String
  let onClick: () -> Void
  var iconGradient: LinearGradient? = nil

  @Environment(\.galleryColors) private var colors

  var body: some View {
    Button(action: onClick) {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 4) {
          // Icon
          if let gradient = iconGradient {
            Image(systemName: systemImage)
              .resizable()
              .scaledToFit()
              .frame(width: 40, height: 40)
              .overlay(gradient)
              .mask(
                Image(systemName: systemImage)
                  .resizable()
                  .scaledToFit()
              )
          } else {
            Image(systemName: systemImage)
              .resizable()
              .scaledToFit()
              .frame(width: 40, height: 40)
              .foregroundStyle(colors.onSurface)
          }

          Spacer()

          // Text
          VStack(alignment: .leading, spacing: 4) {
            Text(label)
              .font(AppFont.font(size: 16, weight: .medium))
              .foregroundStyle(colors.onSurface)
              .lineLimit(1)

            Text(description)
              .font(AppTypography.bodySmall)
              .foregroundStyle(colors.onSurfaceVariant)
              .lineLimit(2)
              .minimumScaleFactor(0.7)
          }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      }
    }
    .buttonStyle(.plain)
    .aspectRatio(1, contentMode: .fit)
    .background(colors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 24))
    .overlay(
      RoundedRectangle(cornerRadius: 24)
        .strokeBorder(colors.surfaceContainerHigh, lineWidth: 2)
    )
  }
}
