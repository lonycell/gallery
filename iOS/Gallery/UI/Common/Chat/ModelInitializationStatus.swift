/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/ModelInitializationStatus.kt

import SwiftUI

/// A pill-shaped chip indicating the model is currently initializing.
struct ModelInitializationStatusChip: View {
  @Environment(\.galleryColors) private var colors

  var body: some View {
    HStack {
      Spacer()
      HStack(spacing: 8) {
        ProgressView()
          .progressViewStyle(.circular)
          .scaleEffect(0.7)
          .frame(width: 14, height: 14)
        Text(Str.modelIsInitializingMsg)
          .font(.caption)
          .foregroundColor(colors.onSecondaryContainer)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(colors.secondaryContainer)
      .clipShape(Capsule())
      .padding(8)
      Spacer()
    }
  }
}
