// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Port of ui/modelmanager/ModelImportDialog.kt

import SwiftUI
import UniformTypeIdentifiers

// NOTE: iOS file import uses `fileImporter`/`UIDocumentPickerViewController` instead of
// Android's `ActivityResultContracts.StartActivityForResult`. The import copy logic
// (writing to the IMPORTS_DIR) mirrors the Android `importModel()` function.

/// Default LLM accelerators for the import dialog.
private let SUPPORTED_ACCELERATORS = [Accelerator.cpu, Accelerator.gpu, Accelerator.npu]

/// Configuration sheet for importing a local model file.
/// Shows after the user picks a `.task` or `.litertlm` file.
/// Mirrors `ModelImportDialog`.
struct ModelImportDialog: View {
  let fileName: String
  let fileSize: Int64
  let onDismiss: () -> Void
  let onDone: (ImportedModel) -> Void
  var defaultValues: [ConfigKey: Any] = [:]

  @State private var modelName: String
  @State private var defaultMaxTokens: Double = Double(DEFAULT_MAX_TOKEN)
  @State private var defaultTopK: Double = Double(DEFAULT_TOPK)
  @State private var defaultTopP: Double = Double(DEFAULT_TOPP)
  @State private var defaultTemperature: Double = Double(DEFAULT_TEMPERATURE)
  @State private var supportImage = false
  @State private var supportAudio = false
  @State private var supportTinyGarden = false
  @State private var supportMobileActions = false
  @State private var supportThinking = false
  @State private var supportSpeculativeDecoding = false
  @State private var selectedAccelerators: Set<String> = [Accelerator.cpu.label]

  @Environment(\.galleryColors) private var colors

  init(fileName: String, fileSize: Int64,
       onDismiss: @escaping () -> Void, onDone: @escaping (ImportedModel) -> Void,
       defaultValues: [ConfigKey: Any] = [:]) {
    self.fileName = fileName
    self.fileSize = fileSize
    self.onDismiss = onDismiss
    self.onDone = onDone
    self.defaultValues = defaultValues
    _modelName = State(initialValue: ensureValidFileName(fileName))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Model name (read-only label)
          SettingRow(title: ConfigKeys.NAME.label) {
            Text(modelName)
              .font(AppTypography.bodyMedium)
              .foregroundStyle(colors.onSurface)
          }

          SettingRow(title: ConfigKeys.MODEL_TYPE.label) {
            Text("LLM")
              .font(AppTypography.bodyMedium)
              .foregroundStyle(colors.onSurface)
          }

          // Sliders
          SliderRow(title: ConfigKeys.DEFAULT_MAX_TOKENS.label,
                    value: $defaultMaxTokens, range: 100...4096, step: 1)
          SliderRow(title: ConfigKeys.DEFAULT_TOPK.label,
                    value: $defaultTopK, range: 5...40, step: 1)
          SliderRow(title: ConfigKeys.DEFAULT_TOPP.label,
                    value: $defaultTopP, range: 0...1, step: 0.01)
          SliderRow(title: ConfigKeys.DEFAULT_TEMPERATURE.label,
                    value: $defaultTemperature, range: 0...2, step: 0.01)

          // Boolean switches
          Toggle(ConfigKeys.SUPPORT_IMAGE.label, isOn: $supportImage)
          Toggle(ConfigKeys.SUPPORT_AUDIO.label, isOn: $supportAudio)
          Toggle(ConfigKeys.SUPPORT_TINY_GARDEN.label, isOn: $supportTinyGarden)
          Toggle(ConfigKeys.SUPPORT_MOBILE_ACTIONS.label, isOn: $supportMobileActions)
          Toggle(ConfigKeys.SUPPORT_THINKING.label, isOn: $supportThinking)
          Toggle(ConfigKeys.SUPPORT_SPECULATIVE_DECODING.label, isOn: $supportSpeculativeDecoding)

          // Accelerator multi-select
          VStack(alignment: .leading, spacing: 8) {
            Text(ConfigKeys.COMPATIBLE_ACCELERATORS.label)
              .font(AppFont.font(size: 14, weight: .medium))
              .foregroundStyle(colors.onSurface)
            HStack {
              ForEach(SUPPORTED_ACCELERATORS, id: \.label) { accel in
                Button(action: { toggleAccelerator(accel.label) }) {
                  Text(accel.label)
                    .font(AppTypography.labelLarge)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedAccelerators.contains(accel.label)
                                ? colors.primaryContainer : colors.surfaceContainer)
                    .foregroundStyle(selectedAccelerators.contains(accel.label)
                                    ? colors.onPrimaryContainer : colors.onSurfaceVariant)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
              }
            }
          }
        }
        .padding(20)
        .font(AppTypography.bodyMedium)
        .toggleStyle(.switch)
      }
      .navigationTitle("Import Model")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { onDismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Import") { handleImport() }
        }
      }
    }
  }

  private func toggleAccelerator(_ label: String) {
    if selectedAccelerators.contains(label) {
      selectedAccelerators.remove(label)
      if selectedAccelerators.isEmpty { selectedAccelerators.insert(Accelerator.cpu.label) }
    } else {
      selectedAccelerators.insert(label)
    }
  }

  private func handleImport() {
    let llmConfig = LlmConfig(
      compatibleAccelerators: Array(selectedAccelerators),
      defaultMaxTokens: Int(defaultMaxTokens),
      defaultTopk: Int(defaultTopK),
      defaultTopp: Float(defaultTopP),
      defaultTemperature: Float(defaultTemperature),
      supportImage: supportImage,
      supportAudio: supportAudio,
      supportTinyGarden: supportTinyGarden,
      supportMobileActions: supportMobileActions,
      supportThinking: supportThinking,
      supportSpeculativeDecoding: supportSpeculativeDecoding
    )
    let importedModel = ImportedModel(fileName: fileName, fileSize: fileSize, llmConfig: llmConfig)
    onDone(importedModel)
  }
}

// MARK: - ModelImportingDialog

/// Shows progress while copying the file into the app's sandbox.
/// Mirrors `ModelImportingDialog`.
struct ModelImportingDialog: View {
  let sourceURL: URL
  let info: ImportedModel
  let onDismiss: () -> Void
  let onDone: (ImportedModel) -> Void

  @State private var progress: Double = 0
  @State private var errorMessage: String = ""
  @Environment(\.galleryColors) private var colors

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Import Model")
        .font(AppTypography.titleLarge)
        .foregroundStyle(colors.onSurface)
        .padding(.bottom, 8)

      if errorMessage.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(info.fileName) (\(info.fileSize.humanReadableSize()))")
            .font(AppTypography.labelSmall)
            .foregroundStyle(colors.onSurface)
          ProgressView(value: progress)
            .tint(colors.primary)
            .padding(.bottom, 8)
        }
      } else {
        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(colors.error)
          Text(errorMessage)
            .font(AppTypography.labelSmall)
            .foregroundStyle(colors.error)
            .padding(.top, 4)
        }
        HStack {
          Spacer()
          Button("Close") { onDismiss() }
            .buttonStyle(.borderedProminent)
        }
      }
    }
    .padding(20)
    .task {
      await importModel()
    }
    .interactiveDismissDisabled(true)
  }

  private func importModel() async {
    // NOTE: Copy source file into <AppDocuments>/imports/ directory.
    let fm = FileManager.default
    guard let docDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
      errorMessage = "Cannot access app documents directory"; return
    }
    let importsDir = docDir.appendingPathComponent(IMPORTS_DIR)
    if !fm.fileExists(atPath: importsDir.path) {
      try? fm.createDirectory(at: importsDir, withIntermediateDirectories: true)
    }
    let dest = importsDir.appendingPathComponent(info.fileName)

    do {
      if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
      // Stream copy with progress
      let fileSize = info.fileSize
      guard let input = InputStream(url: sourceURL) else {
        errorMessage = "Cannot open source file"; return
      }
      guard let output = OutputStream(url: dest, append: false) else {
        errorMessage = "Cannot create output file"; return
      }
      input.open(); output.open()
      defer { input.close(); output.close() }
      let bufferSize = 65536
      var buffer = [UInt8](repeating: 0, count: bufferSize)
      var copied: Int64 = 0
      var lastReportMs: Int64 = currentTimeMillis()
      while input.hasBytesAvailable {
        let read = input.read(&buffer, maxLength: bufferSize)
        if read <= 0 { break }
        output.write(buffer, maxLength: read)
        copied += Int64(read)
        let now = currentTimeMillis()
        if now - lastReportMs > 200 {
          lastReportMs = now
          let pct = fileSize > 0 ? Double(copied) / Double(fileSize) : 0
          await MainActor.run { progress = pct }
        }
      }
      await MainActor.run { progress = 1.0 }
      onDone(info)
    } catch {
      await MainActor.run { errorMessage = error.localizedDescription }
    }
  }
}

// MARK: - Helper views

private struct SettingRow<Content: View>: View {
  let title: String
  @ViewBuilder let content: () -> Content
  @Environment(\.galleryColors) private var colors
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(AppFont.font(size: 14, weight: .medium))
        .foregroundStyle(colors.onSurface)
      content()
    }
  }
}

private struct SliderRow: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double
  @Environment(\.galleryColors) private var colors
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(title)
          .font(AppFont.font(size: 14, weight: .medium))
          .foregroundStyle(colors.onSurface)
        Spacer()
        Text(step >= 1 ? "\(Int(value))" : String(format: "%.2f", value))
          .font(AppTypography.bodyMedium)
          .foregroundStyle(colors.onSurfaceVariant)
      }
      Slider(value: $value, in: range, step: step)
        .tint(colors.primary)
    }
  }
}
