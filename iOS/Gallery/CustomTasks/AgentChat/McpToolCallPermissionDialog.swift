// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/McpToolCallPermissionDialog.kt

import SwiftUI

/// A dialog that prompts the user for permission to execute an MCP tool call.
struct McpToolCallPermissionDialog: View {
    let toolName: String
    let argument: String
    let onResult: (PermissionResult) -> Void

    @Environment(\.galleryColors) var colors

    private var formattedArgument: String {
        guard let data = argument.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let str = String(data: pretty, encoding: .utf8) else { return argument }
        return str
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(Str.mcpToolCallPermissionTitle)
                    .font(AppTypography.titleLarge)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(Str.mcpToolNameLabel).font(AppTypography.labelMedium).fontWeight(.bold)
                    Text(toolName).font(AppTypography.bodySmall)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(Str.mcpToolInputLabel).font(AppTypography.labelMedium).fontWeight(.bold)
                    Text(formattedArgument)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(colors.onSurface)
                }

                VStack(spacing: 8) {
                    Button(Str.mcpToolAlwaysAllow) { onResult(.alwaysAllow) }
                        .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    Button(Str.mcpToolAllowOnce) { onResult(.allowOnce) }
                        .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    Button(Str.mcpToolDontAllow) { onResult(.deny) }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
