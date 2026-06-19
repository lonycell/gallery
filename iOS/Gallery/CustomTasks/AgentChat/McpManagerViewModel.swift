// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/McpManagerViewModel.kt

import Foundation
import SwiftUI

// MARK: - State types

struct McpServerState: Identifiable {
    var mcpServer: McpServer
    var client: McpClient?
    var error: String? = nil
    var id: String { mcpServer.url }
}

struct McpManagerUiState {
    var mcpServers: [McpServerState] = []
    var loadingMcpServer: Bool = false
    var error: String? = nil
}

// MARK: - ViewModel

@MainActor
final class McpManagerViewModel: ObservableObject {
    @Published var uiState = McpManagerUiState()

    private let dataStoreRepository: DataStoreRepository
    // Persisted MCP servers are stored in UserData.mcpServers (JSON).
    // NOTE: Android used a separate proto DataStore<McpServers>; on iOS we piggyback on
    // DataStoreRepository.updateUserData to persist McpServers inline in user_data.json.

    init(dataStoreRepository: DataStoreRepository) {
        self.dataStoreRepository = dataStoreRepository
    }

    // MARK: - Load

    func loadMcpServers() async {
        uiState.loadingMcpServer = true
        let savedServersCollection = (dataStoreRepository as? DefaultDataStoreRepository)?.readMcpServers() ?? McpServers.defaultInstance
        let savedServers = savedServersCollection.mcpServer
        var loaded: [McpServerState] = []
        for serverProto in savedServers {
            do {
                let savedToolsMap = Dictionary(uniqueKeysWithValues: serverProto.tools.map { ($0.name, $0.enabled) })
                let savedAlwaysAllowMap = Dictionary(uniqueKeysWithValues: serverProto.tools.map { ($0.name, $0.alwaysAllow) })
                let auth = resolveAuth(for: serverProto.url)
                let (client, mcpTools) = try await initializeClientAndLoadTools(
                    url: serverProto.url, savedToolsMap: savedToolsMap,
                    savedAlwaysAllowMap: savedAlwaysAllowMap, auth: auth)
                var updated = serverProto
                updated.tools = mcpTools
                updated.enabled = serverProto.enabled
                if let name = client.serverVersion?.name, !name.isEmpty { updated.name = name }
                if let ver = client.serverVersion?.version, !ver.isEmpty { updated.version = ver }
                if !mcpTools.isEmpty { updated.description = "Tools: \(mcpTools.map { $0.name }.joined(separator: ", "))" }
                loaded.append(McpServerState(mcpServer: updated, client: client, error: nil))
            } catch {
                loaded.append(McpServerState(mcpServer: serverProto, client: nil, error: error.localizedDescription))
            }
        }
        uiState.mcpServers = loaded
        uiState.loadingMcpServer = false
        // Persist back (skip errored entries so retries work on next launch)
        await persistServerList(loaded.enumerated().map { idx, state in
            state.error != nil ? savedServers[idx] : state.mcpServer
        })
    }

    // MARK: - Add

    func addMcpServer(url: String, authMethod: McpAuthMethod, headerName: String, headerValue: String) {
        uiState.loadingMcpServer = true
        uiState.error = nil
        _Concurrency.Task {
            do {
                let auth: McpAuthMethod
                switch authMethod {
                case .requestHeader:
                    auth = .requestHeader(name: headerName, value: headerValue)
                default:
                    auth = .none
                }
                let (client, mcpTools) = try await initializeClientAndLoadTools(url: url, auth: auth)
                var proto = McpServer(url: url, tools: mcpTools, enabled: true)
                if let n = client.serverVersion?.name { proto.name = n }
                if let v = client.serverVersion?.version { proto.version = v }
                if !mcpTools.isEmpty { proto.description = "Tools: \(mcpTools.map { $0.name }.joined(separator: ", "))" }
                let newState = McpServerState(mcpServer: proto, client: client, error: nil)

                // Persist auth
                await dataStoreRepository.updateUserData { userData in
                    var mcpAuth = McpAuth()
                    if case .requestHeader(let n, let v) = auth {
                        mcpAuth.method = .requestHeader(headerName: n, headerValue: v)
                    }
                    userData.mcpAuths[url] = mcpAuth
                }

                uiState.mcpServers.removeAll { $0.mcpServer.url == url }
                uiState.mcpServers.append(newState)
                uiState.loadingMcpServer = false
                await persistCurrentServers()
            } catch {
                uiState.error = error.localizedDescription
                uiState.loadingMcpServer = false
            }
        }
    }

    func clearError() { uiState.error = nil }

    func removeMcpServer(url: String) {
        uiState.mcpServers.removeAll { $0.mcpServer.url == url }
        _Concurrency.Task { await persistCurrentServers() }
    }

    func hasMcpServer(url: String) -> Bool { uiState.mcpServers.contains { $0.mcpServer.url == url } }

    // MARK: - Enable / disable

    func setMcpServerEnabled(url: String, enabled: Bool) {
        updateServer(url: url) { $0.mcpServer.enabled = enabled }
        _Concurrency.Task { await persistCurrentServers() }
    }

    func setMcpToolEnabled(url: String, toolName: String, enabled: Bool) {
        updateServer(url: url) { state in
            state.mcpServer.tools = state.mcpServer.tools.map {
                var t = $0; if t.name == toolName { t.enabled = enabled }; return t
            }
        }
        _Concurrency.Task { await persistCurrentServers() }
    }

    func setAllMcpServerEnabled(enabled: Bool) {
        uiState.mcpServers = uiState.mcpServers.map { var s = $0; if s.error == nil { s.mcpServer.enabled = enabled }; return s }
        _Concurrency.Task { await persistCurrentServers() }
    }

    func setAllMcpToolsEnabled(url: String, enabled: Bool) {
        updateServer(url: url) { state in
            state.mcpServer.tools = state.mcpServer.tools.map { var t = $0; t.enabled = enabled; return t }
        }
        _Concurrency.Task { await persistCurrentServers() }
    }

    func setMcpToolAlwaysAllow(url: String, toolName: String, alwaysAllow: Bool) {
        updateServer(url: url) { state in
            state.mcpServer.tools = state.mcpServer.tools.map {
                var t = $0; if t.name == toolName { t.alwaysAllow = alwaysAllow }; return t
            }
        }
        _Concurrency.Task { await persistCurrentServers() }
    }

    // MARK: - Prompt generation

    func getToolsPrompt() -> String {
        uiState.mcpServers
            .filter { $0.mcpServer.enabled }
            .flatMap { $0.mcpServer.tools }
            .filter { $0.enabled }
            .map { tool in "MCP tool name: \"\(tool.name)\"\n- Description: \(tool.description)\n- Input schema: \(tool.inputSchema)" }
            .joined(separator: "\n\n")
    }

    func getSelectedMcpsAndToolsSummary() -> String {
        uiState.mcpServers.flatMap { state -> [String] in
            var parts = ["\(state.mcpServer.url):\(state.mcpServer.enabled)"]
            parts += state.mcpServer.tools.map { "\($0.name):\($0.enabled)" }
            return parts
        }.joined(separator: ";")
    }

    // MARK: - Internal

    private func updateServer(url: String, block: (inout McpServerState) -> Void) {
        if let i = uiState.mcpServers.firstIndex(where: { $0.mcpServer.url == url }) {
            block(&uiState.mcpServers[i])
        }
    }

    private func initializeClientAndLoadTools(url: String, savedToolsMap: [String: Bool]? = nil, savedAlwaysAllowMap: [String: Bool]? = nil, auth: McpAuthMethod = .none) async throws -> (McpClient, [McpTool]) {
        guard let serverURL = URL(string: url) else { throw URLError(.badURL) }
        let client = McpClient(url: serverURL, auth: auth)
        try await client.connect()
        let toolsResponse = try await client.listTools()
        let tools = (toolsResponse.tools ?? []).map { remote -> McpTool in
            let isEnabled = savedToolsMap?[remote.name] ?? true
            let alwaysAllow = savedAlwaysAllowMap?[remote.name] ?? false
            let props = remote.inputSchema?.properties.map { _ in "{}" } ?? "{}"
            // Build a simple JSON schema string
            let required = remote.inputSchema?.required ?? []
            let requiredJson = required.isEmpty ? "[]" : "[\(required.map { "\"\($0)\"" }.joined(separator: ","))]"
            // NOTE: Full property schema serialization omitted — AnyCodable round-trip would be needed.
            let schemaJson = """
            {"type":"object","properties":\(props),"required":\(requiredJson)}
            """
            return McpTool(name: remote.name, description: remote.description ?? "", inputSchema: schemaJson, enabled: isEnabled, alwaysAllow: alwaysAllow)
        }
        return (client, tools)
    }

    private func resolveAuth(for url: String) -> McpAuthMethod {
        guard let auth = dataStoreRepository.readUserData().mcpAuths[url] else { return .none }
        return auth.method.asMcpAuthMethod
    }

    private func persistCurrentServers() async {
        await persistServerList(uiState.mcpServers.map { $0.mcpServer })
    }

    private func persistServerList(_ servers: [McpServer]) async {
        // NOTE: McpServers is persisted via a piggyback key in DataStoreRepository.
        // See UserDataMcpExtension.swift for the implementation.
        // If DataStoreRepository is a DefaultDataStoreRepository, use writeMcpServers.
        if let repo = dataStoreRepository as? DefaultDataStoreRepository {
            repo.writeMcpServers(McpServers(mcpServer: servers))
        }
    }
}

// MARK: - Stored auth helper (lives in UserData)

struct McpAuthStored: Codable {
    var type: String
    var headerName: String? = nil
    var headerValue: String? = nil
}
