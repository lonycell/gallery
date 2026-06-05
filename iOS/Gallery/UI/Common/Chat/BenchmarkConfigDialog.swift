/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/BenchmarkConfigDialog.kt

import SwiftUI

struct BenchmarkConfigDialog: View {
  var messageToBenchmark: ChatMessage?
  var onDismissed: () -> Void = {}
  var onBenchmarkClicked: (ChatMessage, Int, Int) -> Void = { _, _, _ in }

  @State private var warmUpIterations: Double = 50
  @State private var benchmarkIterations: Double = 200
  @Environment(\.galleryColors) private var colors

  var body: some View {
    NavigationView {
      Form {
        Section(header: Text("워밍업 반복")) {
          HStack {
            Slider(value: $warmUpIterations, in: 10...200, step: 1)
            Text("\(Int(warmUpIterations))")
              .frame(width: 40, alignment: .trailing)
              .monospacedDigit()
          }
        }
        Section(header: Text("벤치마크 반복")) {
          HStack {
            Slider(value: $benchmarkIterations, in: 50...500, step: 1)
            Text("\(Int(benchmarkIterations))")
              .frame(width: 40, alignment: .trailing)
              .monospacedDigit()
          }
        }
      }
      .navigationTitle("벤치마크 설정")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(Str.cancel) { onDismissed() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("시작") {
            guard let msg = messageToBenchmark else { onDismissed(); return }
            onBenchmarkClicked(msg, Int(warmUpIterations), Int(benchmarkIterations))
            onDismissed()
          }
          .fontWeight(.semibold)
          .foregroundColor(colors.primary)
        }
      }
    }
  }
}
