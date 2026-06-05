// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/benchmark/BenchmarkViewModel.kt

import Foundation
import Combine

private let TAG = "AGBenchmarkVM"

enum Aggregation: String, CaseIterable {
  case avg    = "avg"
  case median = "median"
  case min    = "min"
  case max    = "max"
}

struct BenchmarkResultInfo: Identifiable {
  let id: String
  var benchmarkResult: BenchmarkResult
  var expanded: Bool = false
  var basicInfoExpanded: Bool = true
  var statsExpanded: Bool = true
  var aggregation: Aggregation = .avg
}

struct BenchmarkUiState {
  var results: [BenchmarkResultInfo] = []
  var baselineResult: BenchmarkResultInfo? = nil
  var showResultsViewer: Bool = false
  var running: Bool = false
  var totalRunCount: Int = 0
  var completedRunCount: Int = 0
}

@MainActor
final class BenchmarkViewModel: ObservableObject {
  @Published private(set) var uiState = BenchmarkUiState()

  let dataStoreRepository: DataStoreRepository

  init(dataStoreRepository: DataStoreRepository) {
    self.dataStoreRepository = dataStoreRepository
    // Load persisted results
    let stored = dataStoreRepository.getAllBenchmarkResults()
    setBenchmarkResults(results: stored)
    collapseAll()
  }

  // MARK: - Benchmark execution

  /// Runs the benchmark for `model` with the given configuration.
  /// NOTE: LiteRT-LM `benchmark()` API is not available on iOS. The loop below
  /// is a stub that records zero values. Replace with the actual iOS SDK call
  /// when available.
  func runBenchmark(model: Model, accelerator: String, prefillTokens: Int,
                    decodeTokens: Int, runCount: Int) {
    Task { @MainActor in
      setRunning(true)
      setRunProgress(0)
      setTotalRunCount(runCount)
      setShowResultsViewer(true)

      let startMs = currentTimeMillis()
      var prefillSpeeds: [Double] = []
      var decodeSpeeds: [Double] = []
      var timesToFirstToken: [Double] = []
      var firstInitTime = 0.0
      var nonFirstInitTimes: [Double] = []

      // NOTE: Real inference via LlmModelHelper is bridged here.
      // For now stub each run with zero stats to keep the UI wirable.
      for i in 0..<runCount {
        // NOTE: replace with await llmModelHelper.benchmark(...)
        let prefill = 0.0
        let decode = 0.0
        let ttft = 0.0
        let initTimeMs = 0.0

        if i == 0 { firstInitTime = initTimeMs } else { nonFirstInitTimes.append(initTimeMs) }
        prefillSpeeds.append(prefill)
        decodeSpeeds.append(decode)
        timesToFirstToken.append(ttft)
        setRunProgress(i + 1)
      }

      let endMs = currentTimeMillis()

      let basicInfo = LlmBenchmarkBasicInfo(
        startMs: startMs, endMs: endMs,
        modelName: model.name, accelerator: accelerator,
        prefillTokens: Int32(prefillTokens), decodeTokens: Int32(decodeTokens),
        numberOfRuns: Int32(runCount),
        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
      )
      let stats = LlmBenchmarkStats(
        prefillSpeed: calculateValueSeries(prefillSpeeds),
        decodeSpeed: calculateValueSeries(decodeSpeeds),
        timeToFirstToken: calculateValueSeries(timesToFirstToken),
        firstInitTimeMs: firstInitTime,
        nonFirstInitTimeMs: calculateValueSeries(nonFirstInitTimes)
      )
      let result = BenchmarkResult(
        llmResult: LlmBenchmarkResult(basicInfo: basicInfo, stats: stats)
      )
      let newId = addBenchmarkResult(result)
      collapseAll()
      setExpanded(id: newId, expanded: true)
      setRunning(false)
    }
  }

  // MARK: - State mutations

  func setShowResultsViewer(_ show: Bool) {
    uiState.showResultsViewer = show
  }

  func setRunning(_ running: Bool) {
    uiState.running = running
  }

  func setTotalRunCount(_ count: Int) {
    uiState.totalRunCount = count
  }

  func setRunProgress(_ completed: Int) {
    uiState.completedRunCount = completed
  }

  @discardableResult
  func addBenchmarkResult(_ result: BenchmarkResult) -> String {
    var updated = uiState.results
    let newId = UUID().uuidString
    updated.insert(BenchmarkResultInfo(
      id: newId,
      benchmarkResult: result,
      basicInfoExpanded: true,
      statsExpanded: true
    ), at: 0)
    uiState.results = updated
    dataStoreRepository.addBenchmarkResult(result)
    return newId
  }

  func setBenchmarkResults(results: [BenchmarkResult]) {
    uiState.results = results.map {
      BenchmarkResultInfo(
        id: UUID().uuidString,
        benchmarkResult: $0,
        expanded: false,
        basicInfoExpanded: false,
        statsExpanded: true
      )
    }
  }

  func deleteBenchmarkResult(id: String) {
    var updated = uiState.results
    guard let idx = updated.firstIndex(where: { $0.id == id }) else { return }
    updated.remove(at: idx)
    uiState.results = updated
    if uiState.baselineResult?.id == id { uiState.baselineResult = nil }
    dataStoreRepository.deleteBenchmarkResult(index: idx)
  }

  func setBaseline(id: String) {
    if id == uiState.baselineResult?.id {
      clearBaseline()
    } else if let r = uiState.results.first(where: { $0.id == id }) {
      uiState.baselineResult = r
    }
  }

  func clearBaseline() { uiState.baselineResult = nil }

  func setExpanded(id: String, expanded: Bool) {
    guard let idx = uiState.results.firstIndex(where: { $0.id == id }) else { return }
    uiState.results[idx].expanded = expanded
    uiState.results[idx].basicInfoExpanded = expanded
    uiState.results[idx].statsExpanded = expanded
  }

  func setBasicInfoExpanded(id: String, expanded: Bool) {
    guard let idx = uiState.results.firstIndex(where: { $0.id == id }) else { return }
    uiState.results[idx].basicInfoExpanded = expanded
  }

  func setStatsExpanded(id: String, expanded: Bool) {
    guard let idx = uiState.results.firstIndex(where: { $0.id == id }) else { return }
    uiState.results[idx].statsExpanded = expanded
  }

  func expandAll() {
    for i in uiState.results.indices {
      uiState.results[i].expanded = true
      uiState.results[i].basicInfoExpanded = true
      uiState.results[i].statsExpanded = true
    }
  }

  func collapseAll() {
    for i in uiState.results.indices {
      uiState.results[i].expanded = false
      uiState.results[i].basicInfoExpanded = false
      uiState.results[i].statsExpanded = false
    }
  }

  func setAggregation(id: String, aggregation: Aggregation) {
    guard let idx = uiState.results.firstIndex(where: { $0.id == id }) else { return }
    uiState.results[idx].aggregation = aggregation
    if uiState.baselineResult?.id == id { uiState.baselineResult = uiState.results[idx] }
  }

  // MARK: - Stats helpers

  private func calculateValueSeries(_ values: [Double]) -> ValueSeries {
    guard !values.isEmpty else { return ValueSeries() }
    let sorted = values.sorted()
    let size = sorted.count
    let min = sorted.first!
    let max = sorted.last!
    let avg = values.reduce(0, +) / Double(values.count)
    func percentile(_ p: Double) -> Double {
      if size == 1 { return sorted[0] }
      let index = p * Double(size - 1)
      let lower = Int(index.rounded(.down))
      let upper = Int(index.rounded(.up))
      if lower == upper { return sorted[lower] }
      let weight = index - Double(lower)
      return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
    return ValueSeries(
      value: values,
      min: min, max: max, avg: avg,
      medium: percentile(0.5),
      pct25: percentile(0.25),
      pct75: percentile(0.75)
    )
  }
}

// MARK: - Aggregation value accessor

func getAggregationValue(valueSeries: ValueSeries, aggregation: Aggregation) -> Double {
  switch aggregation {
  case .avg:    return valueSeries.avg
  case .median: return valueSeries.medium
  case .min:    return valueSeries.min
  case .max:    return valueSeries.max
  }
}
