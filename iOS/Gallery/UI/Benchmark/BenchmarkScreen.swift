// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/benchmark/BenchmarkScreen.kt

import SwiftUI

/// Main benchmark configuration screen.
/// Shows config sliders, a model picker, and run/view-results buttons.
/// Mirrors `BenchmarkScreen`.
struct BenchmarkScreen: View {
  let initialModel: Model
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  let onBackClicked: () -> Void

  @StateObject private var viewModel: BenchmarkViewModel

  @State private var selectedModelName: String
  @State private var showConfirmRunDialog = false
  @State private var enableBackButton = true

  // Config values
  @State private var accelerator: String
  @State private var prefillTokens: Double = 256
  @State private var decodeTokens: Double = 256
  @State private var runCount: Double = 3

  // Filtered results (for enabling "View results")
  @State private var filteredResults: [BenchmarkResultInfo] = []

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  init(initialModel: Model,
       modelManagerViewModel: ModelManagerViewModel,
       onBackClicked: @escaping () -> Void) {
    self.initialModel = initialModel
    self.modelManagerViewModel = modelManagerViewModel
    self.onBackClicked = onBackClicked
    _selectedModelName = State(initialValue: initialModel.name)
    _accelerator = State(initialValue: initialModel.accelerators.first?.label ?? Accelerator.cpu.label)
    // BenchmarkViewModel requires a DataStoreRepository; obtained from modelManagerViewModel.
    // NOTE: We initialise it here rather than injecting it via @StateObject's init(wrappedValue:)
    // because dataStoreRepository is available via modelManagerViewModel.
    _viewModel = StateObject(wrappedValue: BenchmarkViewModel(
      dataStoreRepository: modelManagerViewModel.dataStoreRepository))
  }

  private var selectedModel: Model? {
    modelManagerViewModel.getModelByName(selectedModelName)
  }
  private var maxToken: Int { selectedModel?.llmMaxToken ?? 2048 }
  private var sumTokens: Int { Int(prefillTokens) + Int(decodeTokens) }
  private var exceedsMax: Bool { sumTokens > maxToken }

  private var downloadedLlmModelNames: [String] {
    modelManagerViewModel.getAllDownloadedModels().filter { $0.isLlm }.map { $0.name }
  }

  var body: some View {
    ZStack {
      configScreen

      // Results viewer overlay
      if viewModel.uiState.showResultsViewer {
        BenchmarkResultsViewer(
          initialModelName: selectedModelName,
          modelManagerViewModel: modelManagerViewModel,
          viewModel: viewModel,
          onClose: { viewModel.setShowResultsViewer(false) }
        )
        .transition(.asymmetric(
          insertion: .move(edge: .bottom).combined(with: .opacity),
          removal: .move(edge: .bottom).combined(with: .opacity)
        ))
        .zIndex(1)
      }
    }
    .animation(.easeInOut(duration: 0.3), value: viewModel.uiState.showResultsViewer)
    .onChange(of: viewModel.uiState.results, initial: true) { _, _ in
      rebuildFilteredResults()
    }
    .onChange(of: selectedModelName) { _, _ in
      rebuildFilteredResults()
      // Reset accelerator to first valid one for this model
      if let m = selectedModel {
        accelerator = m.accelerators.first?.label ?? Accelerator.cpu.label
        prefillTokens = min(prefillTokens, Double(m.llmMaxToken))
      }
    }
  }

  @ViewBuilder
  private var configScreen: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          VStack(spacing: 24) {
            // Accelerator picker
            configSection(title: ConfigKeys.ACCELERATOR.label) {
              HStack(spacing: 8) {
                if let m = selectedModel {
                  ForEach(m.accelerators, id: \.label) { accel in
                    Button(action: { accelerator = accel.label }) {
                      Text(accel.label)
                        .font(AppTypography.labelLarge)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(accelerator == accel.label
                                    ? colors.primaryContainer : colors.surfaceContainer)
                        .foregroundStyle(accelerator == accel.label
                                        ? colors.onPrimaryContainer : colors.onSurfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                  }
                }
              }
            }

            // Prefill tokens
            BenchmarkSlider(
              title: "\(ConfigKeys.PREFILL_TOKENS.label): \(Int(prefillTokens))",
              value: $prefillTokens,
              range: 16...(selectedModel.map { Double($0.llmMaxToken) } ?? 4096),
              step: 1
            )

            // Decode tokens
            BenchmarkSlider(
              title: "\(ConfigKeys.DECODE_TOKENS.label): \(Int(decodeTokens))",
              value: $decodeTokens,
              range: 16...1024,
              step: 1
            )

            // Number of runs
            BenchmarkSlider(
              title: "\(ConfigKeys.NUMBER_OF_RUNS.label): \(Int(runCount))",
              value: $runCount,
              range: 1...10,
              step: 1
            )

            // Token limit warning
            Text(String(format: Str.benchmarkTokensLimitMessage, sumTokens, maxToken))
              .font(AppTypography.bodyMedium)
              .foregroundStyle(exceedsMax ? customColors.warningTextColor : colors.onSurfaceVariant)
          }
          .padding(16)
        }

        // Bottom buttons
        HStack(spacing: 8) {
          Button(action: {
            viewModel.setShowResultsViewer(true)
          }) {
            HStack(spacing: 4) {
              Image(systemName: "list.bullet")
              Text(Str.viewResults)
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .disabled(filteredResults.isEmpty)

          Button(action: {
            if selectedModel != nil { showConfirmRunDialog = true }
          }) {
            HStack(spacing: 4) {
              Image(systemName: "chart.bar")
              Text(Str.benchmark)
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .disabled(exceedsMax)
        }
        .padding(16)
      }
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarBackButtonHidden(true)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button(action: onBackClicked) {
            Image(systemName: "chevron.left")
          }
          .disabled(!enableBackButton)
        }
        ToolbarItem(placement: .principal) {
          VStack(spacing: 2) {
            Text(Str.benchmarkModel)
              .font(AppTypography.titleMedium)
              .foregroundStyle(colors.onSurface)
            BenchmarkModelPicker(
              selectedModelName: selectedModelName,
              modelNames: downloadedLlmModelNames,
              title: Str.selectDownloadedModel,
              onSelected: { selectedModelName = $0 }
            )
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Spacer().frame(width: 48)
        }
      }
    }
    .alert(Str.runBenchmark, isPresented: $showConfirmRunDialog) {
      Button(Str.continueButtonLabel) {
        guard let model = selectedModel else { return }
        viewModel.runBenchmark(
          model: model,
          accelerator: accelerator,
          prefillTokens: Int(prefillTokens),
          decodeTokens: Int(decodeTokens),
          runCount: Int(runCount)
        )
      }
      Button(Str.cancel, role: .cancel) {}
    } message: {
      Text(Str.runBenchmarkConfirmationMsg)
    }
  }

  @ViewBuilder
  private func configSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(AppFont.font(size: 14, weight: .medium))
        .foregroundStyle(colors.onSurface)
      content()
    }
  }

  private func rebuildFilteredResults() {
    filteredResults = viewModel.uiState.results.filter {
      $0.benchmarkResult.llmResult?.basicInfo.modelName == selectedModelName
    }
  }
}

// MARK: - BenchmarkSlider

private struct BenchmarkSlider: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double

  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(AppFont.font(size: 14, weight: .medium))
        .foregroundStyle(colors.onSurface)
      Slider(value: $value, in: range, step: step)
        .tint(colors.primary)
    }
  }
}
