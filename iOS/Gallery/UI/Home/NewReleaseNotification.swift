// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/home/NewReleaseNotification.kt

import SwiftUI

private let REPO = "google-ai-edge/gallery"

/// Checks for a newer GitHub release on app-resume and shows a banner when one is available.
/// Mirrors `NewReleaseNotification`.
struct NewReleaseNotification: View {
  @State private var newReleaseVersion = ""
  @State private var newReleaseUrl = ""
  @Environment(\.galleryColors) private var colors
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    if !newReleaseVersion.isEmpty {
      HStack(spacing: 0) {
        Text("New release \(newReleaseVersion) available")
          .font(AppTypography.bodyMedium)
          .foregroundStyle(colors.onSurface)
          .padding(.leading, 12)

        Spacer()

        ClickableLink(
          url: newReleaseUrl,
          linkText: "View",
          icon: "arrow.up.right.square"
        )
        .padding(.trailing, 12)
      }
      .padding(.vertical, 4)
      .background(colors.tertiaryContainer)
      .clipShape(Capsule())
      .padding(.horizontal, 16)
      .padding(.bottom, 12)
      .transition(.asymmetric(insertion: .opacity.combined(with: .push(from: .top)),
                              removal: .opacity))
    }
  }
}

// MARK: - Version comparison

private func isNewerRelease(currentRelease: String, newRelease: String) -> Bool {
  let currentComponents = currentRelease.split(separator: ".").map { Int($0) ?? 0 }
  let newComponents = newRelease.split(separator: ".").map { Int($0) ?? 0 }
  let maxComponents = max(currentComponents.count, newComponents.count)
  for i in 0..<maxComponents {
    let cur = i < currentComponents.count ? currentComponents[i] : 0
    let new = i < newComponents.count ? newComponents[i] : 0
    if new > cur { return true }
    if new < cur { return false }
  }
  return false
}
