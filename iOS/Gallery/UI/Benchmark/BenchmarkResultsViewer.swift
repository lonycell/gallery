// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/benchmark/BenchmarkResultsViewer.kt

import SwiftUI

/// Full-screen results viewer: running spinner, empty state, and a scrollable
/// list of collapsible result cards with baseline comparison.
/// Mirrors `BenchmarkResultsViewer`.
struct BenchmarkResultsViewer: View {
  let initialModelName: String
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  @ObservedObject var viewModel: BenchmarkViewModel
  let onClose: () -> Void

  @State private var selectedModelName: String
  @State private var filterableModelNames: [String] = []
  @State private var filteredResults: [BenchmarkResultInfo] = []
  @State private var showConfirmDeleteDialog = false
  @State private var resultIdToDelete = ""
  @State private var showComparisonHelp = false
  @State private var animatePlacement = false

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  init(initialModelName: String,
       modelManagerViewModel: ModelManagerViewModel,
       viewModel: BenchmarkViewModel,
       onClose: @escaping () -> Void) {
    self.initialModelName = initialModelName
    self.modelManagerViewModel = modelManagerViewModel
    self.viewModel = viewModel
    self.onClose = onClose
    _selectedModelName = State(initialValue: initialModelName)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        content
      }
      .background(colors.surfaceContainer)
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarBackButtonHidden(true)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          if filteredResults.count > 1 {
            Button(action: { showComparisonHelp = true }) {
              Image(systemName: "questionmark.circle")
            }
          } else {
            Spacer().frame(width: 48)
          }
        }
        ToolbarItem(placement: .principal) {
          if !viewModel.uiState.running {
            VStack(spacing: 2) {
              Text(Str.benchmarkResults)
                .font(AppTypography.titleMedium)
                .foregroundStyle(colors.onSurface)
              BenchmarkModelPicker(
                selectedModelName: selectedModelName,
                modelNames: filterableModelNames,
                title: Str.selectModel,
                onSelected: { name in
                  animatePlacement = true
                  selectedModelName = name
                  DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    animatePlacement = false
                  }
                }
              )
            }
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          if !viewModel.uiState.running {
            Button(action: onClose) {
              Image(systemName: "xmark")
            }
          }
        }
      }
    }
    .onChange(of: viewModel.uiState.results, initial: true) { _, _ in
      rebuildFilterableNames()
      rebuildFilteredResults()
    }
    .onChange(of: selectedModelName) { _, _ in
      rebuildFilteredResults()
      viewModel.clearBaseline()
    }
    .task(id: filteredResults.count) {
      // Show comparison help on first time seeing multiple results
      if filteredResults.count > 1 &&
         !viewModel.dataStoreRepository.getHasSeenBenchmarkComparisonHelp() {
        try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
        showComparisonHelp = true
        viewModel.dataStoreRepository.setHasSeenBenchmarkComparisonHelp(true)
      }
    }
    // Confirm delete
    .alert(Str.deleteBenchmarkResultDialogTitle, isPresented: $showConfirmDeleteDialog) {
      Button(Str.delete, role: .destructive) {
        animatePlacement = true
        viewModel.deleteBenchmarkResult(id: resultIdToDelete)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { animatePlacement = false }
      }
      Button(Str.cancel, role: .cancel) {}
    } message: {
      Text(Str.deleteBenchmarkResultDialogContent)
    }
    // Comparison help sheet
    .sheet(isPresented: $showComparisonHelp) {
      comparisonHelpSheet
        .presentationDetents([.medium])
    }
  }

  // MARK: - Main content

  @ViewBuilder
  private var content: some View {
    if viewModel.uiState.running {
      VStack(spacing: 24) {
        ProgressView()
          .scaleEffect(1.5)
        Text(Str.runningBenchmarkMsg)
          .font(AppTypography.titleMedium)
          .foregroundStyle(colors.onSurface)
        Text("\(viewModel.uiState.completedRunCount) / \(viewModel.uiState.totalRunCount)")
          .font(AppTypography.labelLarge)
          .foregroundStyle(colors.onSurfaceVariant)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .transition(.scale(scale: 0.8).combined(with: .opacity))
    } else {
      if filteredResults.isEmpty {
        VStack {
          Spacer()
          Text(Str.benchmarkNoResults)
            .font(AppTypography.titleMedium)
            .foregroundStyle(colors.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
          Spacer()
        }
        .frame(maxWidth: .infinity)
      } else {
        resultsList
      }
    }
  }

  @ViewBuilder
  private var resultsList: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        Spacer().frame(height: 16)

        // Expand / collapse all buttons
        if filteredResults.count > 1 {
          HStack(spacing: 8) {
            SmallOutlinedButton(onClick: { viewModel.expandAll() },
                                label: Str.expandAll,
                                systemImage: "arrow.up.left.and.arrow.down.right")
            SmallOutlinedButton(onClick: { viewModel.collapseAll() },
                                label: Str.collapseAll,
                                systemImage: "arrow.down.right.and.arrow.up.left")
            Spacer()
          }
          .padding(.bottom, 16)
        }

        ForEach(Array(filteredResults.enumerated()), id: \.element.id) { index, result in
          if let llmResult = result.benchmarkResult.llmResult {
            let modelName = llmResult.basicInfo.modelName
            let dateStr = formatMs(llmResult.basicInfo.startMs)

            Accordions(
              title: "\(modelName) · \(llmResult.basicInfo.accelerator)",
              expanded: result.expanded,
              onExpandedChange: { viewModel.setExpanded(id: result.id, expanded: $0) },
              subtitle: dateStr,
              boldTitle: true,
              titleRowAction: AnyView(
                filteredResults.count > 1
                  ? AnyView(FilterChipView(
                    label: Str.baseline,
                    selected: result.id == viewModel.uiState.baselineResult?.id,
                    onTap: { viewModel.setBaseline(id: result.id) }
                  ))
                  : AnyView(EmptyView())
              )
            ) {
              resultCardContent(result: result, llmResult: llmResult)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))

            if index < filteredResults.count - 1 {
              Spacer().frame(height: 12)
            }
          }
        }

        Spacer().frame(height: 80)
      }
      .padding(.horizontal, 16)
    }
  }

  @ViewBuilder
  private func resultCardContent(result: BenchmarkResultInfo, llmResult: LlmBenchmarkResult) -> some View {
    VStack(spacing: 8) {
      // Basic info accordion
      Accordions(
        title: Str.basicInfo,
        expanded: result.basicInfoExpanded,
        onExpandedChange: { viewModel.setBasicInfoExpanded(id: result.id, expanded: $0) },
        bgColor: colors.surfaceContainerLow
      ) {
        VStack(spacing: 8) {
          StatRow(label: "Model", value: llmResult.basicInfo.modelName)
          StatRow(label: "Accelerator", value: llmResult.basicInfo.accelerator)
          StatRow(label: "Prefill tokens", value: "\(llmResult.basicInfo.prefillTokens)")
          StatRow(label: "Decode tokens", value: "\(llmResult.basicInfo.decodeTokens)")
          StatRow(label: "Number of runs", value: "\(llmResult.basicInfo.numberOfRuns)")
          StatRow(label: "App version", value: llmResult.basicInfo.appVersion)
        }
        .padding(.leading, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
      }
      .clipShape(RoundedRectangle(cornerRadius: 12))

      // Stats accordion
      let baseline = viewModel.uiState.baselineResult?.benchmarkResult.llmResult?.stats
      Accordions(
        title: "\(Str.results) (\(Str.runs(Int(llmResult.basicInfo.numberOfRuns))))",
        expanded: result.statsExpanded,
        onExpandedChange: { viewModel.setStatsExpanded(id: result.id, expanded: $0) },
        bgColor: colors.surfaceContainerLow,
        titleRowAction: AnyView(
          llmResult.basicInfo.numberOfRuns > 1
            ? AnyView(AggregationPicker(
              aggregation: result.aggregation,
              onSelect: { viewModel.setAggregation(id: result.id, aggregation: $0) }
            ))
            : AnyView(EmptyView())
        ),
        hideTitleRowActionOnCollapse: true
      ) {
        let baselineStats = result.id != viewModel.uiState.baselineResult?.id ? baseline : nil
        let baselineAgg = result.id != viewModel.uiState.baselineResult?.id
          ? viewModel.uiState.baselineResult?.aggregation : nil

        VStack(spacing: 8) {
          ValueSeriesRow(label: "Prefill speed",
                        valueSeries: llmResult.stats.prefillSpeed,
                        aggregation: result.aggregation,
                        unit: "tokens/sec",
                        baselineValueSeries: baselineStats?.prefillSpeed,
                        baselineAggregation: baselineAgg)
          ValueSeriesRow(label: "Decode speed",
                        valueSeries: llmResult.stats.decodeSpeed,
                        aggregation: result.aggregation,
                        unit: "tokens/sec",
                        baselineValueSeries: baselineStats?.decodeSpeed,
                        baselineAggregation: baselineAgg)
          ValueSeriesRow(label: "Time to first token",
                        valueSeries: llmResult.stats.timeToFirstToken,
                        aggregation: result.aggregation,
                        unit: "sec",
                        baselineValueSeries: baselineStats?.timeToFirstToken,
                        baselineAggregation: baselineAgg,
                        lessIsBetter: true)
          StatRow(label: "First init time",
                  value: String(format: "%.2f", llmResult.stats.firstInitTimeMs),
                  unit: "ms",
                  rawValue: llmResult.stats.firstInitTimeMs,
                  baselineValue: baselineStats?.firstInitTimeMs,
                  lessIsBetter: true)
          if llmResult.stats.nonFirstInitTimeMs.value.count > 1 {
            ValueSeriesRow(label: "Steady init time",
                          valueSeries: llmResult.stats.nonFirstInitTimeMs,
                          aggregation: result.aggregation,
                          unit: "ms",
                          baselineValueSeries: baselineStats?.nonFirstInitTimeMs,
                          baselineAggregation: baselineAgg,
                          lessIsBetter: true)
          }
        }
        .padding(.leading, 6)
        .padding(.top, 6)
      }
      .clipShape(RoundedRectangle(cornerRadius: 12))

      // Action buttons
      HStack(spacing: 8) {
        SmallOutlinedButton(
          onClick: {
            resultIdToDelete = result.id
            showConfirmDeleteDialog = true
          },
          label: Str.delete,
          systemImage: "trash"
        )

        Spacer()

        Button(action: { copyResultToClipboard(result: result, llmResult: llmResult) }) {
          HStack(spacing: 4) {
            Image(systemName: "doc.on.doc")
              .font(.system(size: 14))
            Text(Str.copy)
              .font(AppTypography.labelLarge)
          }
          .padding(SMALL_BUTTON_CONTENT_PADDING)
          .background(colors.secondaryContainer)
          .foregroundStyle(colors.onSecondaryContainer)
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
      }
      .padding(.bottom, 2)
    }
  }

  // MARK: - Comparison help sheet

  @ViewBuilder
  private var comparisonHelpSheet: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 8) {
        Image(systemName: "questionmark.circle")
        Text(Str.benchmarkComparisonHelpTitle)
          .font(AppTypography.titleMedium)
      }
      // NOTE: MarkdownText is owned by common agent — reference by name.
      // MarkdownText(text: Str.benchmarkComparisonHelpContent, smallFontSize: true)
      Text(Str.benchmarkComparisonHelpContent)
        .font(AppTypography.bodySmall)

      SmallOutlinedButton(onClick: { showComparisonHelp = false }, label: Str.dismiss)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
    .padding(.top, 24)
  }

  // MARK: - Helpers

  private func rebuildFilterableNames() {
    let all = viewModel.uiState.results.compactMap {
      $0.benchmarkResult.llmResult?.basicInfo.modelName
    }.unique()
    filterableModelNames = [Str.all] + all
  }

  private func rebuildFilteredResults() {
    let str = selectedModelName
    filteredResults = viewModel.uiState.results.filter {
      str == Str.all || $0.benchmarkResult.llmResult?.basicInfo.modelName == str
    }
  }

  private func copyResultToClipboard(result: BenchmarkResultInfo, llmResult: LlmBenchmarkResult) {
    let csv = getBenchmarkResultCsv(llmResult: llmResult, aggregation: result.aggregation)
    UIPasteboard.general.string = csv
  }
}

// MARK: - StatRow

private struct StatRow: View {
  let label: String
  let value: String
  var unit: String = ""
  var rawValue: Double? = nil
  var baselineValue: Double? = nil
  var lessIsBetter: Bool = false

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  var body: some View {
    HStack(alignment: .top) {
      Text(label)
        .font(AppTypography.labelMedium)
        .foregroundStyle(colors.onSurface)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .truncationMode(.middle)

      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(value)
            .font(AppTypography.labelMedium)
            .foregroundStyle(colors.onSurface)
            .lineLimit(1)
            .truncationMode(.middle)

          Spacer()

          if let bv = baselineValue {
            let dv = rawValue ?? Double(value) ?? 0
            let pct = abs(bv) > 1e-10 ? (dv - bv) / bv * 100 : 0
            let sign = pct >= 0 ? "+" : "-"
            let betterSign = lessIsBetter ? "-" : "+"
            let color = sign == betterSign ? customColors.successColor : customColors.errorTextColor
            Text("\(sign)\(String(format: "%.1f", abs(pct)))%")
              .font(AppTypography.labelMedium)
              .foregroundStyle(color)
          }
        }
        if !unit.isEmpty {
          Text(unit)
            .font(AppTypography.labelMedium)
            .foregroundStyle(colors.onSurfaceVariant.opacity(0.7))
        }
      }
      .frame(maxWidth: .infinity * 0.4)
    }
  }
}

// MARK: - ValueSeriesRow

private struct ValueSeriesRow: View {
  let label: String
  let valueSeries: ValueSeries
  let aggregation: Aggregation
  var unit: String = ""
  var baselineValueSeries: ValueSeries? = nil
  var baselineAggregation: Aggregation? = nil
  var lessIsBetter: Bool = false

  @State private var showDetail = false

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  var body: some View {
    let value = getAggregationValue(valueSeries: valueSeries, aggregation: aggregation)
    let baselineValue: Double? = {
      guard let bvs = baselineValueSeries, let bagg = baselineAggregation else { return nil }
      return getAggregationValue(valueSeries: bvs, aggregation: bagg)
    }()
    let isMultipleRuns = valueSeries.value.count > 1

    HStack(alignment: .top) {
      Text(label)
        .font(AppTypography.labelMedium)
        .foregroundStyle(colors.onSurface)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .truncationMode(.middle)

      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(String(format: "%.2f", value))
            .font(AppTypography.labelMedium)
            .foregroundStyle(isMultipleRuns ? customColors.linkColor : colors.onSurface)
            .lineLimit(1)
            .truncationMode(.middle)
            .overlay(
              isMultipleRuns
                ? Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(customColors.linkColor)
                    .offset(y: 8)
                    .opacity(0.8)
                : nil,
              alignment: .bottom
            )
            .onTapGesture { if isMultipleRuns { showDetail = true } }

          Spacer()

          if let bv = baselineValue, abs(bv) > 1e-6 {
            let pct = (value - bv) / bv * 100
            let sign = pct >= 0 ? "+" : "-"
            let betterSign = lessIsBetter ? "-" : "+"
            let color = sign == betterSign ? customColors.successColor : customColors.errorTextColor
            Text("\(sign)\(String(format: "%.1f", abs(pct)))%")
              .font(AppTypography.labelMedium)
              .foregroundStyle(color)
          }
        }
        if !unit.isEmpty {
          Text(unit)
            .font(AppTypography.labelMedium)
            .foregroundStyle(colors.onSurfaceVariant.opacity(0.7))
        }
      }
      .frame(maxWidth: .infinity * 0.4)
    }
    .sheet(isPresented: $showDetail) {
      BenchmarkValueSeriesViewer(
        title: "\(label) (\(unit))",
        valueSeries: valueSeries,
        onDismiss: { showDetail = false }
      )
    }
  }
}

// MARK: - AggregationPicker

private struct AggregationPicker: View {
  let aggregation: Aggregation
  let onSelect: (Aggregation) -> Void

  @State private var showMenu = false
  @Environment(\.galleryColors) private var colors

  var body: some View {
    Menu {
      ForEach(Aggregation.allCases, id: \.self) { agg in
        Button(agg.rawValue) { onSelect(agg) }
      }
    } label: {
      HStack(spacing: 0) {
        Text(aggregation.rawValue)
          .font(AppTypography.labelMedium)
          .foregroundStyle(colors.onSurfaceVariant)
        Image(systemName: "chevron.down")
          .font(.system(size: 14))
          .foregroundStyle(colors.onSurfaceVariant)
      }
      .padding(.leading, 8)
      .frame(height: 24)
      .background(colors.surfaceContainerLowest)
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(colors.outlineVariant, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
  }
}

// MARK: - FilterChipView

private struct FilterChipView: View {
  let label: String
  let selected: Bool
  let onTap: () -> Void

  @Environment(\.galleryColors) private var colors

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 4) {
        if selected {
          Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .bold))
            .offset(x: 2)
        }
        Text(label)
          .font(AppTypography.labelSmall)
      }
      .padding(.horizontal, 8)
      .frame(height: 24)
      .background(selected ? colors.secondaryContainer : colors.surfaceContainer)
      .foregroundStyle(selected ? colors.onSecondaryContainer : colors.onSurfaceVariant)
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
  }
}

// MARK: - CSV export

private func getBenchmarkResultCsv(llmResult: LlmBenchmarkResult, aggregation: Aggregation) -> String {
  let bi = llmResult.basicInfo
  let s = llmResult.stats
  let header = ["start time (ms)", "end time (ms)", "model name", "accelerator",
                "prefill tokens count", "decode tokens count", "runs count", "app version",
                "prefill speed (tokens/sec)", "decode speed (tokens/sec)",
                "time to first token (sec)", "first init time (ms)", "steady init time (ms)"]
    .joined(separator: ",")
  let data: [String] = [
    "\(bi.startMs)", "\(bi.endMs)", bi.modelName, bi.accelerator,
    "\(bi.prefillTokens)", "\(bi.decodeTokens)", "\(bi.numberOfRuns)", bi.appVersion,
    "\(getAggregationValue(valueSeries: s.prefillSpeed, aggregation: aggregation))",
    "\(getAggregationValue(valueSeries: s.decodeSpeed, aggregation: aggregation))",
    "\(getAggregationValue(valueSeries: s.timeToFirstToken, aggregation: aggregation))",
    "\(s.firstInitTimeMs)",
    "\(getAggregationValue(valueSeries: s.nonFirstInitTimeMs, aggregation: aggregation))"
  ]
  return "\(header)\n\(data.joined(separator: ","))"
}

// MARK: - Helpers

private func formatMs(_ ms: Int64) -> String {
  let date = Date(timeIntervalSince1970: Double(ms) / 1000)
  let fmt = DateFormatter()
  fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
  return fmt.string(from: date)
}

extension Array where Element: Hashable {
  func unique() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
