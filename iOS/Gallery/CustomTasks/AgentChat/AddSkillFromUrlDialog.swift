// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/AddSkillFromUrlDialog.kt

import SwiftUI

private let APPROVED_SKILL_HOSTS = ["google-ai-edge.github.io"]

func isSkillHostApproved(_ url: String) -> Bool {
    guard let u = URL(string: url), let host = u.host?.lowercased() else { return false }
    return APPROVED_SKILL_HOSTS.contains { host == $0.lowercased() }
}

struct AddSkillFromUrlDialog: View {
    @ObservedObject var skillManagerViewModel: SkillManagerViewModel
    let onDismissRequest: () -> Void
    let onSuccess: () -> Void

    @State private var urlText = ""
    @State private var showDisclaimerSheet = false
    @Environment(\.galleryColors) var colors

    var body: some View {
        let uiState = skillManagerViewModel.uiState
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(Str.addSkillFromUrlDialogTitle).font(AppTypography.titleMedium).padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(Str.enterSkillUrl).font(AppTypography.labelMedium)
                    TextField("", text: $urlText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: urlText) { _ in skillManagerViewModel.setValidationError(nil) }
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
                            if isSkillHostApproved(urlText) {
                                validateAndAdd(url: urlText)
                            } else {
                                showDisclaimerSheet = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(20)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showDisclaimerSheet) {
            AddSkillDisclaimerDialog(
                onDismiss: { showDisclaimerSheet = false },
                onConfirm: { showDisclaimerSheet = false; validateAndAdd(url: urlText) })
        }
    }

    private func validateAndAdd(url: String) {
        skillManagerViewModel.validateAndAddSkillFromUrl(url: url, onSuccess: {
            onDismissRequest(); onSuccess()
        }, onValidationError: { _ in /* state already updated */ })
    }
}
