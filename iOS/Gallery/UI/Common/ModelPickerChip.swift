/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/ModelPickerChip.kt

import SwiftUI

/// A compact chip that shows the current model name and opens a ModelPicker sheet.
/// Mirrors `ModelPickerChip` composable.
struct ModelPickerChip: View {
  let enabled: Bool
  let task: Task
  let initialModel: Model
  let modelManagerViewModel: ModelManagerViewModel
  let onModelSelected: (_ prev: Model, _ cur: Model) -> Void

  @State private var showModelPicker: Bool = false

  @Environment(\.galleryColors) private var colors

  private var modelInitStatus: ModelInitializationStatus? {
    modelManagerViewModel.uiState.modelInitializationStatus[initialModel.name]
  }

  private var isInitializing: Bool {
    modelInitStatus?.status == .initializing
  }

  var body: some View {
    HStack(spacing: 2) {
      let modelName = initialModel.displayName.isEmpty ? initialModel.name : initialModel.displayName
      Button {
        guard enabled else { return }
        showModelPicker = true
      } label: {
        HStack(spacing: 4) {
          // Status icon + optional initializing spinner
          ZStack {
            StatusIcon(
              task: task,
              model: initialModel,
              downloadStatus: modelManagerViewModel.uiState.modelDownloadStatus[initialModel.name]
            )
            .frame(width: 21, height: 21)
            if isInitializing {
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: colors.onSurfaceVariant))
                .scaleEffect(0.7)
                .opacity(0.5)
            }
          }
          .frame(width: 21, height: 21)

          Text(modelName)
            .font(AppTypography.labelLarge)
            .foregroundStyle(colors.onSurface)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: UIScreen.main.bounds.width - 250)

          Image(systemName: "chevron.down")
            .resizable()
            .frame(width: 12, height: 8)
            .foregroundStyle(colors.onSurface)
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(colors.surfaceContainerHigh, in: Capsule())
        .opacity(enabled ? 1.0 : 0.6)
      }
      .disabled(!enabled)
      .accessibilityLabel(modelName)
    }
    .sheet(isPresented: $showModelPicker) {
      ModelPicker(
        task: task,
        modelManagerViewModel: modelManagerViewModel,
        onModelSelected: { selectedModel in
          showModelPicker = false
          let prev = modelManagerViewModel.uiState.selectedModel
          onModelSelected(prev, selectedModel)
        }
      )
      .presentationDetents([.medium, .large])
    }
  }
}
