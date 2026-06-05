/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of proto/settings.proto -> Codable Swift structs.
// The Android app persisted these via DataStore<proto>; on iOS the
// DataStoreRepository persists the Codable equivalents as JSON in the app's
// Application Support directory.

import Foundation

enum Theme: String, Codable {
  case themeUnspecified = "THEME_UNSPECIFIED"
  case themeLight = "THEME_LIGHT"
  case themeDark = "THEME_DARK"
  case themeAuto = "THEME_AUTO"
}

struct AccessTokenData: Codable {
  var accessToken: String = ""
  var refreshToken: String = ""
  var expiresAtMs: Int64 = 0
}

struct LlmConfig: Codable {
  var compatibleAccelerators: [String] = []
  var defaultMaxTokens: Int = 0
  var defaultTopk: Int = 0
  var defaultTopp: Float = 0
  var defaultTemperature: Float = 0
  var supportImage: Bool = false
  var supportAudio: Bool = false
  var supportTinyGarden: Bool = false
  var supportMobileActions: Bool = false
  var supportThinking: Bool = false
  var supportSpeculativeDecoding: Bool = false
}

struct ImportedModel: Codable {
  var fileName: String = ""
  var fileSize: Int64 = 0
  var llmConfig: LlmConfig? = nil
}

struct Settings: Codable {
  var theme: Theme = .themeAuto
  var textInputHistory: [String] = []
  var importedModel: [ImportedModel] = []
  var isTosAccepted: Bool = false
  var hasRunTinyGarden: Bool = false
  var hasSeenBenchmarkComparisonHelp: Bool = false
  var isGemmaTermsAccepted: Bool = false
  var featureFlags: [String: Bool] = [:]
  var viewedPromoId: [String] = []

  static let defaultInstance = Settings()
}

struct McpAuth: Codable {
  enum Method: Codable {
    case none
    case requestHeader(headerName: String, headerValue: String)
    case oauth
  }
  var method: Method = .none
}

struct UserData: Codable {
  var accessTokenData: AccessTokenData? = nil
  var secrets: [String: String] = [:]
  var chatSessions: [ChatSessionProto] = []
  var mcpAuths: [String: McpAuth] = [:]

  static let defaultInstance = UserData()
}

// MARK: - Scrapbook cutout types (proto: FillMode/Point/StrokePath/Cutout/CutoutCollection)

enum FillMode: String, Codable {
  case unspecified = "FILL_MODE_UNSPECIFIED"
  case disabled = "FILL_MODE_DISABLED"
  case solid = "FILL_MODE_SOLID"
  case colorize = "FILL_MODE_COLORIZE"
}

struct ProtoPoint: Codable { var x: Float = 0; var y: Float = 0 }

struct StrokePath: Codable {
  var point: [ProtoPoint] = []
  var brushColor: Int32 = 0
  var brushSize: Float = 0
  var brushSoftness: Float = 0
  var blurType: Int32 = 0
}

struct Cutout: Codable {
  var id: String = ""
  var rotationDegree: Int32 = 0
  var borderWidth: Int32 = 0
  var borderColor: Int32 = 0
  var fillColor: Int32 = 0
  var fillMode: FillMode = .unspecified
  var doodleStroke: [StrokePath] = []
}

struct CutoutCollection: Codable {
  var cutout: [Cutout] = []
  static let defaultInstance = CutoutCollection()
}
