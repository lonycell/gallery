// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/AddMcpServerFromUrlDialog.kt

import SwiftUI

private let APPROVED_MCP_HOSTS = ["googleapis.com"]

private func isMcpHostApproved(_ url: String) -> Bool {
    guard let u = URL(string: url), let host = u.host?.lowercased() else { return false }
    return APPROVED_MCP_HOSTS.contains { host == $0 || host.hasSuffix(".\($0)") }
}

struct AddMcpServerFromUrlDialog: View {
    @ObservedObject var mcpManagerViewModel: McpManagerViewModel
    let onDismissRequest: () -> Void
    let onSuccess: () -> Void

    @State private var urlText = ""
    @State private var authType: McpAuthMethodType = .none
    @State private var headerName = ""
    @State private var headerValue = ""
    @State private var isAdding = false
    @State private var showDisclaimerSheet = false
    @State private var showDuplicateAlert = false

    @Environment(\.galleryColors) var colors

    enum McpAuthMethodType: String, CaseIterable {
        case none = "None"
        case requestHeader = "Request header"
        case oauthWip = "OAuth (WIP)"
    }

    private var uiState: McpManagerUiState { mcpManagerViewModel.uiState }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(Str.addMcpServerFromUrlDialogTitle).font(AppTypography.titleMedium).padding(.bottom, 8)

                    // URL field
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Str.enterMcpServerUrl).font(AppTypography.labelMedium)
                        TextField("", text: $urlText, axis: .vertical)
                            .textFieldStyle(.roundedBorder).lineLimit(1...3)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .onChange(of: urlText) { _ in mcpManagerViewModel.clearError() }
                        if let err = uiState.error {
                            Text(err).font(AppTypography.bodySmall).foregroundColor(colors.error).lineLimit(3)
                        }
                    }

                    // Auth selector
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Str.mcpServerAuthorization).font(AppTypography.labelMedium)
                        Picker("", selection: $authType) {
                            ForEach(McpAuthMethodType.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.outline, lineWidth: 1))
                    }

                    // Header fields (if request header auth selected)
                    if authType == .requestHeader {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Str.mcpServerHeaderName).font(AppTypography.labelMedium)
                            TextField("", text: $headerName).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Str.mcpServerHeaderValue).font(AppTypography.labelMedium)
                            TextField("", text: $headerValue).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        }
                    }

                    // Buttons or progress
                    if uiState.loadingMcpServer && isAdding {
                        HStack { Spacer(); ProgressView().frame(width: 20, height: 20) }
                    } else {
                        HStack {
                            Spacer()
                            Button(Str.cancel, action: safeDismiss).buttonStyle(.bordered)
                            Button(Str.add) {
                                let url = urlText.trimmingCharacters(in: .whitespaces)
                                if mcpManagerViewModel.hasMcpServer(url: url) {
                                    showDuplicateAlert = true
                                } else if isMcpHostApproved(url) {
                                    doAdd(url: url)
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
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: uiState.loadingMcpServer) { loading in
            if isAdding && !loading {
                if uiState.error == nil {
                    mcpManagerViewModel.clearError()
                    safeDismiss()
                    onSuccess()
                } else {
                    isAdding = false
                }
            }
        }
        .sheet(isPresented: $showDisclaimerSheet) {
            AddMcpDisclaimerDialog(
                onDismiss: { showDisclaimerSheet = false },
                onConfirm: {
                    showDisclaimerSheet = false
                    doAdd(url: urlText.trimmingCharacters(in: .whitespaces))
                })
        }
        .alert(Str.mcpServerDuplicateTitle, isPresented: $showDuplicateAlert) {
            Button(Str.ok) { showDuplicateAlert = false }
        } message: { Text(Str.mcpServerDuplicateContent) }
    }

    private func safeDismiss() { mcpManagerViewModel.clearError(); onDismissRequest() }

    private func doAdd(url: String) {
        isAdding = true
        let auth: McpAuthMethod
        switch authType {
        case .requestHeader: auth = .requestHeader(name: headerName, value: headerValue)
        default: auth = .none
        }
        mcpManagerViewModel.addMcpServer(url: url, authMethod: auth, headerName: headerName, headerValue: headerValue)
    }
}
