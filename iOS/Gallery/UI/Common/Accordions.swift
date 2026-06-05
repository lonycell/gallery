/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/Accordions.kt

import SwiftUI

/// Expand/collapse container with a header row. Mirrors `Accordions` composable.
struct Accordions<Content: View>: View {
  let title: String
  let expanded: Bool
  let onExpandedChange: (Bool) -> Void
  var subtitle: String = ""
  var boldTitle: Bool = false
  var bgColor: Color? = nil
  var titleRowAction: AnyView = AnyView(EmptyView())
  var hideTitleRowActionOnCollapse: Bool = false
  @ViewBuilder let content: () -> Content

  @Environment(\.galleryColors) private var colors

  private var resolvedBg: Color { bgColor ?? colors.surface }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Title row
      HStack(spacing: 6) {
        Image(systemName: expanded ? "chevron.down" : "chevron.right")
          .foregroundStyle(colors.onSurface)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(boldTitle ? AppFont.font(size: 14, weight: .semibold) : AppTypography.bodyMedium)
            .foregroundStyle(colors.onSurface)
            .lineLimit(1)
            .truncationMode(.middle)

          if !subtitle.isEmpty {
            Text(subtitle)
              .font(AppTypography.bodySmall)
              .foregroundStyle(colors.onSurfaceVariant)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if !hideTitleRowActionOnCollapse || expanded {
          titleRowAction
        }
      }
      .padding(8)
      .contentShape(Rectangle())
      .onTapGesture { onExpandedChange(!expanded) }

      // Content
      if expanded {
        content()
          .padding(.leading, 4)
          .padding(.top, 8)
          .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .move(edge: .top))
          ))
      }
    }
    .background(resolvedBg)
    .padding(8)
    .animation(.easeInOut(duration: 0.2), value: expanded)
  }
}
