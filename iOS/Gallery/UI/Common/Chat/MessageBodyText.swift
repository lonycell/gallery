/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyText.kt

import SwiftUI

struct MessageBodyText: View {
  let message: ChatMessageText
  var inProgress: Bool = false
  var horizontalPadding: CGFloat = 12
  var onCopyClicked: (String) -> Void = { _ in }

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  var body: some View {
    if message.side == .user {
      LongPressCopyContainer(copyText: message.content, onCopyClicked: onCopyClicked) {
        Text(message.content)
          .font(.body)
          .foregroundColor(.white)
          .padding(.vertical, 12)
          .padding(.horizontal, horizontalPadding)
          .textSelection(.enabled)
      }
    } else if message.side == .agent {
      // NOTE: Full Markdown rendering would need a third-party library (e.g. MarkdownUI).
      // Using basic Text with textSelection for now; feature parity for plain text responses.
      Text(message.content)
        .font(.body)
        .foregroundColor(colors.onSurface)
        .padding(.vertical, 12)
        .padding(.horizontal, horizontalPadding)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
