/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/MemoryWarning.kt

import SwiftUI

/// Alert dialog shown when device memory is lower than the model requires.
/// Mirrors `MemoryWarningAlert`.
struct MemoryWarningAlert: ViewModifier {
  @Binding var isPresented: Bool
  let onProceeded: () -> Void
  let onDismissed: () -> Void

  func body(content: Content) -> some View {
    content
      .alert("메모리 부족 경고", isPresented: $isPresented) {
        Button("그래도 계속", role: .destructive, action: {
          onProceeded()
          isPresented = false
        })
        Button("취소", role: .cancel, action: {
          onDismissed()
          isPresented = false
        })
      } message: {
        Text("이 모델을 실행하기 위한 메모리가 충분하지 않을 수 있습니다.")
      }
  }
}

extension View {
  func memoryWarningAlert(
    isPresented: Binding<Bool>,
    onProceeded: @escaping () -> Void,
    onDismissed: @escaping () -> Void
  ) -> some View {
    self.modifier(MemoryWarningAlert(
      isPresented: isPresented,
      onProceeded: onProceeded,
      onDismissed: onDismissed
    ))
  }
}
