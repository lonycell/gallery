/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of proto/mcp.proto -> Codable Swift structs.

import Foundation

struct McpTool: Codable, Identifiable {
  var name: String = ""
  var description: String = ""
  var inputSchema: String = ""
  var enabled: Bool = false
  var alwaysAllow: Bool = false
  var id: String { name }
}

struct McpServer: Codable, Identifiable {
  var url: String = ""
  var tools: [McpTool] = []
  var enabled: Bool = false
  var name: String = ""
  var version: String = ""
  var description: String = ""
  var id: String { url }
}

struct McpServers: Codable {
  var mcpServer: [McpServer] = []
  static let defaultInstance = McpServers()
}
