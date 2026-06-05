/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/DataCard.kt

import SwiftUI

/// A small card showing a labelled numeric stat value with an optional unit.
struct DataCard: View {
  let label: String
  let value: Float?
  let unit: String
  var highlight: Bool = false
  var showPlaceholder: Bool = false

  @Environment(\.galleryColors) private var colors

  var body: some View {
    let strValue: String = {
      if showPlaceholder || value == nil { return "-" }
      return String(format: "%.2f", value!)
    }()

    VStack(alignment: .leading, spacing: 0) {
      Text(label)
        .font(.caption2).fontWeight(.medium)
        .opacity(0.8)
      if showPlaceholder {
        Text("-").font(.caption).fontWeight(.medium)
      } else {
        Text(strValue)
          .font(.caption).fontWeight(highlight ? .bold : .medium)
          .foregroundColor(highlight ? colors.primary : .primary)
      }
      if strValue != "-" {
        Text(unit)
          .font(.caption2)
          .opacity(0.5)
          .offset(y: -1)
      }
    }
  }
}
