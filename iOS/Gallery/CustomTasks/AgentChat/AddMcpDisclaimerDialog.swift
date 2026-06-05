// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/AddMcpDisclaimerDialog.kt

import SwiftUI

struct AddMcpDisclaimerDialog: View {
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Str.mcpDisclaimerDialogTitle).font(AppTypography.titleLarge)
            Text(Str.mcpDisclaimerDialogContent).font(AppTypography.bodyMedium)
            HStack {
                Spacer()
                Button(Str.cancel, action: onDismiss).buttonStyle(.bordered)
                Button(Str.disclaimerDialogAgree, action: onConfirm).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
