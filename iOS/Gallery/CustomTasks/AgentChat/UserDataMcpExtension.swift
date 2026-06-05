// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
//
// Extends UserData (defined in Proto/Settings.swift) with MCP persistence fields.
// NOTE: The Android app stored MCP servers in a *separate* proto DataStore<McpServers>
// and auth tokens in UserData.mcpAuths. On iOS we store both in UserData to avoid a
// second file, piggybacking on the existing DataStoreRepository.updateUserData API.
//
// UserData.mcpAuths already exists in Settings.swift as [String: McpAuth].
// We add mcpServers as an optional field via a separate Codable wrapper so the
// existing UserData JSON files decode cleanly (missing key → nil → use default).

import Foundation

// MARK: - Patch UserData with mcpServers

// Swift extensions cannot add stored properties, so we use a separate Codable
// key via a custom JSON key in a thin wrapper. The DataStoreRepository already
// provides updateUserData; McpManagerViewModel calls it to persist McpServers.
//
// Implementation strategy: McpManagerViewModel calls
//   `dataStoreRepository.updateUserData { $0.mcpServersData = McpServersData(mcpServer: ...) }`
// but since UserData doesn't have this field yet, we piggyback on the `secrets` dictionary
// using a special key — this avoids touching Settings.swift.
//
// NOTE: A cleaner solution would be to add `var mcpServers: McpServers?` to UserData
// and `var mcpAuths: [String: McpAuthStored]?`. The integrator should do this edit in
// Settings.swift once the agent chat feature is wired in, replacing the piggyback approach below.

extension DefaultDataStoreRepository {
    private static let MCP_SERVERS_KEY = "__mcp_servers_json__"

    func readMcpServers() -> McpServers {
        guard let json = readSecret(key: Self.MCP_SERVERS_KEY),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(McpServers.self, from: data) else {
            return McpServers.defaultInstance
        }
        return decoded
    }

    func writeMcpServers(_ servers: McpServers) {
        guard let data = try? JSONEncoder().encode(servers),
              let json = String(data: data, encoding: .utf8) else { return }
        saveSecret(key: Self.MCP_SERVERS_KEY, value: json)
    }
}

// McpAuth bridge: The existing McpAuth in Settings.swift uses a Method enum with
// associated values. McpAuthStored (defined in McpManagerViewModel.swift) uses a simpler
// string-typed struct. We provide a conversion here.

extension McpAuth {
    init(fromStored stored: McpAuthStored) {
        switch stored.type {
        case "request_header":
            self.method = .requestHeader(headerName: stored.headerName ?? "", headerValue: stored.headerValue ?? "")
        case "oauth":
            self.method = .oauth
        default:
            self.method = .none
        }
    }
}

// McpManagerViewModel reads auth by accessing UserData.mcpAuths (existing field).
// We provide a convenience accessor that bridges McpAuth.Method → McpAuthMethod.
extension McpAuth.Method {
    var asMcpAuthMethod: McpAuthMethod {
        switch self {
        case .requestHeader(let name, let value): return .requestHeader(name: name, value: value)
        default: return .none
        }
    }
}
