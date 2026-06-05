/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyError.kt

import SwiftUI

struct MessageBodyError: View {
  let message: ChatMessageError

  @Environment(\.customColors) private var customColors

  var body: some View {
    HStack {
      Spacer()
      Text(message.content)
        .font(.caption)
        .foregroundColor(customColors.errorTextColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(customColors.errorContainerColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
      Spacer()
    }
  }
}
