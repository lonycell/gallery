/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of data/Categories.kt

import Foundation

/// Basic info about a category (a tab on the home page). Mirrors `CategoryInfo`.
struct CategoryInfo: Hashable {
  let id: String
  /// String label. On Android this came from `labelStringRes` or `label`.
  let label: String?

  init(id: String, label: String? = nil) {
    self.id = id
    self.label = label
  }
}

/// Pre-defined categories. Mirrors `object Category`.
enum Category {
  static let LLM = CategoryInfo(id: "llm", label: Str.categoryLlm)
  static let CLASSICAL_ML = CategoryInfo(id: "classical_ml", label: Str.categoryLlm)
  static let EXPERIMENTAL = CategoryInfo(id: "experimental", label: Str.categoryExperimental)
}
