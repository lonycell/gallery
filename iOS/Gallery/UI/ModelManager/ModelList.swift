// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/modelmanager/ModelList.kt

import SwiftUI

private let CONTENT_ANIMATION_OFFSET: CGFloat = 16
private let ANIMATION_INIT_DELAY_MS = 80.0
private let TASK_DESCRIPTION_SECTION_ANIMATION_START_MS = 400.0
private let MODEL_LIST_ANIMATION_START_MS = TASK_DESCRIPTION_SECTION_ANIMATION_START_MS + 150
private let DEFAULT_ANIMATION_DURATION_MS = 700.0
private let TASK_ICON_ANIMATION_DURATION_MS = 1100.0

/// Per-task model list with animated header showing icon, task name, docs and model rows.
/// Mirrors `ModelList`.
struct ModelList: View {
  let task: Task
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  var enableAnimation: Bool
  let onModelClicked: (Model) -> Void
  let onBenchmarkClicked: (Model) -> Void

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  // Derived from task.updateTrigger
  @State private var models: [Model] = []
  @State private var importedModels: [Model] = []
  @State private var modelVariants: [String: [Model]] = [:]
  @State private var expandedStates: [String: Bool] = [:]

  // Animation progress values
  @State private var taskIconProgress: CGFloat = 0
  @State private var taskLabelProgress: CGFloat = 0
  @State private var descriptionProgress: CGFloat = 0
  @State private var modelListProgress: CGFloat = 0

  private var taskBgColor: Color {
    getTaskBgColor(task: task, customColors: customColors)
  }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      ScrollView {
        LazyVStack(spacing: 8) {
          // Task header
          VStack(spacing: 8) {
            Spacer().frame(height: 32)

            VStack(spacing: 8) {
              // Icon
              TaskIcon(task: task, width: 64, animationProgress: Float(taskIconProgress))

              // Task name
              ZStack {
                RevealingText(
                  text: task.label,
                  style: AppFont.font(size: 32, weight: .medium),
                  animationProgress: taskIconProgress,
                  textAlign: .center
                )
                .foregroundStyle(
                  LinearGradient(
                    colors: getTaskBgGradientColors(task: task, customColors: customColors),
                    startPoint: .leading,
                    endPoint: .trailing
                  )
                )

                RevealingText(
                  text: task.label,
                  style: AppFont.font(size: 32, weight: .medium),
                  animationProgress: taskLabelProgress,
                  textAlign: .center
                )
                .foregroundStyle(colors.onSurface)
              }
              .accessibilityLabel(task.label)

              // Experimental pill
              if task.experimental {
                Text(Str.modelListExperimentalLabel)
                  .font(AppFont.font(size: 16, weight: .bold))
                  .padding(.horizontal, 12)
                  .padding(.vertical, 4)
                  .background(colors.secondaryContainer)
                  .clipShape(Capsule())
                  .opacity(descriptionProgress)
                  .offset(y: CONTENT_ANIMATION_OFFSET * (1 - descriptionProgress))
              }

              // Description
              Text(task.description)
                .font(AppTypography.bodyLargeNarrow)
                .multilineTextAlignment(.center)
                .foregroundStyle(colors.onSurface)
                .opacity(descriptionProgress)
                .offset(y: CONTENT_ANIMATION_OFFSET * (1 - descriptionProgress))

              // Docs / source code links
              if !task.docUrl.isEmpty || !task.sourceCodeUrl.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                  if !task.docUrl.isEmpty {
                    ClickableLink(url: task.docUrl, linkText: "API Documentation",
                                  icon: "doc.text")
                  }
                  if !task.sourceCodeUrl.isEmpty {
                    ClickableLink(url: task.sourceCodeUrl, linkText: "Example code",
                                  icon: "chevron.left.forwardslash.chevron.right")
                  }
                }
                .padding(.vertical, 8)
                .opacity(descriptionProgress)
                .offset(y: CONTENT_ANIMATION_OFFSET * (1 - descriptionProgress))
              }

              // Model count
              let total = models.count + importedModels.count
              Text(Str.modelListNumberOfModelsAvailable(total))
                .font(AppTypography.bodyMedium)
                .foregroundStyle(colors.onSurface.opacity(0.6))
                .opacity(descriptionProgress * 0.6)
                .offset(y: CONTENT_ANIMATION_OFFSET * (1 - descriptionProgress))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
          }

          // Recommended models title
          if !models.isEmpty {
            Text(Str.modelListRecommendedModelsTitle)
              .font(AppTypography.labelLarge)
              .foregroundStyle(colors.onSurface)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .opacity(modelListProgress)
              .offset(y: CONTENT_ANIMATION_OFFSET * (1 - modelListProgress))
          }

          // Built-in models
          ForEach(models.filter { $0.parentModelName == nil || $0.parentModelName!.isEmpty }, id: \.name) { model in
            let expanded = expandedStates[model.name]
            // NOTE: ModelItem is owned by the common/modelitem agent — reference by name.
            ModelItem(
              model: model,
              task: task,
              modelManagerViewModel: modelManagerViewModel,
              onModelClicked: onModelClicked,
              onBenchmarkClicked: onBenchmarkClicked,
              expanded: expanded,
              showBenchmarkButton: true,
              onExpanded: { expandedStates[model.name] = $0 },
              modelVariants: modelVariants[model.name] ?? []
            )
            .opacity(modelListProgress)
            .offset(y: CONTENT_ANIMATION_OFFSET * (1 - modelListProgress))
          }

          // Imported models section
          if !importedModels.isEmpty {
            Text(Str.modelListImportedModelsTitle)
              .font(AppTypography.labelLarge)
              .foregroundStyle(colors.onSurface)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 16)
              .padding(.top, 32)
              .padding(.bottom, 8)
              .opacity(modelListProgress)
              .offset(y: CONTENT_ANIMATION_OFFSET * (1 - modelListProgress))

            ForEach(importedModels, id: \.name) { model in
              ModelItem(
                model: model,
                task: task,
                modelManagerViewModel: modelManagerViewModel,
                onModelClicked: onModelClicked,
                onBenchmarkClicked: onBenchmarkClicked,
                expanded: true,
                showBenchmarkButton: true
              )
              .opacity(modelListProgress)
              .offset(y: CONTENT_ANIMATION_OFFSET * (1 - modelListProgress))
            }
          }

          Spacer().frame(height: 80)
        }
        .padding(.horizontal, 16)
      }
      .background(taskBgColor)

      // Bottom gradient overlay
      LinearGradient(
        colors: [.clear, colors.surfaceContainer],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: 40)
      .allowsHitTesting(false)
    }
    .onAppear {
      rebuildModels()
      startAnimations()
    }
    .onReceive(task.$updateTrigger) { _ in rebuildModels() }
  }

  private func rebuildModels() {
    let all = task.models
    models = all.filter { !$0.imported }
    importedModels = all.filter { $0.imported }
    var variants: [String: [Model]] = [:]
    for m in all where m.parentModelName != nil {
      variants[m.parentModelName!, default: []].append(m)
    }
    modelVariants = variants
  }

  private func startAnimations() {
    guard enableAnimation else {
      taskIconProgress = 1; taskLabelProgress = 1
      descriptionProgress = 1; modelListProgress = 1
      return
    }
    withAnimation(.easeOut(duration: TASK_ICON_ANIMATION_DURATION_MS / 1000)
      .delay(ANIMATION_INIT_DELAY_MS / 1000)) {
      taskIconProgress = 1
    }
    withAnimation(.easeOut(duration: TASK_ICON_ANIMATION_DURATION_MS / 1000)
      .delay((ANIMATION_INIT_DELAY_MS + 300) / 1000)) {
      taskLabelProgress = 1
    }
    withAnimation(.easeOut(duration: DEFAULT_ANIMATION_DURATION_MS / 1000)
      .delay((ANIMATION_INIT_DELAY_MS + TASK_DESCRIPTION_SECTION_ANIMATION_START_MS) / 1000)) {
      descriptionProgress = 1
    }
    withAnimation(.easeOut(duration: DEFAULT_ANIMATION_DURATION_MS / 1000)
      .delay((ANIMATION_INIT_DELAY_MS + MODEL_LIST_ANIMATION_START_MS) / 1000)) {
      modelListProgress = 1
    }
  }
}

// NOTE: getTaskBgColor / getTaskBgGradientColors / getTaskIconColor are provided
// by the shared UI/Common/ColorUtils.swift.
