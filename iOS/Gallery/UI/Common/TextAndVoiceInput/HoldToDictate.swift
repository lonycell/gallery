/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/textandvoiceinput/HoldToDictate.kt

import SwiftUI
import Speech

/// A "hold to dictate" button. Press and hold to record; release to stop.
/// Mirrors `HoldToDictate` composable.
struct HoldToDictate: View {
  let task: Task
  let viewModel: HoldToDictateViewModel
  let onDone: (String) -> Void
  let onAmplitudeChanged: (Int) -> Void
  let enabled: Bool

  @State private var permissionGranted: Bool = false
  @GestureState private var isPressing: Bool = false

  @Environment(\.customColors) private var customColors

  private var bgColor: Color {
    getTaskBgGradientColors(task: task, customColors: customColors)[1]
  }

  var body: some View {
    Group {
      if permissionGranted {
        ZStack {
          Capsule()
            .fill(bgColor)
            .opacity(enabled ? 1.0 : 0.5)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .overlay(
              Text(viewModel.uiState.recognizing ? Str.listening : Str.holdDownToTalk)
                .font(AppTypography.bodyMedium)
                .foregroundStyle(.white)
            )
        }
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { _ in
              guard enabled, !viewModel.uiState.recognizing else { return }
              viewModel.startSpeechRecognition(
                onDone: onDone,
                onAmplitudeChanged: onAmplitudeChanged
              )
            }
            .onEnded { value in
              // Slide up to cancel: if finger moved significantly upward, cancel.
              if value.translation.height < -50 {
                viewModel.cancelSpeechRecognition()
              } else {
                viewModel.stopSpeechRecognition()
              }
            }
        )
        .disabled(!enabled)
      } else {
        Text(Str.grantRecordAudioPermission)
          .font(AppTypography.bodyMedium)
          .foregroundStyle(.white)
          .padding(.horizontal, 16)
          .frame(maxWidth: .infinity, minHeight: 48)
          .background(bgColor.opacity(0.5), in: Capsule())
      }
    }
    .task { await requestMicPermission() }
  }

  private func requestMicPermission() async {
    let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
      SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
    }
    await MainActor.run {
      permissionGranted = (status == .authorized)
    }
  }
}
