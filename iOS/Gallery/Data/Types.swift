/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of data/Types.kt

import Foundation

/// Hardware accelerator for running a model. Mirrors `data.Accelerator`.
enum Accelerator: String, CaseIterable, Codable {
  case cpu = "CPU"
  case gpu = "GPU"
  case npu = "NPU"
  case tpu = "TPU"

  var label: String { rawValue }
}
