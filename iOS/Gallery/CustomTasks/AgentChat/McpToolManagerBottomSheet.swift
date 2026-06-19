// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/McpToolManagerBottomSheet.kt

import SwiftUI

struct McpToolManagerBottomSheet: View {
    @ObservedObject var mcpManagerViewModel: McpManagerViewModel
    let serverUrl: String
    let onDismiss: () -> Void

    @State private var toolToView: McpTool?
    @State private var toolToRevoke: McpTool?

    @Environment(\.galleryColors) var colors

    private var uiState: McpManagerUiState { mcpManagerViewModel.uiState }
    private var serverState: McpServerState? { uiState.mcpServers.first { $0.mcpServer.url == serverUrl } }

    var body: some View {
        guard let state = serverState else { return AnyView(EmptyView()) }
        let server = state.mcpServer
        return AnyView(
            NavigationStack {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Text(Str.manageTools).font(AppTypography.titleLarge).frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: onDismiss) { Image(systemName: "xmark") }
                    }
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)

                    Text(String(format: Str.mcpServerLabel, server.name.isEmpty ? server.url : server.name))
                        .font(AppTypography.bodyMedium).foregroundColor(colors.onSurfaceVariant)
                        .padding(.horizontal, 16).padding(.bottom, 8)

                    HStack {
                        Text(Str.mcpToolsCount(server.tools.count)).font(AppTypography.labelLarge)
                        Spacer()
                        Button(Str.turnOnAll) { mcpManagerViewModel.setAllMcpToolsEnabled(url: serverUrl, enabled: true) }.buttonStyle(.plain).foregroundColor(colors.primary)
                        Button(Str.turnOffAll) { mcpManagerViewModel.setAllMcpToolsEnabled(url: serverUrl, enabled: false) }.buttonStyle(.plain).foregroundColor(colors.primary)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 8)

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(server.tools) { tool in
                                toolRow(tool, serverUrl: server.url)
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 16)
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .alert(toolToView?.name ?? "", isPresented: Binding(get: { toolToView != nil }, set: { if !$0 { toolToView = nil } })) {
                Button(Str.close) { toolToView = nil }
            } message: {
                if let t = toolToView {
                    Text("\(t.description)\n\n\(formattedSchema(t.inputSchema))")
                }
            }
            .alert(Str.mcpToolRevokePermissionTitle, isPresented: Binding(get: { toolToRevoke != nil }, set: { if !$0 { toolToRevoke = nil } })) {
                Button(Str.cancel, role: .cancel) { toolToRevoke = nil }
                Button(Str.mcpToolRevoke) {
                    if let t = toolToRevoke { mcpManagerViewModel.setMcpToolAlwaysAllow(url: serverUrl, toolName: t.name, alwaysAllow: false) }
                    toolToRevoke = nil
                }
            } message: { Text(Str.mcpToolRevokePermissionContent) }
        )
    }

    private func toolRow(_ tool: McpTool, serverUrl: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.name).font(AppTypography.bodyMedium).fontWeight(.medium)
                    if !tool.description.isEmpty {
                        Text(tool.description).font(AppTypography.bodySmall).foregroundColor(colors.onSurfaceVariant).lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: Binding(
                    get: { tool.enabled },
                    set: { mcpManagerViewModel.setMcpToolEnabled(url: serverUrl, toolName: tool.name, enabled: $0) }))
                .labelsHidden().offset(y: -4)
            }

            HStack(spacing: 8) {
                SmallFilledTonalButton(onClick: { toolToView = tool }, label: Str.view, systemImage: "eye")
                if tool.alwaysAllow {
                    SmallOutlinedButton(onClick: { toolToRevoke = tool }, label: Str.mcpToolRevokePermission, systemImage: "xmark.circle")
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(colors.surfaceContainerLowest)
        .cornerRadius(20)
    }

    private func formattedSchema(_ schema: String) -> String {
        guard let data = schema.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let str = String(data: pretty, encoding: .utf8) else { return schema }
        return str
    }
}

