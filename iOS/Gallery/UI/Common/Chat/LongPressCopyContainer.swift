/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/LongPressCopyContainer.kt

import SwiftUI

/// Wraps content with a long-press gesture that shows a "Copy" context menu.
struct LongPressCopyContainer<Content: View>: View {
  let copyText: String
  var onCopyClicked: (String) -> Void = { _ in }
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .contextMenu {
        Button {
          UIPasteboard.general.string = copyText
          onCopyClicked(copyText)
        } label: {
          Label(Str.copy, systemImage: "doc.on.doc")
        }
      }
  }
}
