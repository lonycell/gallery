/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/ModelPicker.kt

import SwiftUI

/// Displays a list of models for a task so the user can select one.
/// Mirrors `ModelPicker` composable.
struct ModelPicker: View {
  let task: Task
  let modelManagerViewModel: ModelManagerViewModel
  let onModelSelected: (Model) -> Void

  @State private var showMemoryWarning: Bool = false
  @State private var modelToPick: Model? = nil

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Title row
      HStack(spacing: 8) {
        TaskIconImage(task: task, size: 16)
          .foregroundStyle(getTaskIconColor(task: task, customColors: customColors))
        Text("\(task.label) models")
          .font(AppTypography.titleMedium)
          .foregroundStyle(getTaskIconColor(task: task, customColors: customColors))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)

      // Model list
      ForEach(task.models, id: \.name) { model in
        let selected = model.name == modelManagerViewModel.uiState.selectedModel.name
        Button {
          if isMemoryLow(model: model) {
            modelToPick = model
            showMemoryWarning = true
          } else {
            onModelSelected(model)
          }
        } label: {
          HStack(spacing: 8) {
            Spacer().frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
              Text(model.displayName.isEmpty ? model.name : model.displayName)
                .font(AppTypography.bodyMedium)
                .foregroundStyle(colors.onSurface)
              if model.runtimeType != .aicore {
                HStack(spacing: 4) {
                  StatusIcon(
                    task: task,
                    model: model,
                    downloadStatus: modelManagerViewModel.uiState.modelDownloadStatus[model.name]
                  )
                  let sizeLabel: String = model.localFileRelativeDirPathOverride.isEmpty
                    ? model.sizeInBytes.humanReadableSize()
                    : "{ext_file_dir}/\(model.localFileRelativeDirPathOverride)"
                  Text(sizeLabel)
                    .font(AppTypography.labelSmall)
                    .foregroundStyle(colors.onSurfaceVariant)
                    .lineSpacing(-2)
                }
              }
            }
            Spacer()
            if selected {
              Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 16, height: 16)
                .foregroundStyle(colors.primary)
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(selected ? colors.surfaceContainer : Color.clear)
        }
      }
    }
    .padding(.bottom, 8)
    .alert(Str.memoryWarningTitle, isPresented: $showMemoryWarning) {
      Button(Str.cancel, role: .cancel) { showMemoryWarning = false }
      Button(Str.memoryWarningProceedAnyway) {
        if let m = modelToPick { onModelSelected(m) }
        showMemoryWarning = false
      }
    } message: {
      Text(Str.memoryWarningContent)
    }
  }
}
