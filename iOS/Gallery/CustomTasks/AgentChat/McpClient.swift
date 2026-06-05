// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/agentchat/McpManagerViewModel.kt (client transport portion)
//
// NOTE: Android uses the official MCP Kotlin SDK (`io.modelcontextprotocol:kotlin-sdk`) which
// provides `StreamableHttpClientTransport` (HTTP + SSE) and `Client`. No equivalent iOS Swift
// SDK exists yet. This file provides a minimal `McpClient` abstraction built on top of
// URLSession. The MCP Streamable-HTTP transport (https://spec.modelcontextprotocol.io/specification/
// basic/transports/#streamable-http) is implemented using:
//   - POST  <url>  with JSON-RPC body → returns JSON-RPC response (non-streaming calls).
//   - GET   <url>  with Accept: text/event-stream → SSE stream for notifications.
// Replace or expand with a real SDK once one is available for iOS.

import Foundation

// MARK: - Wire types (minimal JSON-RPC / MCP schema)

struct McpJsonRpcRequest: Codable {
    var jsonrpc = "2.0"
    var id: Int
    var method: String
    var params: [String: AnyCodable]?
}

struct McpJsonRpcResponse: Codable {
    var jsonrpc: String?
    var id: Int?
    var result: AnyCodable?
    var error: McpJsonRpcError?
}

struct McpJsonRpcError: Codable {
    var code: Int
    var message: String
}

/// Minimal type-erased JSON value — covers the subset we need for MCP requests/responses.
struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode([String: AnyCodable].self) { value = v }
        else if let v = try? container.decode([AnyCodable].self) { value = v }
        else { value = NSNull() }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let b as Bool:   try c.encode(b)
        case let i as Int:    try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let a as [AnyCodable]: try c.encode(a)
        case let o as [String: AnyCodable]: try c.encode(o)
        default: try c.encodeNil()
        }
    }
}

// MARK: - MCP Tool discovery response models

struct McpListToolsResult: Codable {
    var tools: [McpRemoteTool]?
}
struct McpRemoteTool: Codable {
    var name: String
    var description: String?
    var inputSchema: McpInputSchema?
}
struct McpInputSchema: Codable {
    var properties: [String: AnyCodable]?
    var required: [String]?
}

// MCP callTool result models
struct McpCallToolResult: Codable {
    var content: [McpContentItem]?
    var isError: Bool?
}
struct McpContentItem: Codable {
    var type: String?
    var text: String?
}

// Server info from initialize response
struct McpServerInfo: Codable {
    var name: String?
    var version: String?
}
struct McpInitializeResult: Codable {
    var serverInfo: McpServerInfo?
    var capabilities: AnyCodable?
}

// MARK: - McpAuth equivalent

enum McpAuthMethod {
    case none
    case requestHeader(name: String, value: String)
}

// MARK: - McpClient

/// A minimal MCP client using URLSession + JSON-RPC over HTTP.
/// NOTE: This implements only the subset of the MCP Streamable-HTTP transport needed for
/// `initialize`, `tools/list`, and `tools/call`. SSE notification streaming is stubbed.
/// Replace with a proper SDK transport once available.
final class McpClient {
    let url: URL
    private let auth: McpAuthMethod
    private var requestId = 1
    private(set) var serverVersion: McpServerInfo?

    init(url: URL, auth: McpAuthMethod = .none) {
        self.url = url
        self.auth = auth
    }

    // MARK: - Connect and initialize

    /// Sends MCP `initialize` then `notifications/initialized`, populating `serverVersion`.
    func connect() async throws {
        let result: McpInitializeResult = try await call(method: "initialize", params: [
            "protocolVersion": AnyCodable("2024-11-05"),
            "clientInfo": AnyCodable(["name": AnyCodable("gallery-ios"), "version": AnyCodable("1.0")] as [String: AnyCodable]),
            "capabilities": AnyCodable([:] as [String: AnyCodable]),
        ])
        serverVersion = result.serverInfo
        // Send initialized notification (fire-and-forget, no response expected)
        _ = try? await sendNotification(method: "notifications/initialized")
    }

    // MARK: - List tools

    func listTools() async throws -> McpListToolsResult {
        return try await call(method: "tools/list", params: nil)
    }

    // MARK: - Call tool

    func callTool(name: String, arguments: [String: AnyCodable]) async throws -> McpCallToolResult {
        return try await call(method: "tools/call", params: [
            "name": AnyCodable(name),
            "arguments": AnyCodable(arguments),
        ])
    }

    // MARK: - Private JSON-RPC helpers

    private func call<T: Decodable>(method: String, params: [String: AnyCodable]?) async throws -> T {
        let id = requestId; requestId += 1
        let req = McpJsonRpcRequest(id: id, method: method, params: params)
        let body = try JSONEncoder().encode(req)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuth(to: &request)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw McpError.httpError(httpResponse.statusCode)
        }
        let rpc = try JSONDecoder().decode(McpJsonRpcResponse.self, from: data)
        if let err = rpc.error { throw McpError.rpcError(err.code, err.message) }
        // Re-encode the result value and decode as T
        guard let resultValue = rpc.result else { throw McpError.noResult }
        let resultData = try JSONEncoder().encode(resultValue)
        return try JSONDecoder().decode(T.self, from: resultData)
    }

    @discardableResult
    private func sendNotification(method: String) async throws -> Data {
        let body = try JSONEncoder().encode(["jsonrpc": "2.0", "method": method] as [String: String])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)
        request.httpBody = body
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    private func applyAuth(to request: inout URLRequest) {
        if case .requestHeader(let name, let value) = auth {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }
}

enum McpError: Error {
    case httpError(Int)
    case rpcError(Int, String)
    case noResult
}
