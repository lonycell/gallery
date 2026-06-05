/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Port of customtasks/exampleagent/ExampleAgentScreen.kt
//
// TEMPLATE: a minimal chat UI for the example agent.
// Tool calls happen transparently inside inference — nothing tool-specific here.

import SwiftUI

/// TEMPLATE: minimal chat UI for the ExampleAgent. Mirrors `ExampleAgentScreen`.
struct ExampleAgentScreen: View {
    let task: Task
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel

    @StateObject private var viewModel = ExampleAgentViewModel()
    @State private var input: String = ""

    @Environment(\.galleryColors) private var colors

    var body: some View {
        let modelManagerState = modelManagerViewModel.uiState
        let model = modelManagerState.selectedModel

        VStack(spacing: 0) {
            if !modelManagerState.isModelInitialized(model) {
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(width: 24, height: 24)
                Spacer()
            } else {
                // Message list.
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.uiState.messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.uiState.messages.count) { _ in
                        if let last = viewModel.uiState.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Error text.
                if !viewModel.uiState.error.isEmpty {
                    Text(viewModel.uiState.error)
                        .foregroundColor(colors.error)
                        .font(.caption)
                        .padding(.horizontal)
                }

                Divider()

                // Input row.
                HStack(spacing: 8) {
                    TextField("Ask for the time, a calculation, …", text: $input, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)

                    Button {
                        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        viewModel.send(model: model, input: text)
                        input = ""
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(viewModel.uiState.generating)
                }
                .padding(12)
            }
        }
        .background(colors.surface)
    }
}

/// Message bubble view. Mirrors `MessageBubble` composable.
private struct MessageBubbleView: View {
    let message: ExampleMessage
    @Environment(\.galleryColors) private var colors

    var body: some View {
        HStack {
            if message.fromUser { Spacer(minLength: 48) }

            Text(message.text.isEmpty
                 ? (message.streaming ? "…" : "")
                 : message.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(message.fromUser
                             ? colors.primary
                             : colors.surfaceVariant)
                .foregroundColor(message.fromUser
                                 ? colors.onPrimary
                                 : colors.onSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: UIScreen.main.bounds.width * 0.85,
                       alignment: message.fromUser ? .trailing : .leading)

            if !message.fromUser { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: message.fromUser ? .trailing : .leading)
    }
}
