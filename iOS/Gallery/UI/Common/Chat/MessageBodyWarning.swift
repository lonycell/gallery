/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyWarning.kt

import SwiftUI

struct MessageBodyWarning: View {
  let message: ChatMessageWarning

  @Environment(\.customColors) private var customColors

  var body: some View {
    HStack {
      Spacer()
      Text(message.content)
        .font(.caption)
        .foregroundColor(customColors.warningTextColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(customColors.warningContainerColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
      Spacer()
    }
  }
}
