/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/llmsingleturn/SingleSelectButton.kt

import SwiftUI

/// A compact drop-down button that shows `config.label: selectedOption` and lets
/// the user pick a new option from a menu. Mirrors `@Composable fun SingleSelectButton`.
struct SingleSelectButton: View {
  let config: PromptTemplateSingleSelectInputEditor
  let onSelected: (String) -> Void

  @State private var selectedOption: String

  init(config: PromptTemplateSingleSelectInputEditor, onSelected: @escaping (String) -> Void) {
    self.config = config
    self.onSelected = onSelected
    self._selectedOption = State(initialValue: config.defaultOption)
  }

  @Environment(\.galleryColors) private var colors

  var body: some View {
    Menu {
      ForEach(config.options, id: \.self) { option in
        Button(option) {
          selectedOption = option
          onSelected(option)
        }
      }
    } label: {
      HStack(spacing: 2) {
        Text("\(config.label): \(selectedOption)")
          .font(AppTypography.labelLarge)
        Image(systemName: "chevron.down")
          .imageScale(.small)
      }
      .padding(.vertical, 4)
      .padding(.leading, 14)
      .padding(.trailing, 8)
      .background(colors.secondaryContainer, in: RoundedRectangle(cornerRadius: 8))
    }
    .onChange(of: config.defaultOption) { _, newDefault in
      selectedOption = newDefault
    }
  }
}
