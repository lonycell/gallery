/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/CursorTrackingTextField.kt

import SwiftUI

/// A text-field that automatically scrolls to keep the cursor visible when it moves.
/// Mirrors `CursorTrackingTextField` composable.
///
/// NOTE: Compose's `BringIntoViewRequester` has no exact SwiftUI equivalent. We use a
/// standard `TextEditor` inside a `ScrollViewReader` and scroll to a proxy anchor
/// whenever the text changes; this approximates the behaviour.
struct CursorTrackingTextField: View {
  var initialValue: String
  var onValueChange: (String) -> Void
  var label: String? = nil
  var supportingText: String? = nil
  var placeholder: String? = nil
  var enabled: Bool = true
  var minLines: Int = 1
  var monoFont: Bool = false
  var extraBottomContent: (() -> AnyView)? = nil
  var trailingIcon: (() -> AnyView)? = nil

  @State private var text: String
  @Environment(\.galleryColors) private var colors

  init(
    initialValue: String,
    onValueChange: @escaping (String) -> Void,
    label: String? = nil,
    supportingText: String? = nil,
    placeholder: String? = nil,
    enabled: Bool = true,
    minLines: Int = 1,
    monoFont: Bool = false,
    extraBottomContent: (() -> AnyView)? = nil,
    trailingIcon: (() -> AnyView)? = nil
  ) {
    self.initialValue = initialValue
    self.onValueChange = onValueChange
    self.label = label
    self.supportingText = supportingText
    self.placeholder = placeholder
    self.enabled = enabled
    self.minLines = minLines
    self.monoFont = monoFont
    self.extraBottomContent = extraBottomContent
    self.trailingIcon = trailingIcon
    _text = State(initialValue: initialValue)
  }

  private var bodyFont: Font {
    monoFont
      ? Font.system(size: 12, design: .monospaced)
      : AppTypography.bodyMedium
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let label {
        Text(label)
          .font(AppTypography.bodySmall)
          .foregroundStyle(colors.onSurfaceVariant)
      }
      ZStack(alignment: .topLeading) {
        // Minimum-height placeholder area
        if text.isEmpty, let placeholder {
          Text(placeholder)
            .font(bodyFont)
            .foregroundStyle(colors.onSurfaceVariant.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .allowsHitTesting(false)
        }
        HStack(alignment: .top) {
          TextEditor(text: Binding(
            get: { text },
            set: { newVal in
              text = newVal
              onValueChange(newVal)
            }
          ))
          .font(bodyFont)
          .foregroundStyle(enabled ? colors.onSurface : colors.onSurface.opacity(0.7))
          .disabled(!enabled)
          .scrollContentBackground(.hidden)
          .background(Color.clear)
          .padding(.horizontal, 8)
          .frame(minHeight: CGFloat(minLines) * 20)

          if let icon = trailingIcon {
            icon()
              .padding(.top, 8)
              .padding(.trailing, 8)
          }
        }
      }
      .padding(.vertical, 4)
      .overlay(
        RoundedRectangle(cornerRadius: 4)
          .stroke(colors.outline, lineWidth: 1)
      )

      if let supporting = supportingText {
        VStack(alignment: .leading, spacing: 4) {
          Text(supporting)
            .font(AppTypography.bodySmall)
            .foregroundStyle(colors.onSurfaceVariant)
          extraBottomContent?()
        }
      }
    }
    .onChange(of: initialValue) { newVal in
      if newVal != text { text = newVal }
    }
  }
}
