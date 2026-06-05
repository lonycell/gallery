// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/modelmanager/ModelManager.kt

import SwiftUI

/// Per-task model list screen with a top app bar showing the task name.
/// Navigates up automatically when the last model is removed.
/// Mirrors `ModelManager`.
struct ModelManager: View {
  let task: Task
  @ObservedObject var viewModel: ModelManagerViewModel
  var enableAnimation: Bool = true
  let navigateUp: () -> Void
  let onModelClicked: (Model) -> Void
  var onBenchmarkClicked: (Model) -> Void = { _ in }

  @Environment(\.galleryColors) private var colors

  // Watch model count; navigate up when it drops to zero.
  @State private var prevModelCount: Int = -1

  var body: some View {
    ModelList(
      task: task,
      modelManagerViewModel: viewModel,
      enableAnimation: enableAnimation,
      onModelClicked: onModelClicked,
      onBenchmarkClicked: onBenchmarkClicked
    )
    .navigationTitle(task.label)
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    .toolbar {
      ToolbarItem(placement: .navigationBarLeading) {
        Button(action: navigateUp) {
          Image(systemName: "chevron.left")
        }
      }
    }
    .onReceive(task.$updateTrigger) { _ in
      let count = task.models.count
      if prevModelCount >= 0 && count == 0 {
        navigateUp()
      }
      prevModelCount = count
    }
    .onAppear {
      prevModelCount = task.models.count
    }
  }
}
