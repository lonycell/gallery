// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/AddSkillFromLocalImportDialog.kt
//
// NOTE: Android used `OpenDocumentTree` (SAF). On iOS we present a `UIDocumentPickerViewController`
// for folders (requires iOS 16+: `UTType.folder`). The picked URL is security-scoped and passed
// to `SkillManagerViewModel.setImportDirectoryURL` before validation.

import SwiftUI
import UniformTypeIdentifiers

struct AddSkillFromLocalImportDialog: View {
    @ObservedObject var skillManagerViewModel: SkillManagerViewModel
    let onDismissRequest: () -> Void
    let onSuccess: () -> Void

    @State private var showDocumentPicker = false
    @State private var showReplaceConfirmation = false
    @Environment(\.galleryColors) var colors

    var body: some View {
        let uiState = skillManagerViewModel.uiState
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Str.addSkillDialogTitleFromLocalImport).font(AppTypography.titleMedium)
                    Text(Str.addSkillDialogSubtitleFromLocalImport)
                        .font(AppTypography.labelSmall)
                        .foregroundColor(colors.onSurfaceVariant.opacity(0.7))
                }
                .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Str.pickSkillDir).font(AppTypography.labelMedium)
                    HStack(spacing: 8) {
                        Text(uiState.importDirectoryURL?.lastPathComponent ?? NSLocalizedString("No directory selected", comment: ""))
                            .font(AppTypography.bodyMedium)
                            .foregroundColor(uiState.importDirectoryURL == nil ? colors.onSurfaceVariant.opacity(0.7) : colors.onSurface)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(colors.surfaceContainerHigh)
                            .cornerRadius(4)
                        Button(action: { showDocumentPicker = true }) {
                            Image(systemName: "doc.badge.plus")
                        }
                    }
                    if let err = uiState.validationError {
                        Text(err).font(AppTypography.bodySmall).foregroundColor(colors.error)
                    }
                }

                if uiState.validating {
                    HStack { Spacer(); ProgressView().frame(width: 20, height: 20) }
                } else {
                    HStack {
                        Spacer()
                        Button(Str.cancel, action: onDismissRequest).buttonStyle(.bordered)
                        Button(Str.add) {
                            if let url = uiState.importDirectoryURL {
                                if skillManagerViewModel.checkLocalSkillExisted(directoryURL: url) {
                                    showReplaceConfirmation = true
                                } else {
                                    doImport()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(uiState.importDirectoryURL == nil)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(20)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView(onPick: { url in
                skillManagerViewModel.setImportDirectoryURL(url)
                skillManagerViewModel.setValidationError(nil)
            })
        }
        .alert(Str.replaceSkillDialogTitle, isPresented: $showReplaceConfirmation) {
            Button(Str.cancel, role: .cancel) { showReplaceConfirmation = false }
            Button(NSLocalizedString("Replace", comment: "")) { doImport() }
        } message: {
            Text(Str.replaceSkillDialogContent)
        }
    }

    private func doImport() {
        skillManagerViewModel.validateAndAddSkillFromLocalImport(
            onSuccess: { onDismissRequest(); onSuccess() },
            onValidationError: { _ in })
    }
}

// MARK: - DocumentPickerView (UIDocumentPickerViewController wrapper)

private struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker: UIDocumentPickerViewController
        if #available(iOS 16, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
        }
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
