/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of MainActivity.kt + GalleryApplication.kt + GalleryApp.kt.
//
// `@main GalleryApp` is the SwiftUI App (≈ MainActivity hosting setContent). It
// builds the `AppContainer` (≈ Hilt graph / GalleryApplication.onCreate), applies
// `GalleryTheme`, kicks off the model-allowlist load, and renders the root nav.

import SwiftUI

@main
struct GalleryApp: App {
  @StateObject private var container = AppContainer()

  init() {
    // Keep the screen on during demos (≈ FLAG_KEEP_SCREEN_ON).
    UIApplication.shared.isIdleTimerDisabled = true
  }

  var body: some Scene {
    WindowGroup {
      GalleryTheme {
        GalleryAppView()
          .environmentObject(container)
          .environmentObject(container.modelManagerViewModel)
          .onAppear {
            // MainActivity.onCreate -> modelManagerViewModel.loadModelAllowlist()
            container.modelManagerViewModel.loadModelAllowlist()
            Analytics.log(.buttonClicked, params: ["event": "app_open"])
          }
          .onOpenURL { url in
            // FCM / deep-link handling (MainActivity.onNewIntent).
            container.router.handleDeepLink(url, modelManager: container.modelManagerViewModel)
          }
      }
    }
  }
}

/// Top-level composable representing the main screen. Mirrors `GalleryApp.kt`.
struct GalleryAppView: View {
  @EnvironmentObject private var container: AppContainer
  @EnvironmentObject private var modelManagerViewModel: ModelManagerViewModel

  var body: some View {
    GalleryNavHost(container: container)
      .environmentObject(container.router)
  }
}
