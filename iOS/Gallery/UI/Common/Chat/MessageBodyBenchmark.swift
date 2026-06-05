/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyBenchmark.kt

import SwiftUI

private let HISTOGRAM_BAR_HEIGHT: CGFloat = 50

struct MessageBodyBenchmark: View {
  let message: ChatMessageBenchmarkResult

  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Data cards row
      HStack {
        ForEach(message.orderedStats, id: \.id) { stat in
          DataCard(
            label: stat.label,
            value: message.statValues[stat.id],
            unit: stat.unit,
            highlight: stat.id == message.highlightStat,
            showPlaceholder: message.isWarmingUp()
          )
          Spacer()
        }
      }

      // Histogram
      if !message.histogram.buckets.isEmpty {
        HStack(alignment: .bottom, spacing: 2) {
          ForEach(Array(message.histogram.buckets.enumerated()), id: \.offset) { index, count in
            let isHighlight = index == message.histogram.highlightBucketIndex
            let alpha: Double = {
              if isHighlight { return 0.8 }
              return count != 0 ? 0.5 : 0.3
            }()
            let barColor: Color = isHighlight ? colors.primary : colors.onSurfaceVariant

            let barH: CGFloat = {
              let maxC = message.histogram.maxCount
              if maxC == 0 { return 1 }
              return max(1, CGFloat(count) / CGFloat(maxC) * HISTOGRAM_BAR_HEIGHT)
            }()

            RoundedRectangle(cornerRadius: 2)
              .fill(barColor.opacity(alpha))
              .frame(width: 4, height: barH)
          }
        }
        .frame(height: HISTOGRAM_BAR_HEIGHT)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity)
  }
}
