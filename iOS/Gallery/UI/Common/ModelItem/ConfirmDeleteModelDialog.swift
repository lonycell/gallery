/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/modelitem/ConfirmDeleteModelDialog.kt

import SwiftUI

/// A confirmation dialog for deleting a downloaded model. Mirrors `ConfirmDeleteModelDialog`.
///
/// Usage: Add an `@State private var showConfirmDelete = false` to the parent view,
/// use `if showConfirmDelete { ConfirmDeleteModelDialog(...) }` and toggle the state.
struct ConfirmDeleteModelDialog: View {
  let model: Model
  let onConfirm: () -> Void
  let onDismiss: () -> Void

  @State private var isPresented: Bool = true

  var body: some View {
    Color.clear
      .alert(Str.confirmDeleteModelDialogTitle, isPresented: $isPresented) {
        Button(Str.ok, role: .destructive) { onConfirm() }
        Button(Str.cancel, role: .cancel) { onDismiss() }
      } message: {
        Text(String(format: Str.confirmDeleteModelDialogContent, model.name))
      }
      .onChange(of: isPresented) { val in
        if !val { onDismiss() }
      }
  }
}
