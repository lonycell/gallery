/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/textandvoiceinput/TextAndVoiceInput.kt

import SwiftUI

/// Combined text + voice input bar. Mirrors `TextAndVoiceInput` composable.
struct TextAndVoiceInput: View {
  let task: Task
  let processing: Bool
  let holdToDictateViewModel: HoldToDictateViewModel
  let onDone: (String) -> Void
  let onAmplitudeChanged: (Int) -> Void
  var clearTextTrigger: Int64 = 0
  var defaultTextInputMode: Bool = false

  @State private var textInputMode: Bool
  @State private var curTextInput: String = ""

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  init(task: Task,
       processing: Bool,
       holdToDictateViewModel: HoldToDictateViewModel,
       onDone: @escaping (String) -> Void,
       onAmplitudeChanged: @escaping (Int) -> Void,
       clearTextTrigger: Int64 = 0,
       defaultTextInputMode: Bool = false) {
    self.task = task
    self.processing = processing
    self.holdToDictateViewModel = holdToDictateViewModel
    self.onDone = onDone
    self.onAmplitudeChanged = onAmplitudeChanged
    self.clearTextTrigger = clearTextTrigger
    self.defaultTextInputMode = defaultTextInputMode
    _textInputMode = State(initialValue: defaultTextInputMode)
  }

  private var sendButtonColor: Color {
    getTaskBgGradientColors(task: task, customColors: customColors)[1]
  }

  var body: some View {
    HStack(spacing: 8) {
      // Mode toggle button (text ↔ voice)
      Button {
        guard !processing else { return }
        curTextInput = ""
        textInputMode.toggle()
      } label: {
        ZStack {
          Circle()
            .fill(colors.surfaceContainerLow)
            .overlay(Circle().stroke(colors.outlineVariant, lineWidth: 1))
            .frame(width: 48, height: 48)
          Image(systemName: textInputMode ? "mic" : "keyboard")
            .imageScale(.medium)
            .foregroundStyle(colors.onSurface)
        }
      }
      .opacity(processing ? 0.5 : 1)
      .disabled(processing)

      if textInputMode {
        // Text input field
        HStack(alignment: .center, spacing: 4) {
          ZStack(alignment: .leading) {
            if curTextInput.isEmpty {
              Text(Str.textInputPlaceholderLlmChat)
                .font(AppTypography.bodyLarge)
                .foregroundStyle(colors.onSurfaceVariant)
                .padding(.leading, 16)
                .padding(.vertical, 8)
            }
            TextEditor(text: $curTextInput)
              .font(AppTypography.bodyLarge)
              .foregroundStyle(colors.onSurface)
              .scrollContentBackground(.hidden)
              .background(Color.clear)
              .disabled(processing)
              .padding(.leading, 12)
              .padding(.trailing, 4)
              .padding(.vertical, 4)
              .frame(minHeight: 36, maxHeight: 80)
          }

          // Send button
          Button {
            guard !processing else { return }
            onDone(curTextInput)
          } label: {
            ZStack {
              Circle()
                .fill(sendButtonColor)
                .frame(width: 36, height: 36)
              Image(systemName: "arrow.right")
                .imageScale(.small)
                .foregroundStyle(.white)
                .offset(x: 1)
            }
          }
          .opacity(processing ? 0.5 : 1)
          .disabled(processing)
          .padding(.trailing, 6)
        }
        .background(colors.surface)
        .overlay(
          RoundedRectangle(cornerRadius: 28)
            .stroke(colors.outlineVariant, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .frame(maxWidth: .infinity, minHeight: 48)
      } else {
        // Hold to talk
        HoldToDictate(
          task: task,
          viewModel: holdToDictateViewModel,
          onDone: onDone,
          onAmplitudeChanged: onAmplitudeChanged,
          enabled: !processing
        )
        .frame(maxWidth: .infinity)
      }
    }
    .onChange(of: clearTextTrigger) { _ in curTextInput = "" }
  }
}
