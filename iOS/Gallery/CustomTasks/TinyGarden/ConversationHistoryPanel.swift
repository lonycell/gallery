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

// Port of customtasks/tinygarden/ConversationHistoryPanel.kt

import SwiftUI

/// A panel that shows the TinyGarden conversation history.
/// Mirrors `ConversationHistoryPanel` composable.
struct ConversationHistoryPanel: View {
    let task: Task
    var bottomPadding: CGFloat = 0
    @ObservedObject var viewModel: TinyGardenViewModel
    let onDismiss: () -> Void

    @Environment(\.galleryColors) private var colors
    @Environment(\.customColors) private var customColors

    var body: some View {
        VStack(spacing: 0) {
            // Title and dismiss button.
            HStack {
                Text(Str.conversationHistory)
                    .font(AppTypography.titleMedium)
                    .padding(.leading, 12)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(colors.onSurface)
                }
                .padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(colors.surfaceContainerHighest)

            // Message list — scrollable, auto-scrolls to bottom on new messages.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.uiState.messages) { message in
                            messageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onChange(of: viewModel.uiState.messages.count) { _ in
                    if let last = viewModel.uiState.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(colors.surface)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func messageBubble(message: TinyGardenMessage) -> some View {
        let isUser   = message.side == .user
        let isSystem = message.side == .system
        let isAgent  = message.side == .agent

        let bubbleBg: Color = isUser
            ? customColors.userBubbleBgColor
            : customColors.agentBubbleBgColor
        let hAlign: HorizontalAlignment = isUser ? .trailing : .leading
        let paddingStart: CGFloat = isUser ? 48 : (isSystem ? 24 : 0)
        let paddingEnd:   CGFloat = isAgent ? 48 : (isSystem ? 24 : 0)

        VStack(alignment: hAlign, spacing: 2) {
            // Sender label (mirrors MessageSender).
            if !isSystem {
                Text(isUser ? Str.chatYou : task.agentName)
                    .font(AppTypography.labelSmall)
                    .foregroundColor(colors.onSurfaceVariant)
            }

            if message.isWarning {
                Text(message.content)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(customColors.warningTextColor)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            } else {
                Text(message.content)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(isUser ? colors.onPrimary : colors.onSurface)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            }
        }
        .padding(.leading, paddingStart)
        .padding(.trailing, paddingEnd)
        .padding(.vertical, 6)
    }
}
