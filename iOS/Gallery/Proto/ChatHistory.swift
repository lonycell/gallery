/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of proto/chat_history.proto -> Codable Swift structs.

import Foundation

enum ChatSideProto: String, Codable {
  case unspecified = "CHAT_SIDE_UNSPECIFIED"
  case user = "CHAT_SIDE_USER"
  case model = "CHAT_SIDE_MODEL"
  case system = "CHAT_SIDE_SYSTEM"
}

struct AudioMessageProto: Codable {
  var filePath: String = ""
  var sampleRate: Int32 = 0
}

struct ChatMessageProto: Codable {
  var messageType: String = ""
  var content: String = ""
  var side: ChatSideProto = .unspecified
  var latencyMs: Float = 0
  var isMarkdown: Bool = false
  var accelerator: String = ""
  var hideSenderLabel: Bool = false
  var inProgress: Bool = false
  var imageFilePaths: [String] = []
  var audioClips: [AudioMessageProto] = []
}

struct ChatSessionProto: Codable, Identifiable {
  var sessionId: String = ""
  var title: String = ""
  var timestampMs: Int64 = 0
  var originalModel: String = ""
  var taskId: String = ""
  var messages: [ChatMessageProto] = []

  var id: String { sessionId }
}
