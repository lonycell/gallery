// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/modelmanager/GlobalModelManager.kt

import SwiftUI
import UniformTypeIdentifiers

private let TAG = "AGGlobalMM"

/// All-models list with import FAB, task-selection sheet, and optional promo banner.
/// Mirrors `GlobalModelManager`.
struct GlobalModelManager: View {
  @ObservedObject var viewModel: ModelManagerViewModel
  let navigateUp: () -> Void
  let onModelSelected: (Task, Model) -> Void
  let onBenchmarkClicked: (Model) -> Void

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  // Model lists (rebuilt on modelImportingUpdateTrigger)
  @State private var builtInModels: [Model] = []
  @State private var importedModels: [Model] = []
  @State private var modelVariants: [String: [Model]] = [:]
  @State private var expandedStates: [String: Bool] = [:]

  // Task selector sheet
  @State private var taskCandidates: [Task] = []
  @State private var modelForTaskCandidate: Model? = nil
  @State private var showTaskSelectorSheet = false

  // Import flow
  @State private var showImportOptionsSheet = false
  @State private var showImportDialog = false
  @State private var showImportingDialog = false
  @State private var selectedFileURL: URL? = nil
  @State private var selectedFileInfo: ImportedModel? = nil
  @State private var showFileImporter = false
  @State private var showUnsupportedFileTypeAlert = false
  @State private var showUnsupportedWebModelAlert = false

  // Promo
  private let promoId = "gm4_banner"
  @State private var showPromo = false

  // Snackbar
  @State private var snackbarMessage: String? = nil

  private var totalModelCount: Int { builtInModels.count + importedModels.count }

  var body: some View {
    NavigationStack {
      ZStack(alignment: .bottomCenter) {
        ScrollView {
          LazyVStack(spacing: 8) {
            // Promo banner
            if showPromo {
              PromoBannerGm4(onDismiss: {
                withAnimation { showPromo = false }
                viewModel.dataStoreRepository.addViewedPromoId(promoId: promoId)
              })
              .padding(.horizontal, 16)
              .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .move(edge: .top))
              ))
            }

            // Built-in models
            ForEach(builtInModels, id: \.name) { model in
              let expanded = expandedStates[model.name] ?? true
              // NOTE: ModelItem is owned by common/modelitem agent — reference by name.
              ModelItem(
                model: model,
                modelVariants: modelVariants[model.name] ?? [],
                task: nil,
                modelManagerViewModel: viewModel,
                onModelClicked: handleModelClick,
                onBenchmarkClicked: onBenchmarkClicked,
                expanded: expanded,
                showBenchmarkButton: model.runtimeType == .litertLm,
                onExpanded: { expandedStates[model.name] = $0 }
              )
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

              ForEach(importedModels, id: \.name) { model in
                ModelItem(
                  model: model,
                  task: nil,
                  modelManagerViewModel: viewModel,
                  onModelClicked: handleModelClick,
                  onBenchmarkClicked: onBenchmarkClicked,
                  expanded: true,
                  showBenchmarkButton: model.runtimeType == .litert_lm
                )
              }
            }

            Spacer().frame(height: 100)
          }
          .padding(.horizontal, 16)
          .padding(.top, 16)
        }
        .background(colors.surfaceContainer)

        // Bottom gradient
        VStack {
          Spacer()
          LinearGradient(
            colors: [.clear, colors.surfaceContainer],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: 60)
          .allowsHitTesting(false)
        }

        // Snackbar
        if let msg = snackbarMessage {
          VStack {
            Spacer()
            Text(msg)
              .font(AppTypography.bodyMedium)
              .foregroundStyle(.white)
              .padding(.horizontal, 16)
              .padding(.vertical, 10)
              .background(Color.black.opacity(0.8))
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .padding(.bottom, 80)
          }
          .transition(.opacity)
          .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
              withAnimation { snackbarMessage = nil }
            }
          }
        }
      }
      .navigationTitle(Text("\(Str.drawerModelsLabel) (\(totalModelCount))"))
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarBackButtonHidden(true)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          HStack(spacing: 4) {
            Image(systemName: "list.bullet.rectangle")
              .frame(width: 20, height: 20)
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: navigateUp) {
            Image(systemName: "xmark")
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        // FAB
        HStack {
          Spacer()
          Button(action: { showImportOptionsSheet = true }) {
            Image(systemName: "plus")
              .padding(14)
              .background(colors.secondaryContainer)
              .foregroundStyle(colors.secondary)
              .clipShape(Circle())
              .shadow(radius: 4)
          }
          .padding(.trailing, 16)
          .padding(.bottom, 16)
          .accessibilityLabel(Str.cdImportModelButton)
        }
      }
    }
    // Task selector sheet
    .sheet(isPresented: $showTaskSelectorSheet) {
      taskSelectorSheet
    }
    // Import options sheet
    .confirmationDialog("Import model", isPresented: $showImportOptionsSheet, titleVisibility: .visible) {
      Button("From local model file") {
        showFileImporter = true
      }
      Button("Cancel", role: .cancel) {}
    }
    // File importer
    .fileImporter(
      isPresented: $showFileImporter,
      allowedContentTypes: [UTType.data],
      allowsMultipleSelection: false
    ) { result in
      handleFilePicked(result: result)
    }
    // Import config dialog
    .sheet(isPresented: $showImportDialog) {
      if let url = selectedFileURL {
        let info = ImportedModel(fileName: url.lastPathComponent, fileSize: fileSizeOf(url))
        ModelImportDialog(
          fileName: info.fileName,
          fileSize: info.fileSize,
          onDismiss: { showImportDialog = false },
          onDone: { importedInfo in
            selectedFileInfo = importedInfo
            showImportDialog = false
            showImportingDialog = true
          }
        )
      }
    }
    // Import progress dialog
    .sheet(isPresented: $showImportingDialog) {
      if let url = selectedFileURL, let info = selectedFileInfo {
        ModelImportingDialog(
          sourceURL: url,
          info: info,
          onDismiss: { showImportingDialog = false },
          onDone: { imported in
            viewModel.addImportedLlmModel(info: imported)
            showImportingDialog = false
            withAnimation { snackbarMessage = "Model imported successfully" }
          }
        )
        .presentationDetents([.medium, .large])
      }
    }
    // Unsupported file type
    .alert("Unsupported file type", isPresented: $showUnsupportedFileTypeAlert) {
      Button("OK") {}
    } message: {
      Text("Only \".task\" or \".litertlm\" file type is supported.")
    }
    // Unsupported web model
    .alert("Unsupported model type", isPresented: $showUnsupportedWebModelAlert) {
      Button("OK") {}
    } message: {
      Text("Looks like the model is a web-only model and is not supported by the app.")
    }
    .onAppear {
      rebuildModels()
      Task {
        showPromo = !viewModel.dataStoreRepository.hasViewedPromo(promoId: promoId)
      }
    }
    .onChange(of: viewModel.uiState.modelImportingUpdateTrigger) { _, _ in
      rebuildModels()
    }
  }

  // MARK: - Task selector sheet

  @ViewBuilder
  private var taskSelectorSheet: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(Str.modelManagerSelectTaskTitle)
        .font(AppTypography.titleLarge)
        .foregroundStyle(colors.onSurface)
        .padding(.bottom, 8)
        .padding(.horizontal, 16)

      ForEach(taskCandidates) { task in
        Button(action: {
          if let model = modelForTaskCandidate {
            onModelSelected(task, model)
          }
          showTaskSelectorSheet = false
        }) {
          HStack {
            Text(task.label)
              .font(AppTypography.titleMedium)
              .foregroundStyle(colors.onSurface)
            Spacer()
            TaskIcon(task: task, width: 40)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 4)
        }
      }

      Spacer().frame(height: 16)
    }
    .padding(.top, 16)
    .presentationDetents([.medium, .large])
  }

  // MARK: - Helpers

  private func rebuildModels() {
    let allowlist = viewModel.allowlistModels
    let allowlistOrderMap = Dictionary(uniqueKeysWithValues: allowlist.enumerated().map { ($0.element.name, $0.offset) })
    let all = viewModel.getAllModels()
      .filter { $0.parentModelName == nil || $0.parentModelName!.isEmpty }
      .sorted { a, b in
        let ia = allowlistOrderMap[a.name] ?? Int.max
        let ib = allowlistOrderMap[b.name] ?? Int.max
        if ia != ib { return ia < ib }
        return a.name < b.name
      }
    builtInModels = all.filter { !$0.imported }
    importedModels = all.filter { $0.imported }

    // Rebuild variants
    var variants: [String: [Model]] = [:]
    for task in viewModel.uiState.tasks {
      for m in task.models where m.parentModelName != nil {
        variants[m.parentModelName!, default: []].append(m)
      }
    }
    modelVariants = variants
  }

  private func handleModelClick(_ model: Model) {
    let tasks = viewModel.uiState.tasks.filter { t in t.models.contains { $0.name == model.name } }
    if tasks.count == 1 {
      onModelSelected(tasks[0], model)
    } else if tasks.count > 1 {
      taskCandidates = tasks
      modelForTaskCandidate = model
      showTaskSelectorSheet = true
    }
  }

  private func handleFilePicked(result: Result<[URL], Error>) {
    guard case .success(let urls) = result, let url = urls.first else { return }
    _ = url.startAccessingSecurityScopedResource()
    let name = url.lastPathComponent
    if !name.hasSuffix(".task") && !name.hasSuffix(".litertlm") {
      showUnsupportedFileTypeAlert = true
    } else if name.lowercased().contains("-web") {
      showUnsupportedWebModelAlert = true
    } else {
      selectedFileURL = url
      showImportDialog = true
    }
  }
}

private func fileSizeOf(_ url: URL) -> Int64 {
  (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0!) } ?? 0
}
