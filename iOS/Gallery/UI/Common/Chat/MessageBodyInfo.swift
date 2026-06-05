/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyInfo.kt

import SwiftUI

struct MessageBodyInfo: View {
  let message: ChatMessageInfo
  var smallFontSize: Bool = true

  @Environment(\.customColors) private var customColors

  var body: some View {
    HStack {
      Spacer()
      Text(message.content)
        .font(smallFontSize ? .caption : .body)
        .padding(12)
        .background(customColors.agentBubbleBgColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
      Spacer()
    }
  }
}
