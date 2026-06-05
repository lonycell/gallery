/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/ErrorDialog.kt

import SwiftUI

/// Simple error dialog with a close button. Mirrors `ErrorDialog`.
struct ErrorDialog: View {
  let error: String
  let onDismiss: () -> Void

  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("오류")
        .font(AppTypography.titleLarge)
        .padding(.bottom, 8)

      Text(error)
        .font(AppTypography.bodySmall)
        .foregroundStyle(colors.error)

      HStack {
        Spacer()
        Button("닫기", action: onDismiss)
          .buttonStyle(.borderedProminent)
      }
    }
    .padding(20)
    .background(colors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }
}

/// Convenience modifier to present `ErrorDialog` as a sheet/overlay.
extension View {
  func errorDialog(
    error: String?,
    onDismiss: @escaping () -> Void
  ) -> some View {
    self.overlay {
      if let error = error {
        Color.black.opacity(0.4)
          .ignoresSafeArea()
          .overlay {
            ErrorDialog(error: error, onDismiss: onDismiss)
              .padding(24)
          }
      }
    }
  }
}
