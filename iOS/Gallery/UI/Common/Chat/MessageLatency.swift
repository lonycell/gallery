/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageLatency.kt

import SwiftUI

/// Displays human-readable latency for a chat message when available.
struct LatencyText: View {
  let message: ChatMessage

  var body: some View {
    if message.latencyMs >= 0 {
      Text(latencyString(message.latencyMs))
        .font(.caption2)
        .opacity(0.5)
    }
  }
}
