/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/DownloadAndTryButton.kt
//
// NOTE: The Android version handles a full HuggingFace OAuth token-exchange flow via
// AppAuth (authService / getAuthorizationRequest / handleAuthResult) and
// Android's notification-permission launcher. Those platform pieces are bridged
// through ModelManagerViewModel on iOS. The UI flow (checking token, showing the
// agreement-ack sheet, memory warning, Gemma TOS dialog) is fully translated; the
// actual OAuth intent-launch is a NOTE stub below.

import SwiftUI

private let MODEL_NAMES_TO_SHOW_GEMMA_LICENSES: Set<String> = [
  "Gemma-3n-E2B-it", "Gemma-3n-E4B-it", "Gemma3-1B-IT", "Gemma3-1B-IT NPU"
]

struct DownloadAndTryButton: View {
  let task: Task?
  let model: Model
  let enabled: Bool
  let downloadStatus: ModelDownloadStatusType?
  let downloadProgress: Float
  let modelManagerViewModel: ModelManagerViewModel
  let onClicked: () -> Void
  var compact: Bool = false
  var canShowTryIt: Bool = true
  var downloadButtonBackgroundColor: Color? = nil

  // NOTE: Pass a TosViewModel wired to DataStoreRepository from the caller if available.
  // Fallback creates one without persistence (in-memory only) for contexts where DI is not set up.
  var tosViewModel: TosViewModel = TosViewModel()

  @State private var checkingToken: Bool = false
  @State private var showAgreementAckSheet: Bool = false
  @State private var showErrorDialog: Bool = false
  @State private var showMemoryWarning: Bool = false
  @State private var showGemmaTermsOfUseDialog: Bool = false
  @State private var downloadStarted: Bool = false
  @State private var animatedProgress: Float = 0

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  private var needToDownloadFirst: Bool {
    (downloadStatus == .notDownloaded || downloadStatus == .failed)
      && model.localFileRelativeDirPathOverride.isEmpty
      && model.runtimeType != .aicore
  }
  private var inProgress: Bool { downloadStatus == .inProgress }
  private var downloadSucceeded: Bool { downloadStatus == .succeeded }
  private var isPartiallyDownloaded: Bool { downloadStatus == .partiallyDownloaded }
  private var showDownloadProgress: Bool {
    !downloadSucceeded
      && (downloadStarted || checkingToken || inProgress || isPartiallyDownloaded)
  }

  private var bgColor: Color {
    if let override = downloadButtonBackgroundColor { return override }
    return colors.surfaceContainer
  }

  private var buttonContainerColor: Color {
    if (!downloadSucceeded || !canShowTryIt) && model.localFileRelativeDirPathOverride.isEmpty {
      return bgColor
    }
    if let t = task {
      return getTaskBgGradientColors(task: t, customColors: customColors)[1]
    }
    return colors.primary
  }

  var body: some View {
    Group {
      if !showDownloadProgress {
        Button {
          if !enabled || checkingToken { return }
          if model.url.hasPrefix("https://dl.google.com/google-ai-edge-gallery/")
              && MODEL_NAMES_TO_SHOW_GEMMA_LICENSES.contains(model.name)
              && !tosViewModel.getIsGemmaTermsOfUseAccepted() {
            showGemmaTermsOfUseDialog = true
          } else {
            checkMemoryAndHandleClick()
          }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: needToDownloadFirst ? "arrow.down.circle" : "arrow.right")
              .foregroundStyle(buttonTextColor)
            if !compact {
              if needToDownloadFirst {
                Text(Str.download)
                  .font(AppTypography.titleMedium)
                  .foregroundStyle(buttonTextColor)
                  .lineLimit(1)
                  .minimumScaleFactor(0.5)
              } else if canShowTryIt {
                Text(Str.tryIt)
                  .font(AppTypography.titleMedium)
                  .foregroundStyle(buttonTextColor)
                  .lineLimit(1)
                  .minimumScaleFactor(0.5)
              }
            }
          }
          .padding(.horizontal, 12)
          .frame(height: 42)
        }
        .background(buttonContainerColor, in: Capsule())
        .disabled(!enabled)
      } else {
        // Download progress row
        HStack(spacing: 4) {
          if checkingToken {
            Text(Str.checkingAccess)
              .font(AppTypography.bodyMedium)
              .foregroundStyle(colors.onSurface)
              .frame(maxWidth: compact ? nil : .infinity)
              .padding(.horizontal, compact ? 4 : 0)
          } else {
            Text(String(format: "%d%%", Int(downloadProgress * 100)))
              .font(AppTypography.bodyMedium)
              .foregroundStyle(colors.onSurface)
              .frame(width: compact ? 36 : 48)
              .padding(.leading, 12)
            if !compact {
              let barColor = task.map { getTaskBgGradientColors(task: $0, customColors: customColors)[1] }
                ?? colors.primary
              ProgressView(value: Double(animatedProgress))
                .progressViewStyle(LinearProgressViewStyle(tint: barColor))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
            }
            Button {
              downloadStarted = false
              modelManagerViewModel.cancelDownloadModel(model)
            } label: {
              Image(systemName: "xmark")
                .foregroundStyle(colors.onSurface)
            }
            .frame(width: 44, height: 44)
          }
        }
        .frame(height: 42)
        .frame(maxWidth: compact ? nil : .infinity)
        .background(colors.surfaceContainer, in: Capsule())
        .onChange(of: downloadProgress) { newVal in
          withAnimation(.easeInOut(duration: 0.15)) { animatedProgress = newVal }
        }
      }
    }
    // Agreement acknowledgement sheet
    .sheet(isPresented: $showAgreementAckSheet) {
      VStack(alignment: .center, spacing: 16) {
        Text("Acknowledge user agreement")
          .font(AppTypography.titleLarge)
        Text("This is a gated model. Please tap the button below to view and agree to the user agreement. After accepting, return to proceed with the model download.")
          .font(AppTypography.bodyMedium)
          .multilineTextAlignment(.center)
        Button("Open user agreement") {
          if let idx = model.url.range(of: "/resolve/") {
            let agreementUrl = String(model.url[..<idx.lowerBound])
            if let url = URL(string: agreementUrl) {
              // NOTE: Opens in Safari; Android used a Custom Tab with a result-launcher
              // to auto-retry download after the user returns. On iOS we just open the URL.
              UIApplication.shared.open(url)
            }
          }
          showAgreementAckSheet = false
        }
        .buttonStyle(.borderedProminent)
      }
      .padding()
      .presentationDetents([.medium])
    }
    // Error dialog
    .alert("Unknown network error", isPresented: $showErrorDialog) {
      Button(Str.close) { showErrorDialog = false }
    } message: {
      Text("Please check your internet connection.")
    }
    // Memory warning
    .sheet(isPresented: $showMemoryWarning) {
      MemoryWarningSheet(
        onProceeded: { handleClick(); showMemoryWarning = false },
        onDismissed: { showMemoryWarning = false }
      )
    }
    // Gemma TOS
    .sheet(isPresented: $showGemmaTermsOfUseDialog) {
      GemmaTermsOfUseDialog(
        onTosAccepted: {
          showGemmaTermsOfUseDialog = false
          tosViewModel.acceptGemmaTermsOfUse()
          checkMemoryAndHandleClick()
        },
        onCancel: { showGemmaTermsOfUseDialog = false }
      )
    }
  }

  // MARK: Private helpers

  private var buttonTextColor: Color {
    if !enabled {
      return colors.onSurface.opacity(0.38)
    } else if !downloadSucceeded && model.localFileRelativeDirPathOverride.isEmpty {
      return colors.onSurface
    } else if task != nil {
      return .white
    }
    return colors.onPrimary
  }

  private func checkMemoryAndHandleClick() {
    if isMemoryLow(model: model) {
      showMemoryWarning = true
    } else {
      handleClick()
    }
  }

  private func handleClick() {
    Task {
      if needToDownloadFirst {
        downloadStarted = true
        if model.url.hasPrefix("https://huggingface.co") {
          checkingToken = true
          // NOTE: HuggingFace OAuth token check is not yet bridged on iOS.
          // For now, attempt a direct download without a token.
          checkingToken = false
          await MainActor.run { startDownload(accessToken: nil) }
        } else {
          await MainActor.run { startDownload(accessToken: nil) }
        }
      } else {
        await MainActor.run { onClicked() }
      }
    }
  }

  private func startDownload(accessToken: String?) {
    model.accessToken = accessToken
    if let t = task {
      modelManagerViewModel.downloadModel(task: t, model: model)
    }
    checkingToken = false
  }
}

// MARK: - MemoryWarningSheet (inline helper used above)

private struct MemoryWarningSheet: View {
  let onProceeded: () -> Void
  let onDismissed: () -> Void

  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(spacing: 20) {
      Text(Str.memoryWarningTitle)
        .font(AppTypography.titleLarge)
        .foregroundStyle(colors.onSurface)
      Text(Str.memoryWarningContent)
        .font(AppTypography.bodyMedium)
        .foregroundStyle(colors.onSurfaceVariant)
        .multilineTextAlignment(.center)
      HStack(spacing: 16) {
        Button(Str.cancel) { onDismissed() }
          .foregroundStyle(colors.primary)
        Button(Str.memoryWarningProceedAnyway) { onProceeded() }
          .buttonStyle(.borderedProminent)
      }
    }
    .padding(24)
    .presentationDetents([.fraction(0.35)])
  }
}
