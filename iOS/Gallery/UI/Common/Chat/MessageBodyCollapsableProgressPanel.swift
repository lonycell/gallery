/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyCollapsableProgressPanel.kt

import SwiftUI

struct MessageBodyCollapsableProgressPanel: View {
  let message: ChatMessageCollapsableProgressPanel

  @State private var isExpanded = false
  @State private var showLogsViewer = false
  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(spacing: 0) {
      // Header row (always visible)
      HStack(spacing: 12) {
        // Leading spinner or done icon
        ZStack {
          if message.inProgress {
            ProgressView()
              .progressViewStyle(.circular)
              .scaleEffect(0.7)
              .frame(width: 24, height: 24)
          } else {
            Image(systemName: message.doneIcon)
              .frame(width: 24, height: 24)
          }
        }

        // Animated title
        Text(message.title)
          .font(.subheadline).fontWeight(.semibold)
          .frame(maxWidth: .infinity, alignment: .leading)
          .id(message.title) // triggers transition on title change

        // Expand/collapse chevron
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
          .foregroundColor(colors.onSurface)
      }
      .padding(16)
      .contentShape(Rectangle())
      .onTapGesture { withAnimation { isExpanded.toggle() } }

      // Collapsable content
      if isExpanded {
        VStack(spacing: 12) {
          ForEach(message.items.indices, id: \.self) { i in
            let item = message.items[i]
            HStack(alignment: .top, spacing: 12) {
              Circle()
                .fill(colors.secondaryContainer)
                .frame(width: 12, height: 12)
                .padding(.top, 2)
              VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                  .font(.caption).fontWeight(.semibold)
                if !item.description.isEmpty {
                  Text(item.description)
                    .font(.caption2)
                    .foregroundColor(colors.onSurfaceVariant)
                    .lineLimit(5)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(colors.surfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: 12))
          }

          if !message.logMessages.isEmpty {
            HStack {
              Spacer()
              Button {
                showLogsViewer = true
              } label: {
                Label("로그 보기", systemImage: "doc.text")
                  .font(.caption)
              }
              .buttonStyle(.borderedProminent)
              .buttonBorderShape(.capsule)
              .controlSize(.small)
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, message.logMessages.isEmpty ? 12 : 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .background(colors.surfaceContainerHigh)
    .frame(maxWidth: .infinity)
    .sheet(isPresented: $showLogsViewer) {
      LogsViewer(logs: message.logMessages, onDismissRequest: { showLogsViewer = false })
    }
  }
}
