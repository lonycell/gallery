/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of data/Config.kt

import Foundation

/// The types of configuration editors available. Mirrors `ConfigEditorType`.
enum ConfigEditorType {
  case label
  case numberSlider
  case booleanSwitch
  case segmentedButton
  case bottomSheetSelector
}

/// The data types of configuration values. Mirrors `ValueType`.
enum ValueType {
  case int
  case float
  case double
  case string
  case boolean
}

struct ConfigKey: Hashable {
  let id: String
  let label: String
}

enum ConfigKeys {
  static let MAX_TOKENS = ConfigKey(id: "max_tokens", label: "Max tokens")
  static let TOPK = ConfigKey(id: "topk", label: "TopK")
  static let TOPP = ConfigKey(id: "topp", label: "TopP")
  static let TEMPERATURE = ConfigKey(id: "temperature", label: "Temperature")
  static let DEFAULT_MAX_TOKENS = ConfigKey(id: "default_max_tokens", label: "Default max tokens")
  static let DEFAULT_TOPK = ConfigKey(id: "default_topk", label: "Default TopK")
  static let DEFAULT_TOPP = ConfigKey(id: "default_topp", label: "Default TopP")
  static let DEFAULT_TEMPERATURE = ConfigKey(id: "default_temperature", label: "Default temperature")
  static let SUPPORT_IMAGE = ConfigKey(id: "support_image", label: "Support image")
  static let SUPPORT_AUDIO = ConfigKey(id: "support_audio", label: "Support audio")
  static let SUPPORT_TINY_GARDEN = ConfigKey(id: "support_tiny_garden", label: "Support tiny garden")
  static let SUPPORT_MOBILE_ACTIONS = ConfigKey(id: "support_mobile_actions", label: "Support mobile actions")
  static let SUPPORT_THINKING = ConfigKey(id: "support_thinking", label: "Support thinking")
  static let SUPPORT_SPECULATIVE_DECODING = ConfigKey(id: "support_speculative_decoding", label: "Support speculative decoding")
  static let ENABLE_THINKING = ConfigKey(id: "enable_thinking", label: "Enable thinking")
  static let ENABLE_SPECULATIVE_DECODING = ConfigKey(id: "enable_speculative_decoding", label: "Enable speculative decoding")
  static let MAX_RESULT_COUNT = ConfigKey(id: "max_result_count", label: "Max result count")
  static let USE_GPU = ConfigKey(id: "use_gpu", label: "Use GPU")
  static let ACCELERATOR = ConfigKey(id: "accelerator", label: "Accelerator")
  static let VISION_ACCELERATOR = ConfigKey(id: "vision_accelerator", label: "Vision accelerator")
  static let COMPATIBLE_ACCELERATORS = ConfigKey(id: "compatible_accelerators", label: "Compatible accelerators")
  static let WARM_UP_ITERATIONS = ConfigKey(id: "warm_up_iterations", label: "Warm up iterations")
  static let BENCHMARK_ITERATIONS = ConfigKey(id: "benchmark_iterations", label: "Benchmark iterations")
  static let ITERATIONS = ConfigKey(id: "iterations", label: "Iterations")
  static let THEME = ConfigKey(id: "theme", label: "Theme")
  static let NAME = ConfigKey(id: "name", label: "Name")
  static let MODEL_TYPE = ConfigKey(id: "model_type", label: "Model type")
  static let MODEL = ConfigKey(id: "model", label: "Model")
  static let RESET_CONVERSATION_TURN_COUNT = ConfigKey(id: "reset_conversation_turn_count", label: "Number of turns before the conversation resets")
  static let PREFILL_TOKENS = ConfigKey(id: "prefill_tokens", label: "Prefill tokens")
  static let DECODE_TOKENS = ConfigKey(id: "decode_tokens", label: "Decode tokens")
  static let NUMBER_OF_RUNS = ConfigKey(id: "number_of_runs", label: "Number of runs")
}

/// Base class for configuration settings. Mirrors `open class Config`.
class Config {
  let type: ConfigEditorType
  let key: ConfigKey
  let defaultValue: Any
  let valueType: ValueType
  /// Changes to configs with this flag set automatically trigger model re-init.
  let needReinitialization: Bool

  init(type: ConfigEditorType, key: ConfigKey, defaultValue: Any, valueType: ValueType, needReinitialization: Bool = true) {
    self.type = type
    self.key = key
    self.defaultValue = defaultValue
    self.valueType = valueType
    self.needReinitialization = needReinitialization
  }
}

final class LabelConfig: Config {
  init(key: ConfigKey, defaultValue: String = "") {
    super.init(type: .label, key: key, defaultValue: defaultValue, valueType: .string)
  }
}

final class NumberSliderConfig: Config {
  let sliderMin: Float
  let sliderMax: Float
  init(key: ConfigKey, sliderMin: Float, sliderMax: Float, defaultValue: Float,
       valueType: ValueType, needReinitialization: Bool = true) {
    self.sliderMin = sliderMin
    self.sliderMax = sliderMax
    super.init(type: .numberSlider, key: key, defaultValue: defaultValue,
               valueType: valueType, needReinitialization: needReinitialization)
  }
}

final class BooleanSwitchConfig: Config {
  init(key: ConfigKey, defaultValue: Bool, needReinitialization: Bool = true) {
    super.init(type: .booleanSwitch, key: key, defaultValue: defaultValue,
               valueType: .boolean, needReinitialization: needReinitialization)
  }
}

final class SegmentedButtonConfig: Config {
  let options: [String]
  let allowMultiple: Bool
  init(key: ConfigKey, defaultValue: String, options: [String], allowMultiple: Bool = false) {
    self.options = options
    self.allowMultiple = allowMultiple
    // Emitted value is comma-separated labels when allowMultiple == true.
    super.init(type: .segmentedButton, key: key, defaultValue: defaultValue, valueType: .string)
  }
}

struct BottomSheetSelectorItem { let label: String }

final class BottomSheetSelectorConfig: Config {
  let options: [BottomSheetSelectorItem]
  let bottomSheetTitle: String?
  init(key: ConfigKey, defaultValue: String, options: [BottomSheetSelectorItem], bottomSheetTitle: String? = nil) {
    self.options = options
    self.bottomSheetTitle = bottomSheetTitle
    super.init(type: .bottomSheetSelector, key: key, defaultValue: defaultValue, valueType: .string)
  }
}

func convertValueToTargetType(value: Any, valueType: ValueType) -> Any {
  switch valueType {
  case .int:
    switch value {
    case let v as Int: return v
    case let v as Float: return Int(v)
    case let v as Double: return Int(v)
    case let v as String: return Int(v) ?? ""
    case let v as Bool: return v ? 1 : 0
    default: return ""
    }
  case .float:
    switch value {
    case let v as Int: return Float(v)
    case let v as Float: return v
    case let v as Double: return Float(v)
    case let v as String: return Float(v) ?? ""
    case let v as Bool: return v ? Float(1) : Float(0)
    default: return ""
    }
  case .double:
    switch value {
    case let v as Int: return Double(v)
    case let v as Float: return Double(v)
    case let v as Double: return v
    case let v as String: return Double(v) ?? ""
    case let v as Bool: return v ? 1.0 : 0.0
    default: return ""
    }
  case .boolean:
    switch value {
    case let v as Int: return v == 0
    case let v as Bool: return v
    case let v as Float: return abs(v) > 1e-6
    case let v as Double: return abs(v) > 1e-6
    case let v as String: return !v.isEmpty
    default: return false
    }
  case .string:
    return "\(value)"
  }
}

func createLlmChatConfigs(
  defaultMaxToken: Int = DEFAULT_MAX_TOKEN,
  defaultMaxContextLength: Int? = nil,
  defaultTopK: Int = DEFAULT_TOPK,
  defaultTopP: Float = DEFAULT_TOPP,
  defaultTemperature: Float = DEFAULT_TEMPERATURE,
  accelerators: [Accelerator] = DEFAULT_ACCELERATORS,
  supportThinking: Bool = false,
  supportSpeculativeDecoding: Bool = false
) -> [Config] {
  var maxTokensConfig: Config = LabelConfig(key: ConfigKeys.MAX_TOKENS, defaultValue: "\(defaultMaxToken)")
  if let ctx = defaultMaxContextLength {
    maxTokensConfig = NumberSliderConfig(
      key: ConfigKeys.MAX_TOKENS, sliderMin: 2000, sliderMax: Float(ctx),
      defaultValue: Float(defaultMaxToken), valueType: .int)
  }
  var configs: [Config] = [
    maxTokensConfig,
    NumberSliderConfig(key: ConfigKeys.TOPK, sliderMin: 5, sliderMax: 100,
                       defaultValue: Float(defaultTopK), valueType: .int),
    NumberSliderConfig(key: ConfigKeys.TOPP, sliderMin: 0.0, sliderMax: 1.0,
                       defaultValue: defaultTopP, valueType: .float),
    NumberSliderConfig(key: ConfigKeys.TEMPERATURE, sliderMin: 0.0, sliderMax: 2.0,
                       defaultValue: defaultTemperature, valueType: .float),
    SegmentedButtonConfig(key: ConfigKeys.ACCELERATOR, defaultValue: accelerators[0].label,
                          options: accelerators.map { $0.label }),
  ]
  if supportThinking {
    configs.append(BooleanSwitchConfig(key: ConfigKeys.ENABLE_THINKING, defaultValue: false))
  }
  if supportSpeculativeDecoding {
    configs.append(BooleanSwitchConfig(key: ConfigKeys.ENABLE_SPECULATIVE_DECODING, defaultValue: false))
  }
  return configs
}

func createLlmChatConfigsForNpuModel(
  defaultMaxToken: Int = DEFAULT_MAX_TOKEN,
  accelerators: [Accelerator] = DEFAULT_ACCELERATORS
) -> [Config] {
  [
    LabelConfig(key: ConfigKeys.MAX_TOKENS, defaultValue: "\(defaultMaxToken)"),
    SegmentedButtonConfig(key: ConfigKeys.ACCELERATOR, defaultValue: accelerators[0].label,
                          options: accelerators.map { $0.label }),
  ]
}

func createAICoreConfigs(
  defaultMaxToken: Int = DEFAULT_MAX_TOKEN,
  defaultTopK: Int = DEFAULT_TOPK,
  defaultTemperature: Float = DEFAULT_TEMPERATURE,
  accelerators: [Accelerator] = DEFAULT_ACCELERATORS
) -> [Config] {
  [
    LabelConfig(key: ConfigKeys.MAX_TOKENS, defaultValue: "\(defaultMaxToken)"),
    NumberSliderConfig(key: ConfigKeys.TOPK, sliderMin: 5, sliderMax: 100,
                       defaultValue: Float(defaultTopK), valueType: .int),
    NumberSliderConfig(key: ConfigKeys.TEMPERATURE, sliderMin: 0.0, sliderMax: 1.0,
                       defaultValue: defaultTemperature, valueType: .float),
    SegmentedButtonConfig(key: ConfigKeys.ACCELERATOR, defaultValue: accelerators[0].label,
                          options: accelerators.map { $0.label }),
  ]
}

func getConfigValueString(value: Any, config: Config) -> String {
  if config.valueType == .float {
    return String(format: "%.2f", (value as? Float) ?? Float("\(value)") ?? 0)
  }
  return "\(value)"
}
