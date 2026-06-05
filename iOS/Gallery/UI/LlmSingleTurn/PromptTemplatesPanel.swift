/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/llmsingleturn/PromptTemplatesPanel.kt
//
// The top pane of the Prompt Lab screen. Contains:
//  • A scrollable tab row for selecting the active prompt template.
//  • Optional input editors (e.g. tone / style / language selectors).
//  • A multi-line text field for user input.
//  • A "preview prompt" toggle, a copy button, an example-prompt picker, and
//    a send / stop button.

import SwiftUI

private let ICON_BUTTON_SIZE: CGFloat = 42
private let FULL_PROMPT_SWITCH_KEY = "full_prompt"

struct PromptTemplatesPanel: View {
  let model: Model
  @ObservedObject var viewModel: LlmSingleTurnViewModel
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  let onSend: (String) -> Void
  let onStopButtonClicked: (Model) -> Void

  @Environment(\.customColors) private var customColors
  @Environment(\.galleryColors) private var colors

  // Local state
  @State private var selectedTabIndex: Int = 0
  @State private var curTextInput: String = ""
  @State private var showFullPrompt: Bool = false
  @State private var showExampleSheet: Bool = false
  @State private var inputEditorValues: [String: String] = [:]
  @FocusState private var isInputFocused: Bool

  private var uiState: LlmSingleTurnUiState { viewModel.uiState }
  private var selectedTemplate: PromptTemplateType { uiState.selectedPromptTemplateType }
  private var inProgress: Bool { uiState.inProgress }

  private var fullPrompt: String {
    selectedTemplate.genFullPrompt(userInput: curTextInput, inputEditorValues: inputEditorValues)
  }

  private var promptPrefix: String {
    selectedTemplate.genPromptPrefix(inputEditorValues: inputEditorValues)
  }

  var body: some View {
    VStack(spacing: 0) {
      // Tab row — mirrors PrimaryScrollableTabRow.
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 0) {
          ForEach(Array(PromptTemplateType.allCases.enumerated()), id: \.offset) { index, template in
            Button {
              guard !inProgress else { return }
              curTextInput = ""
              showFullPrompt = false
              inputEditorValues = defaultEditorValues(for: PromptTemplateType.allCases[index])
              selectedTabIndex = index
              viewModel.selectPromptTemplate(model: model, promptTemplateType: template)
            } label: {
              VStack(spacing: 4) {
                Text(template.label)
                  .font(AppTypography.bodyMedium)
                  .foregroundStyle(
                    selectedTabIndex == index ? colors.primary : colors.onSurfaceVariant)
                  .opacity(inProgress ? 0.5 : 1)
                  .padding(.horizontal, 16)
                  .padding(.vertical, 10)

                // Underline indicator for selected tab.
                if selectedTabIndex == index {
                  Rectangle()
                    .fill(colors.primary)
                    .frame(height: 2)
                } else {
                  Rectangle().fill(Color.clear).frame(height: 2)
                }
              }
            }
            .buttonStyle(.plain)
          }
        }
      }
      .background(colors.surface)

      Divider()

      // Input editors row (tone / style / language etc.)
      if !selectedTemplate.config.inputEditors.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(selectedTemplate.config.inputEditors, id: \.label) { editor in
              if let singleSelect = editor as? PromptTemplateSingleSelectInputEditor {
                SingleSelectButton(
                  config: singleSelect,
                  onSelected: { option in
                    inputEditorValues[editor.label] = option
                  })
              }
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
        }
        .background(colors.surfaceContainerLow)
      }

      // Text input area with action row overlay.
      ZStack(alignment: .bottom) {
        if showFullPrompt && !curTextInput.isEmpty {
          // Preview mode: show the fully constructed prompt with a gradient prefix.
          ScrollView {
            VStack(alignment: .leading) {
              (Text(promptPrefix)
                .foregroundStyle(
                  LinearGradient(
                    colors: geminiGradientColors,
                    startPoint: .leading,
                    endPoint: .trailing))
              + Text(curTextInput))
              .font(AppTypography.bodyMedium)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(16)
            }
            .padding(.bottom, 48)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          // Input mode: plain text field.
          ScrollView {
            TextField("Enter content", text: $curTextInput, axis: .vertical)
              .font(AppTypography.bodyLarge)
              .focused($isInputFocused)
              .padding(.horizontal, 16)
              .padding(.top, 8)
              .padding(.bottom, 48)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .onTapGesture { isInputFocused = true }
        }

        // Action row (bottom of input area).
        HStack(spacing: 4) {
          // Full-prompt preview toggle.
          if selectedTemplate != .freeForm && !curTextInput.isEmpty {
            Button {
              showFullPrompt.toggle()
            } label: {
              HStack(spacing: 4) {
                Image(systemName: showFullPrompt ? "eye" : "eye.slash")
                  .opacity(showFullPrompt ? 1 : 0.3)
                  .imageScale(.small)
                Text("Preview prompt")
                  .font(AppTypography.labelMedium)
              }
              .padding(.horizontal, 12)
              .frame(height: 40)
              .background(
                showFullPrompt ? colors.secondaryContainer : customColors.agentBubbleBgColor,
                in: Capsule())
              .overlay(Capsule().stroke(colors.surface, lineWidth: 1))
            }
            .buttonStyle(.plain)
          }

          Spacer()

          // Copy-full-prompt button.
          if !curTextInput.isEmpty {
            Button {
              UIPasteboard.general.string = fullPrompt
            } label: {
              Image(systemName: "doc.on.doc")
                .resizable()
                .frame(width: 20, height: 20)
            }
            .frame(width: ICON_BUTTON_SIZE, height: ICON_BUTTON_SIZE)
            .background(customColors.agentBubbleBgColor)
            .clipShape(RoundedRectangle(cornerRadius: ICON_BUTTON_SIZE / 2))
            .overlay(
              RoundedRectangle(cornerRadius: ICON_BUTTON_SIZE / 2)
                .stroke(colors.surface, lineWidth: 1))
          }

          // Example-prompt button.
          Button {
            guard !inProgress else { return }
            showExampleSheet = true
          } label: {
            Image(systemName: "plus")
              .resizable()
              .frame(width: 20, height: 20)
              .opacity(inProgress ? 0.4 : 1)
          }
          .frame(width: ICON_BUTTON_SIZE, height: ICON_BUTTON_SIZE)
          .background(
            inProgress
              ? customColors.agentBubbleBgColor.opacity(0.4)
              : customColors.agentBubbleBgColor)
          .clipShape(RoundedRectangle(cornerRadius: ICON_BUTTON_SIZE / 2))
          .overlay(
            RoundedRectangle(cornerRadius: ICON_BUTTON_SIZE / 2)
              .stroke(colors.surface, lineWidth: 1))
          .disabled(inProgress)

          // Stop / Send button.
          let modelInitializing = modelManagerViewModel.isModelInitializing(model)
          if inProgress && !modelInitializing && !uiState.preparing {
            Button { onStopButtonClicked(model) } label: {
              Image(systemName: "stop.fill")
                .foregroundStyle(colors.primary)
            }
            .frame(width: ICON_BUTTON_SIZE, height: ICON_BUTTON_SIZE)
            .background(colors.secondaryContainer)
            .clipShape(RoundedRectangle(cornerRadius: ICON_BUTTON_SIZE / 2))
          } else {
            let canSend = !inProgress && !curTextInput.isEmpty
            Button {
              isInputFocused = false
              onSend(fullPrompt)
            } label: {
              Image(systemName: "paperplane.fill")
                .resizable()
                .frame(width: 18, height: 18)
                .opacity(canSend ? 1 : 0.1)
            }
            .frame(width: ICON_BUTTON_SIZE, height: ICON_BUTTON_SIZE)
            .background(
              canSend
                ? colors.secondaryContainer
                : colors.secondaryContainer.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: ICON_BUTTON_SIZE / 2))
            .overlay(
              RoundedRectangle(cornerRadius: ICON_BUTTON_SIZE / 2)
                .stroke(colors.surface, lineWidth: 1))
            .disabled(!canSend)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color.clear)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // Reset editor values when the selected template changes externally.
    .onChange(of: selectedTemplate) { _, template in
      inputEditorValues = defaultEditorValues(for: template)
    }
    .onAppear {
      inputEditorValues = defaultEditorValues(for: selectedTemplate)
    }
    // Example prompts bottom sheet.
    .sheet(isPresented: $showExampleSheet) {
      ExamplePromptSheet(
        template: selectedTemplate,
        onSelect: { prompt in
          curTextInput = prompt
          showExampleSheet = false
        })
    }
  }

  private func defaultEditorValues(for template: PromptTemplateType) -> [String: String] {
    var values: [String: String] = [:]
    for editor in template.config.inputEditors {
      values[editor.label] = editor.defaultOption
    }
    return values
  }
}

// MARK: - ExamplePromptSheet

private struct ExamplePromptSheet: View {
  let template: PromptTemplateType
  let onSelect: (String) -> Void

  @State private var expandedPrompts: Set<String> = []

  var body: some View {
    NavigationView {
      List {
        ForEach(template.examplePrompts, id: \.self) { prompt in
          ExamplePromptRow(
            prompt: prompt,
            isExpanded: expandedPrompts.contains(prompt),
            onToggleExpand: {
              if expandedPrompts.contains(prompt) {
                expandedPrompts.remove(prompt)
              } else {
                expandedPrompts.insert(prompt)
              }
            },
            onSelect: { onSelect(prompt) })
        }
      }
      .listStyle(.plain)
      .navigationTitle("Select an example")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

private struct ExamplePromptRow: View {
  let prompt: String
  let isExpanded: Bool
  let onToggleExpand: () -> Void
  let onSelect: () -> Void

  @State private var isTruncated = false

  var body: some View {
    Button(action: onSelect) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "doc.text")
            .foregroundStyle(.secondary)
          Text(prompt)
            .font(AppTypography.bodySmall)
            .lineLimit(isExpanded ? nil : 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              GeometryReader { geo in
                // Measure if text would overflow 3 lines.
                Color.clear.onAppear {
                  // Approximate: if string is long, consider it truncated.
                  isTruncated = prompt.count > 120
                }
              })
        }

        if isTruncated && !isExpanded {
          HStack {
            Spacer()
            Button(action: onToggleExpand) {
              Image(systemName: "chevron.down")
                .imageScale(.small)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
          }
        } else if isExpanded {
          HStack {
            Spacer()
            Button(action: onToggleExpand) {
              Image(systemName: "chevron.up")
                .imageScale(.small)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
          }
        }
      }
      .padding(.vertical, 8)
    }
    .buttonStyle(.plain)
  }
}
