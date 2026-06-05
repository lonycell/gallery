/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/llmsingleturn/ResponsePanel.kt
//
// The bottom pane of the Prompt Lab screen. Shows a streaming markdown
// response for the selected model + prompt template, with copy and
// scroll-to-bottom affordances.

import SwiftUI

private let TAG = "AGResponsePanel"

struct ResponsePanel: View {
  let task: Task
  let model: Model
  @ObservedObject var viewModel: LlmSingleTurnViewModel
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel

  @Environment(\.customColors) private var customColors
  @Environment(\.galleryColors) private var colors

  @State private var isAtBottom = true

  private var uiState: LlmSingleTurnUiState { viewModel.uiState }

  var body: some View {
    let selectedTemplate = uiState.selectedPromptTemplateType
    let response = uiState.responsesByModel[model.name]?[selectedTemplate.label] ?? ""
    let initializing = uiState.preparing

    ZStack(alignment: .bottomLeading) {
      Group {
        if initializing {
          // Loading indicator while the model is preparing its first token.
          HStack {
            MessageBodyLoading()
              .padding(.horizontal, 16)
              .padding(.top, 8)
            Spacer()
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if response.isEmpty {
          // Placeholder when no response yet.
          HStack {
            Spacer()
            Text("Response will appear here")
              .font(AppTypography.labelMedium)
              .opacity(0.5)
            Spacer()
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          // Streaming markdown response.
          ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
              ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                  BufferedFadingMarkdownText(
                    text: response,
                    inProgress: uiState.inProgress)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                    .accessibilityAddTraits(.updatesFrequently)
                  // Anchor at the bottom for auto-scroll.
                  Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Track scroll position via a geometry reader inside the scroll content.
                .background(
                  GeometryReader { geo in
                    Color.clear.preference(
                      key: ScrollAtBottomKey.self,
                      value: geo.frame(in: .named("responseScroll")).maxY)
                  })
              }
              .coordinateSpace(name: "responseScroll")
              .onPreferenceChange(ScrollAtBottomKey.self) { maxY in
                // Approximate: if content bottom is near or past viewport edge.
                withAnimation { isAtBottom = maxY <= 20 }
              }
              .onChange(of: response) { _, _ in
                if isAtBottom {
                  withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
              }
            }

            // Copy button (bottom-right overlay).
            Button {
              UIPasteboard.general.string = response
            } label: {
              Image(systemName: "doc.on.doc")
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(colors.primary)
            }
            .frame(width: 44, height: 44)
            .background(colors.surfaceContainerHighest)
            .clipShape(Circle())
            .padding(4)
          }
        }
      }

      // Scroll-to-bottom button (bottom-center overlay), only in non-empty state.
      if !response.isEmpty && !initializing {
        VStack {
          Spacer()
          HStack {
            Spacer()
            ScrollToBottomButton(isAtBottom: isAtBottom) {
              // Trigger scroll via the onChange(of: response) path by bumping state.
              isAtBottom = false
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isAtBottom = true }
            }
            Spacer()
          }
          .padding(.bottom, 4)
        }
      }
    }
    .background(customColors.agentBubbleBgColor)
  }
}

// MARK: - Scroll-at-bottom preference key

private struct ScrollAtBottomKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
