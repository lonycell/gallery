/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/modelitem/ModelItem.kt

import SwiftUI

/// Card representing a model in the model-manager list.
/// Mirrors `ModelItem` composable.
struct ModelItem: View {
  let model: Model
  let task: Task?
  let modelManagerViewModel: ModelManagerViewModel
  let onModelClicked: (Model) -> Void
  let onBenchmarkClicked: (Model) -> Void
  var expanded: Bool? = nil
  var showDeleteButton: Bool = true
  var canExpand: Bool = true
  var showBenchmarkButton: Bool = false
  var onExpanded: (Bool) -> Void = { _ in }
  var modelVariants: [Model] = []
  var tosViewModel: TosViewModel? = nil

  @State private var isExpanded: Bool = false

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  private var downloadStatus: ModelDownloadStatus? {
    modelManagerViewModel.uiState.modelDownloadStatus[model.name]
  }
  private var isBestOverall: Bool {
    model.bestForTaskIds.contains(task?.id ?? "")
  }
  private var isAicore: Bool { model.runtimeType == .aicore }
  private var isDownloadFailed: Bool { downloadStatus?.status == .failed }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12)
        .fill(customColors.taskCardBgColor)

      VStack(alignment: .leading, spacing: 8) {
        // Header row
        ZStack(alignment: .topTrailing) {
          ModelNameAndStatus(
            model: model,
            task: task,
            downloadStatus: downloadStatus,
            isExpanded: isExpanded,
            showModelSizeAndDownloadProgressLabel: modelVariants.isEmpty
          )
          .frame(maxWidth: .infinity, alignment: .leading)

          // Action menu + expand button
          HStack(alignment: .top, spacing: 0) {
            if modelVariants.isEmpty && downloadStatus?.status == .succeeded {
              ModelItemActionMenu(
                model: model,
                modelManagerViewModel: modelManagerViewModel,
                showBenchmarkButton: showBenchmarkButton,
                showDeleteButton: showDeleteButton
                  && model.localFileRelativeDirPathOverride.isEmpty
                  && !isAicore,
                onBenchmarkClicked: { onBenchmarkClicked(model) }
              )
              .offset(y: -12)
            }
            if !model.imported {
              Image(systemName: isExpanded ? "chevron.up.2" : "chevron.down.2")
                .imageScale(.small)
                .foregroundStyle(colors.onSurfaceVariant.opacity(0.6))
            }
          }
        }

        // Expanded content
        if isExpanded {
          VStack(spacing: 16) {
            if !model.info.isEmpty {
              MarkdownText(
                text: model.info,
                smallFontSize: true,
                textColor: colors.onSurfaceVariant
              )
              .padding(.top, 8)
            }
            if isAicore && isDownloadFailed {
              AICoreAccessPanel()
            }
          }
        }

        // Download panel / variants
        if modelVariants.isEmpty {
          DownloadModelPanel(
            model: model,
            task: task,
            modelManagerViewModel: modelManagerViewModel,
            downloadStatus: downloadStatus?.status,
            downloadProgress: calculateDownloadProgress(downloadStatus: downloadStatus),
            isExpanded: isExpanded,
            onTryItClicked: { onModelClicked(model) },
            tosViewModel: tosViewModel
          )
          .padding(.top, isExpanded ? 12 : 0)
          .frame(maxWidth: .infinity)
        } else {
          VStack(spacing: 8) {
            ForEach(([model] + modelVariants), id: \.name) { variantModel in
              ModelVariantRow(
                variantModel: variantModel,
                task: task,
                modelManagerViewModel: modelManagerViewModel,
                isExpanded: isExpanded,
                showBenchmarkButton: showBenchmarkButton,
                showDeleteButton: showDeleteButton,
                onBenchmarkClicked: onBenchmarkClicked,
                onTryItClicked: { onModelClicked(variantModel) }
              )
            }
          }
          .padding(.top, isExpanded ? 12 : 0)
        }
      }
      .padding(16)
    }
    .onTapGesture {
      guard canExpand else { return }
      if !model.imported {
        isExpanded.toggle()
        onExpanded(isExpanded)
      } else if !showBenchmarkButton {
        onModelClicked(model)
      }
    }
    .onAppear {
      isExpanded = expanded ?? isBestOverall
    }
  }
}

// MARK: - ModelVariantRow

private struct ModelVariantRow: View {
  let variantModel: Model
  let task: Task?
  let modelManagerViewModel: ModelManagerViewModel
  let isExpanded: Bool
  let showBenchmarkButton: Bool
  let showDeleteButton: Bool
  let onBenchmarkClicked: (Model) -> Void
  let onTryItClicked: () -> Void

  @Environment(\.galleryColors) private var colors

  private var variantStatus: ModelDownloadStatus? {
    modelManagerViewModel.uiState.modelDownloadStatus[variantModel.name]
  }
  private var isNotDownloaded: Bool { variantStatus?.status == .notDownloaded }
  private var isDownloaded: Bool { variantStatus?.status == .succeeded }
  private var showColumnLayout: Bool { (!isNotDownloaded && !isDownloaded) || isExpanded }

  var body: some View {
    Group {
      if showColumnLayout {
        VStack(alignment: .leading, spacing: 8) {
          variantHeader
          variantPanel
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
      } else {
        HStack(spacing: 8) {
          variantHeader
            .frame(maxWidth: .infinity)
          variantPanel
        }
      }
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 16)
    .background(colors.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
  }

  @ViewBuilder
  private var variantHeader: some View {
    HStack(spacing: 4) {
      VStack(alignment: .leading, spacing: 2) {
        Text(variantModel.variantLabel ?? variantModel.name)
          .font(AppTypography.bodyMedium)
          .lineLimit(1)
          .truncationMode(.tail)
          .minimumScaleFactor(0.5)
        ModelStatusDetails(
          model: variantModel,
          task: task,
          downloadStatus: variantStatus,
          isExpanded: isExpanded
        )
      }
      Spacer()
      if variantStatus?.status == .succeeded {
        ModelItemActionMenu(
          model: variantModel,
          modelManagerViewModel: modelManagerViewModel,
          showBenchmarkButton: showBenchmarkButton,
          showDeleteButton: showDeleteButton
            && variantModel.localFileRelativeDirPathOverride.isEmpty
            && variantModel.runtimeType != .aicore,
          onBenchmarkClicked: { onBenchmarkClicked(variantModel) }
        )
        .offset(y: showColumnLayout ? 0 : 12)
      }
    }
  }

  @ViewBuilder
  private var variantPanel: some View {
    DownloadModelPanel(
      model: variantModel,
      task: task,
      modelManagerViewModel: modelManagerViewModel,
      downloadStatus: variantStatus?.status,
      downloadProgress: calculateDownloadProgress(downloadStatus: variantStatus),
      isExpanded: isExpanded,
      onTryItClicked: onTryItClicked,
      downloadButtonBackgroundColor: Color(UIColor.systemFill)
    )
  }
}

// MARK: - ModelItemActionMenu

/// Three-dot overflow menu for benchmark + delete actions.
/// Mirrors `ModelItemActionMenu` composable.
struct ModelItemActionMenu: View {
  let model: Model
  let modelManagerViewModel: ModelManagerViewModel
  let showBenchmarkButton: Bool
  let showDeleteButton: Bool
  let onBenchmarkClicked: () -> Void

  @State private var showMenu: Bool = false
  @State private var showConfirmDeleteDialog: Bool = false

  @Environment(\.galleryColors) private var colors

  var body: some View {
    Menu {
      if showBenchmarkButton {
        Button {
          onBenchmarkClicked()
        } label: {
          Label(Str.benchmark, systemImage: "chart.bar")
        }
      }
      if showDeleteButton {
        Button(role: .destructive) {
          showConfirmDeleteDialog = true
        } label: {
          Label(Str.delete, systemImage: "trash")
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .imageScale(.medium)
        .foregroundStyle(colors.onSurfaceVariant)
        .frame(width: 44, height: 44)
    }
    .overlay {
      if showConfirmDeleteDialog {
        ConfirmDeleteModelDialog(
          model: model,
          onConfirm: {
            modelManagerViewModel.deleteModel(model)
            showConfirmDeleteDialog = false
          },
          onDismiss: { showConfirmDeleteDialog = false }
        )
      }
    }
  }
}
