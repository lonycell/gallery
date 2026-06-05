/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/TextInputHistorySheet.kt

import SwiftUI

struct TextInputHistorySheet: View {
  let history: [String]
  var onHistoryItemClicked: (String) -> Void = { _ in }
  var onHistoryItemDeleted: (String) -> Void = { _ in }
  var onHistoryItemsDeleteAll: () -> Void = {}
  var onDismissed: () -> Void = {}

  @State private var showConfirmDelete = false
  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  var body: some View {
    NavigationView {
      List {
        ForEach(history, id: \.self) { item in
          HStack(spacing: 8) {
            Text(item)
              .font(.body)
              .lineLimit(3)
              .frame(maxWidth: .infinity, alignment: .leading)
            Button {
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onHistoryItemDeleted(item)
              }
            } label: {
              Image(systemName: "trash").foregroundColor(colors.onSurfaceVariant)
            }
            .buttonStyle(.plain)
          }
          .padding(.vertical, 16)
          .padding(.horizontal, 16)
          .background(customColors.agentBubbleBgColor)
          .clipShape(RoundedRectangle(cornerRadius: 24))
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
          .listRowBackground(Color.clear)
          .contentShape(Rectangle())
          .onTapGesture {
            onHistoryItemClicked(item)
            onDismissed()
          }
        }
      }
      .listStyle(.plain)
      .navigationTitle("텍스트 입력 기록")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(Str.close) { onDismissed() }
        }
        ToolbarItem(placement: .destructiveAction) {
          Button {
            showConfirmDelete = true
          } label: {
            Image(systemName: "trash.fill")
          }
        }
      }
    }
    .alert("기록 지우기", isPresented: $showConfirmDelete) {
      Button("확인", role: .destructive) {
        onHistoryItemsDeleteAll()
        onDismissed()
      }
      Button(Str.cancel, role: .cancel) {}
    } message: {
      Text("입력 기록을 모두 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.")
    }
  }
}
