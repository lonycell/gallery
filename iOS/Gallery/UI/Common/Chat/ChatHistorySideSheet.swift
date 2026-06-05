/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/ChatHistorySideSheet.kt

import SwiftUI

struct ChatHistorySideSheetContent: View {
  let history: [ChatSessionProto]
  var onHistoryItemClicked: (String) -> Void = { _ in }
  var onHistoryItemDeleted: (String) -> Void = { _ in }
  var onHistoryItemsDeleteAll: () -> Void = {}
  var onNewChatClicked: () -> Void = {}
  var onDismissed: () -> Void = {}

  @State private var showConfirmDeleteAll = false
  @State private var itemToDelete: String?
  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(spacing: 0) {
      // Top bar
      HStack {
        Text("채팅 기록")
          .font(.title3).fontWeight(.semibold)
        Spacer()
        Button(action: onDismissed) {
          Image(systemName: "xmark")
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 24)
      .padding(.top, 24)
      .padding(.bottom, 12)

      // "+ New chat" button
      HStack {
        Button(action: onNewChatClicked) {
          Label("새 채팅", systemImage: "plus.bubble")
        }
        .buttonStyle(.borderedProminent)
        .tint(colors.primaryContainer)
        .foregroundColor(colors.onPrimaryContainer)
        Spacer()
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 16)

      // Subheading
      HStack {
        Text("채팅 기록")
          .font(.subheadline)
          .foregroundColor(colors.onSurfaceVariant)
        Spacer()
        Button("모두 지우기") {
          showConfirmDeleteAll = true
        }
        .font(.subheadline)
        .foregroundColor(colors.primary)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 8)

      // List
      List {
        ForEach(history) { session in
          HStack(spacing: 8) {
            Text(session.title)
              .font(.body)
              .lineLimit(3)
              .frame(maxWidth: .infinity, alignment: .leading)
            Button {
              itemToDelete = session.sessionId
            } label: {
              Image(systemName: "trash")
                .foregroundColor(colors.onSurfaceVariant)
            }
            .buttonStyle(.plain)
          }
          .padding(.vertical, 12)
          .padding(.horizontal, 16)
          .background(colors.surfaceVariant.opacity(0.5))
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
          .listRowBackground(Color.clear)
          .contentShape(Rectangle())
          .onTapGesture { onHistoryItemClicked(session.sessionId) }
        }
      }
      .listStyle(.plain)

      // Info footer
      HStack(spacing: 8) {
        Image(systemName: "info.circle")
          .frame(width: 16, height: 16)
          .foregroundColor(colors.onSurfaceVariant)
        Text(Str.chatHistoryDemoNotice)
          .font(.caption)
          .foregroundColor(colors.onSurfaceVariant)
        Spacer()
      }
      .padding(16)
    }
    // Confirm delete all
    .alert("기록 지우기", isPresented: $showConfirmDeleteAll) {
      Button("확인", role: .destructive) { onHistoryItemsDeleteAll() }
      Button(Str.cancel, role: .cancel) {}
    } message: {
      Text("모든 채팅 기록을 지우시겠습니까?")
    }
    // Confirm delete single
    .alert("기록 삭제", isPresented: Binding(
      get: { itemToDelete != nil },
      set: { if !$0 { itemToDelete = nil } }
    )) {
      Button("확인", role: .destructive) {
        if let id = itemToDelete { onHistoryItemDeleted(id) }
        itemToDelete = nil
      }
      Button(Str.cancel, role: .cancel) { itemToDelete = nil }
    } message: {
      Text("이 채팅을 삭제하시겠습니까?")
    }
  }
}
