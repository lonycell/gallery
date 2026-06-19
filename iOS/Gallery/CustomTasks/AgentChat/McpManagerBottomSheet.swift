// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/McpManagerBottomSheet.kt

import SwiftUI

struct McpManagerBottomSheet: View {
    @ObservedObject var mcpManagerViewModel: McpManagerViewModel
    let onDismiss: (Bool) -> Void  // Bool = selections changed

    @State private var searchQuery = ""
    @State private var showAddDialog = false
    @State private var showDeleteAlert = false
    @State private var serverToDeleteUrl = ""
    @State private var serverForToolsUrl: String?
    @State private var savedSummary = ""

    @Environment(\.galleryColors) var colors
    @Environment(\.customColors) var customColors

    private var uiState: McpManagerUiState { mcpManagerViewModel.uiState }

    private var filteredServers: [McpServerState] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return uiState.mcpServers }
        return uiState.mcpServers.filter { state in
            let s = state.mcpServer
            return s.name.lowercased().contains(q) || s.url.lowercased().contains(q) ||
                s.tools.contains { $0.name.lowercased().contains(q) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if uiState.loadingMcpServer && uiState.mcpServers.isEmpty {
                    ProgressView().padding(.top, 60)
                } else if uiState.mcpServers.isEmpty {
                    emptyView
                } else {
                    serverListView
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { savedSummary = mcpManagerViewModel.getSelectedMcpsAndToolsSummary() }
        .sheet(isPresented: $showAddDialog) {
            AddMcpServerFromUrlDialog(mcpManagerViewModel: mcpManagerViewModel,
                onDismissRequest: { showAddDialog = false },
                onSuccess: { showAddDialog = false })
        }
        .sheet(item: Binding<McpServerStateIdentifiable?>(
            get: { serverForToolsUrl.map { McpServerStateIdentifiable(url: $0) } },
            set: { serverForToolsUrl = $0?.url })) { item in
            McpToolManagerBottomSheet(mcpManagerViewModel: mcpManagerViewModel, serverUrl: item.url,
                onDismiss: { serverForToolsUrl = nil })
        }
        .alert(Str.deleteMcpServerDialogTitle, isPresented: $showDeleteAlert) {
            Button(Str.cancel, role: .cancel) { showDeleteAlert = false }
            Button(Str.delete, role: .destructive) {
                mcpManagerViewModel.removeMcpServer(url: serverToDeleteUrl)
                showDeleteAlert = false
            }
        } message: { Text(Str.deleteMcpServerDialogContent) }
    }

    private var emptyView: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: { onDismiss(false) }) { Image(systemName: "xmark") }.padding(16)
            }
            Spacer()
            VStack(spacing: 16) {
                Button(action: { showAddDialog = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text(Str.addMcpServer)
                    }
                }
                .buttonStyle(.borderedProminent)
                Link(Str.learnMoreAboutMcp, destination: URL(string: "https://github.com/google-ai-edge/gallery/tree/main/mcp")!)
                    .font(AppTypography.bodyMedium)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var serverListView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Str.manageMcpServers).font(AppTypography.titleLarge)
                    Link(Str.learnMoreAboutMcpShort, destination: URL(string: "https://github.com/google-ai-edge/gallery/tree/main/mcp")!)
                        .font(AppTypography.bodyMedium).padding(.top, 4)
                }
                Spacer()
                Button(action: {
                    onDismiss(savedSummary != mcpManagerViewModel.getSelectedMcpsAndToolsSummary())
                }) { Image(systemName: "xmark") }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            // Search + Add
            HStack(spacing: 12) {
                SearchBar(text: $searchQuery, placeholder: Str.searchMcpServer)
                Button(action: { searchQuery = ""; showAddDialog = true }) {
                    Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colors.onPrimary).frame(width: 44, height: 44)
                        .background(colors.primary).clipShape(Circle())
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            if searchQuery.isEmpty {
                HStack {
                    Text(Str.mcpServersCount(uiState.mcpServers.count)).font(AppTypography.labelLarge)
                    Spacer()
                    Button(Str.turnOnAll) { mcpManagerViewModel.setAllMcpServerEnabled(enabled: true) }.buttonStyle(.plain).foregroundColor(colors.primary)
                    Button(Str.turnOffAll) { mcpManagerViewModel.setAllMcpServerEnabled(enabled: false) }.buttonStyle(.plain).foregroundColor(colors.primary)
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }

            // List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredServers) { state in
                        McpServerItemRowView(
                            serverState: state,
                            onEnabledChange: { mcpManagerViewModel.setMcpServerEnabled(url: state.mcpServer.url, enabled: $0) },
                            onToolsClick: { serverForToolsUrl = state.mcpServer.url },
                            onDeleteClick: { serverToDeleteUrl = state.mcpServer.url; showDeleteAlert = true }
                        )
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
    }
}

// MARK: - McpServerItemRow

private struct McpServerItemRowView: View {
    let serverState: McpServerState
    let onEnabledChange: (Bool) -> Void
    let onToolsClick: () -> Void
    let onDeleteClick: () -> Void

    @Environment(\.galleryColors) var colors

    var body: some View {
        let server = serverState.mcpServer
        let hasName = !server.name.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hasName ? server.name : server.url)
                        .font(AppTypography.bodyMedium).fontWeight(.medium)
                    if hasName && !server.version.isEmpty {
                        Text("v\(server.version)").font(AppTypography.bodySmall).foregroundColor(colors.onSurfaceVariant).lineLimit(1)
                    }
                    if hasName {
                        Text(server.url).font(AppTypography.bodySmall).foregroundColor(colors.onSurfaceVariant).lineLimit(1).truncationMode(.middle)
                    }
                    if let err = serverState.error {
                        Text(err).font(AppTypography.bodySmall).foregroundColor(colors.error).lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: Binding(get: { server.enabled }, set: onEnabledChange))
                    .labelsHidden()
                    .disabled(serverState.error != nil)
                    .offset(y: -4)
            }

            HStack(spacing: 8) {
                let enabledCount = server.tools.filter { $0.enabled }.count
                let totalCount = server.tools.count
                SmallFilledTonalButton(onClick: onToolsClick, label: "Tools (\(enabledCount)/\(totalCount))", systemImage: "slider.horizontal.3")
                    .disabled(serverState.error != nil)
                SmallOutlinedButton(onClick: onDeleteClick, label: Str.delete, systemImage: "trash")
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(colors.surfaceContainerLowest)
        .cornerRadius(20)
    }
}

// MARK: - Helper for sheet item binding

private struct McpServerStateIdentifiable: Identifiable {
    let url: String
    var id: String { url }
}


// MARK: - Reuse SearchBar + SmallButtons (inline)
// (Identical helpers to SkillManagerBottomSheet — factor into a shared file if desired.)

private struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    @Environment(\.galleryColors) var colors
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(colors.onSurfaceVariant)
            TextField(placeholder, text: $text).autocorrectionDisabled().textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button(action: { text = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(colors.onSurfaceVariant) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(colors.surfaceContainerHigh).clipShape(Capsule())
    }
}
