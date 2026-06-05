/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/ModelNotDownloaded.kt

import SwiftUI

struct ModelNotDownloaded: View {
  var onClicked: () -> Void = {}

  var body: some View {
    VStack {
      Spacer()
      Button(action: onClicked) {
        Text("다운로드 및 체험하기")
          .lineLimit(1)
      }
      .buttonStyle(.borderedProminent)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}
