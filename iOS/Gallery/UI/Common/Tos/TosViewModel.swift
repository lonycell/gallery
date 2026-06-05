/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/tos/TosViewModel.kt

import Foundation
import Combine

/// ViewModel for Terms of Service state. Mirrors `TosViewModel`.
@MainActor
final class TosViewModel: ObservableObject {
  @Published private(set) var isTosAccepted: Bool = false
  @Published private(set) var isGemmaTermsAccepted: Bool = false

  private var dataStoreRepository: DataStoreRepository?

  init(dataStoreRepository: DataStoreRepository? = nil) {
    self.dataStoreRepository = dataStoreRepository
    if let repo = dataStoreRepository {
      isTosAccepted = repo.isTosAccepted()
      isGemmaTermsAccepted = repo.isGemmaTermsOfUseAccepted()
    }
  }

  func getIsTosAccepted() -> Bool {
    dataStoreRepository?.isTosAccepted() ?? isTosAccepted
  }

  func acceptTos() {
    dataStoreRepository?.acceptTos()
    isTosAccepted = true
  }

  func getIsGemmaTermsOfUseAccepted() -> Bool {
    dataStoreRepository?.isGemmaTermsOfUseAccepted() ?? isGemmaTermsAccepted
  }

  func acceptGemmaTermsOfUse() {
    dataStoreRepository?.acceptGemmaTermsOfUse()
    isGemmaTermsAccepted = true
  }
}
