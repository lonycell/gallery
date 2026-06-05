// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Extension methods on ModelManagerViewModel needed by Home / ModelManager / Benchmark screens.
// These mirror small Android helper methods that were inlined in ViewModels or Activities.

import Foundation

extension ModelManagerViewModel {

  // MARK: - HuggingFace token helpers (SettingsDialog)

  /// Returns the current HF token status and data. Mirrors `getTokenStatusAndData()`.
  func getTokenStatusAndData() -> TokenStatusAndData {
    guard let token = dataStoreRepository.readAccessTokenData() else {
      return TokenStatusAndData(status: .notStored, data: nil)
    }
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let status: TokenStatus = token.expiresAtMs > now ? .notExpired : .expired
    return TokenStatusAndData(status: status, data: token)
  }

  /// Persists a new HF access token. Mirrors `saveAccessToken(...)`.
  func saveAccessToken(accessToken: String, refreshToken: String, expiresAt: Int64) {
    dataStoreRepository.saveAccessTokenData(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt
    )
  }

  /// Clears the stored HF access token. Mirrors `clearAccessToken()`.
  func clearAccessToken() {
    dataStoreRepository.clearAccessTokenData()
  }

  // MARK: - Imported-model management (GlobalModelManager / ModelImportDialog)

  // NOTE: `allowlistModels` is stored on `ModelManagerViewModel` as:
  //   var allowlistModels: [AllowedModel] = []    (internal, not private)
  // It is populated inside `applyAllowlist()` and read here for sort-order in
  // GlobalModelManager. If not yet present in ModelManagerViewModel, add it there.

  /// Registers a newly imported LLM model and rebuilds the task list.
  /// Mirrors `addImportedLlmModel(info:)`.
  func addImportedLlmModel(info: ImportedModel) {
    // Persist
    var stored = dataStoreRepository.readImportedModels()
    stored.append(info)
    dataStoreRepository.saveImportedModels(stored)

    // Rebuild task/model state
    processTasks()
    uiState.modelImportingUpdateTrigger = currentTimeMillis()
  }
}
