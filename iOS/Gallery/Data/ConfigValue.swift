/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of data/ConfigValue.kt

import Foundation

/// A type-erased configuration value. Mirrors the Kotlin `sealed class ConfigValue`.
enum ConfigValue {
  case intValue(Int)
  case floatValue(Float)
  case stringValue(String)
}

func getIntConfigValue(_ configValue: ConfigValue?, default def: Int) -> Int {
  guard let configValue else { return def }
  switch configValue {
  case .intValue(let v): return v
  case .floatValue(let v): return Int(v)
  case .stringValue: return 0
  }
}

func getFloatConfigValue(_ configValue: ConfigValue?, default def: Float) -> Float {
  guard let configValue else { return def }
  switch configValue {
  case .intValue(let v): return Float(v)
  case .floatValue(let v): return v
  case .stringValue: return 0
  }
}

func getStringConfigValue(_ configValue: ConfigValue?, default def: String) -> String {
  guard let configValue else { return def }
  switch configValue {
  case .intValue(let v): return "\(v)"
  case .floatValue(let v): return "\(v)"
  case .stringValue(let v): return v
  }
}
