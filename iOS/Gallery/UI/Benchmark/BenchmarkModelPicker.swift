// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/benchmark/BenchmarkModelPicker.kt

import SwiftUI

/// Chip that opens a bottom sheet to pick a benchmark model.
/// Mirrors `BenchmarkModelPicker`.
struct BenchmarkModelPicker: View {
  let selectedModelName: String
  let modelNames: [String]
  let title: String
  let onSelected: (String) -> Void

  @State private var showSheet = false
  @Environment(\.galleryColors) private var colors

  var body: some View {
    Button(action: { showSheet = true }) {
      HStack(spacing: 4) {
        Text(selectedModelName)
          .font(AppTypography.labelLarge)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(colors.onSecondaryContainer)

        Image(systemName: "chevron.down")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(colors.onSecondaryContainer)
      }
      .padding(.vertical, 4)
      .padding(.leading, 12)
      .padding(.trailing, 8)
      .background(colors.secondaryContainer)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $showSheet) {
      pickerSheet
        .presentationDetents([.medium, .large])
    }
  }

  @ViewBuilder
  private var pickerSheet: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(AppTypography.titleLarge)
        .foregroundStyle(colors.onSurface)
        .padding(16)

      List(modelNames, id: \.self) { name in
        Button(action: {
          onSelected(name)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showSheet = false
          }
        }) {
          HStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(colors.secondary)
              .opacity(name == selectedModelName ? 1 : 0)

            Text(name)
              .font(AppTypography.labelLarge)
              .foregroundStyle(colors.onSurface)

            Spacer()
          }
          .contentShape(Rectangle())
          .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
      }
      .listStyle(.plain)
    }
  }
}
