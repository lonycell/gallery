/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyBenchmarkLlm.kt

import SwiftUI

struct MessageBodyBenchmarkLlm: View {
  let message: ChatMessageBenchmarkLlmResult

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        ForEach(message.orderedStats, id: \.id) { stat in
          DataCard(label: stat.label, value: message.statValues[stat.id], unit: stat.unit)
          Spacer()
        }
      }
    }
    .padding(12)
  }
}
