/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of proto/benchmark.proto -> Codable Swift structs.

import Foundation

struct ValueSeries: Codable {
  var value: [Double] = []
  var min: Double = 0
  var max: Double = 0
  var avg: Double = 0
  var medium: Double = 0
  var pct25: Double = 0
  var pct75: Double = 0
}

struct LlmBenchmarkBasicInfo: Codable {
  var startMs: Int64 = 0
  var endMs: Int64 = 0
  var modelName: String = ""
  var accelerator: String = ""
  var prefillTokens: Int32 = 0
  var decodeTokens: Int32 = 0
  var numberOfRuns: Int32 = 0
  var appVersion: String = ""
}

struct LlmBenchmarkStats: Codable {
  var prefillSpeed: ValueSeries = ValueSeries()
  var decodeSpeed: ValueSeries = ValueSeries()
  var timeToFirstToken: ValueSeries = ValueSeries()
  var firstInitTimeMs: Double = 0
  var nonFirstInitTimeMs: ValueSeries = ValueSeries()
}

struct LlmBenchmarkResult: Codable {
  var basicInfo: LlmBenchmarkBasicInfo = LlmBenchmarkBasicInfo()
  var stats: LlmBenchmarkStats = LlmBenchmarkStats()
}

struct BenchmarkResult: Codable, Identifiable {
  var id: String = UUID().uuidString
  var llmResult: LlmBenchmarkResult? = nil
}

struct BenchmarkResults: Codable {
  var result: [BenchmarkResult] = []
  static let defaultInstance = BenchmarkResults()
}
