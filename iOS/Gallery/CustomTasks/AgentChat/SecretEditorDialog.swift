// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/SecretEditorDialog.kt

import SwiftUI

/// An alert-style dialog for entering / viewing a secret (API key / token).
/// Mirrors `SecretEditorDialog` composable.
struct SecretEditorDialog: View {
    let title: String
    let fieldLabel: String
    @Binding var value: String
    let onDone: () -> Void
    let onDismiss: () -> Void

    @State private var passwordVisible = false
    @Environment(\.galleryColors) var colors

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(AppTypography.titleLarge).padding(.top, 8)
                MarkdownText(fieldLabel)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(colors.onSurface)

                HStack {
                    Group {
                        if passwordVisible {
                            TextField("", text: $value)
                        } else {
                            SecureField("", text: $value)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    Button(action: { passwordVisible.toggle() }) {
                        Image(systemName: passwordVisible ? "eye.slash" : "eye")
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }

                HStack {
                    Spacer()
                    Button(Str.cancel, action: onDismiss)
                        .buttonStyle(.bordered)
                    Button(Str.done, action: onDone)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
