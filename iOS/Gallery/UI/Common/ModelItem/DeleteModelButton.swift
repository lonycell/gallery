/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/modelitem/DeleteModelButton.kt

import SwiftUI

/// A button that triggers a confirmation dialog to delete a downloaded model.
/// Mirrors `DeleteModelButton` composable.
struct DeleteModelButton: View {
  let model: Model
  let modelManagerViewModel: ModelManagerViewModel
  let downloadStatus: ModelDownloadStatus?
  var showDeleteButton: Bool = true

  @State private var showConfirmDialog: Bool = false

  @Environment(\.galleryColors) private var colors

  var body: some View {
    HStack {
      if downloadStatus?.status == .succeeded && showDeleteButton {
        Button {
          showConfirmDialog = true
        } label: {
          Image(systemName: "trash")
            .imageScale(.medium)
            .foregroundStyle(colors.onSurfaceVariant.opacity(0.6))
        }
        .buttonStyle(.plain)
      }
    }
    .overlay {
      if showConfirmDialog {
        ConfirmDeleteModelDialog(
          model: model,
          onConfirm: {
            modelManagerViewModel.deleteModel(model)
            showConfirmDialog = false
          },
          onDismiss: { showConfirmDialog = false }
        )
      }
    }
  }
}
