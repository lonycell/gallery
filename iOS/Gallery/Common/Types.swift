/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of common/Types.kt

import SwiftUI

protocol LatencyProvider {
  var latencyMs: Float { get }
}

struct Classification {
  let label: String
  let score: Float
  let color: Color
}

struct JsonObjAndTextContent<T> {
  let jsonObj: T
  let textContent: String
}

final class AudioClip: Equatable {
  let audioData: Data
  let sampleRate: Int
  init(audioData: Data, sampleRate: Int) {
    self.audioData = audioData
    self.sampleRate = sampleRate
  }
  static func == (lhs: AudioClip, rhs: AudioClip) -> Bool {
    lhs.audioData == rhs.audioData && lhs.sampleRate == rhs.sampleRate
  }
}

/// A one-shot awaitable result, mirroring Kotlin's `CompletableDeferred<T>`.
final class Deferred<T>: @unchecked Sendable {
  private var continuation: CheckedContinuation<T, Never>?
  private var stored: T?
  private let lock = NSLock()

  func complete(_ value: T) {
    lock.lock(); defer { lock.unlock() }
    if let c = continuation {
      continuation = nil
      c.resume(returning: value)
    } else {
      stored = value
    }
  }

  func await() async -> T {
    await withCheckedContinuation { c in
      lock.lock(); defer { lock.unlock() }
      if let v = stored {
        c.resume(returning: v)
      } else {
        continuation = c
      }
    }
  }
}

enum AgentActionName {
  case callJsSkill
  case skillProgress
  case askInfo
  case requestPermission
  case askMcpToolCallPermission
}

class AgentAction {
  let name: AgentActionName
  init(name: AgentActionName) { self.name = name }
}

final class CallJsAgentAction: AgentAction {
  let url: String
  let data: String
  let secret: String
  let result = Deferred<String>()
  init(url: String, data: String, secret: String = "") {
    self.url = url; self.data = data; self.secret = secret
    super.init(name: .callJsSkill)
  }
}

final class AskInfoAgentAction: AgentAction {
  let dialogTitle: String
  let fieldLabel: String
  let result = Deferred<String>()
  init(dialogTitle: String, fieldLabel: String) {
    self.dialogTitle = dialogTitle; self.fieldLabel = fieldLabel
    super.init(name: .askInfo)
  }
}

final class SkillProgressAgentAction: AgentAction {
  let label: String
  let inProgress: Bool
  let addItemTitle: String
  let addItemDescription: String
  let customData: Any?
  init(label: String, inProgress: Bool, addItemTitle: String = "",
       addItemDescription: String = "", customData: Any? = nil) {
    self.label = label; self.inProgress = inProgress
    self.addItemTitle = addItemTitle; self.addItemDescription = addItemDescription
    self.customData = customData
    super.init(name: .skillProgress)
  }
}

final class RequestPermissionAgentAction: AgentAction {
  let permission: String
  let result = Deferred<Bool>()
  init(permission: String) {
    self.permission = permission
    super.init(name: .requestPermission)
  }
}

enum PermissionResult {
  case deny
  case allowOnce
  case alwaysAllow
}

final class AskMcpToolCallPermissionAction: AgentAction {
  let toolName: String
  let argument: String
  let result = Deferred<PermissionResult>()
  init(toolName: String, argument: String) {
    self.toolName = toolName; self.argument = argument
    super.init(name: .askMcpToolCallPermission)
  }
}

struct SkillTryOutChip {
  let icon: String   // SF Symbol name (was Compose ImageVector)
  let label: String
  let prompt: String
  let skillName: String
}

struct SkillInfo {
  let skillMd: String
  var skillUrl: String? = nil
  var tryoutChip: SkillTryOutChip? = nil
}

struct SkillsIndex {
  let skills: [SkillInfo]
}

struct CallJsSkillResultImage: Codable { let base64: String? }

struct CallJsSkillResultWebview: Codable {
  let url: String?
  let iframe: Bool?
  /// width/height; the webview always spans full screen width, default 4:3.
  let aspectRatio: Float?
}

struct CallJsSkillResult: Codable {
  let result: String?
  let error: String?
  let image: CallJsSkillResultImage?
  let webview: CallJsSkillResultWebview?
}
