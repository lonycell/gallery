/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/ChatMessage.kt — the chat message class hierarchy.
// Kotlin used an open class + subclasses; Swift mirrors that with a base class
// and subclasses so the chat UI can switch on `type`.

import SwiftUI
import UIKit

enum ChatMessageType {
  case info, warning, error, text, image, imageWithHistory, audioClip, loading
  case classification, configValuesChange, benchmarkResult, benchmarkLlmResult
  case promptTemplates, webview, collapsableProgressPanel, thinking
}

enum ChatSide { case user, agent, system }

/// Base chat message. Mirrors `open class ChatMessage`.
class ChatMessage: Identifiable {
  let id = UUID()
  let type: ChatMessageType
  let side: ChatSide
  let latencyMs: Float
  let accelerator: String
  let hideSenderLabel: Bool
  let disableBubbleShape: Bool

  init(type: ChatMessageType, side: ChatSide, latencyMs: Float = -1, accelerator: String = "",
       hideSenderLabel: Bool = false, disableBubbleShape: Bool = false) {
    self.type = type
    self.side = side
    self.latencyMs = latencyMs
    self.accelerator = accelerator
    self.hideSenderLabel = hideSenderLabel
    self.disableBubbleShape = disableBubbleShape
  }

  func clone() -> ChatMessage {
    ChatMessage(type: type, side: side, latencyMs: latencyMs, accelerator: accelerator,
                hideSenderLabel: hideSenderLabel, disableBubbleShape: disableBubbleShape)
  }
}

final class ChatMessageLoading: ChatMessage {
  var extraProgressLabel: String
  init(extraProgressLabel: String = "", accelerator: String = "") {
    self.extraProgressLabel = extraProgressLabel
    super.init(type: .loading, side: .agent, accelerator: accelerator)
  }
  override func clone() -> ChatMessage {
    ChatMessageLoading(extraProgressLabel: extraProgressLabel, accelerator: accelerator)
  }
}

final class ChatMessageInfo: ChatMessage {
  let content: String
  init(content: String) { self.content = content; super.init(type: .info, side: .system) }
}

final class ChatMessageWarning: ChatMessage {
  let content: String
  init(content: String) { self.content = content; super.init(type: .warning, side: .system) }
}

final class ChatMessageError: ChatMessage {
  let content: String
  init(content: String) { self.content = content; super.init(type: .error, side: .system) }
}

final class ChatMessageConfigValuesChange: ChatMessage {
  let model: Model
  let oldValues: [String: Any]
  let newValues: [String: Any]
  init(model: Model, oldValues: [String: Any], newValues: [String: Any]) {
    self.model = model; self.oldValues = oldValues; self.newValues = newValues
    super.init(type: .configValuesChange, side: .system)
  }
}

/// Plain text message. Mirrors `open class ChatMessageText`.
class ChatMessageText: ChatMessage {
  let content: String
  let isMarkdown: Bool
  var llmBenchmarkResult: ChatMessageBenchmarkLlmResult?
  var data: Any?

  init(content: String, side: ChatSide, latencyMs: Float = 0, isMarkdown: Bool = true,
       llmBenchmarkResult: ChatMessageBenchmarkLlmResult? = nil, accelerator: String = "",
       hideSenderLabel: Bool = false, data: Any? = nil) {
    self.content = content
    self.isMarkdown = isMarkdown
    self.llmBenchmarkResult = llmBenchmarkResult
    self.data = data
    super.init(type: .text, side: side, latencyMs: latencyMs, accelerator: accelerator,
               hideSenderLabel: hideSenderLabel)
  }
  override func clone() -> ChatMessage {
    ChatMessageText(content: content, side: side, latencyMs: latencyMs, isMarkdown: isMarkdown,
                    llmBenchmarkResult: llmBenchmarkResult, accelerator: accelerator,
                    hideSenderLabel: hideSenderLabel, data: data)
  }
}

final class ChatMessageImage: ChatMessage {
  let images: [UIImage]
  let maxSize: Int
  var persistedPaths: [String]?
  init(images: [UIImage], maxSize: Int = 200, side: ChatSide, latencyMs: Float = 0,
       accelerator: String = "", hideSenderLabel: Bool = false, persistedPaths: [String]? = nil) {
    self.images = images; self.maxSize = maxSize; self.persistedPaths = persistedPaths
    super.init(type: .image, side: side, latencyMs: latencyMs, accelerator: accelerator,
               hideSenderLabel: hideSenderLabel)
  }
  override func clone() -> ChatMessage {
    ChatMessageImage(images: images, side: side, latencyMs: latencyMs, accelerator: accelerator,
                     hideSenderLabel: hideSenderLabel, persistedPaths: persistedPaths)
  }
}

final class ChatMessageAudioClip: ChatMessage {
  let audioData: Data
  let sampleRate: Int
  var persistedPath: String?
  init(audioData: Data, sampleRate: Int, side: ChatSide, latencyMs: Float = 0, persistedPath: String? = nil) {
    self.audioData = audioData; self.sampleRate = sampleRate; self.persistedPath = persistedPath
    super.init(type: .audioClip, side: side, latencyMs: latencyMs)
  }
  override func clone() -> ChatMessage {
    ChatMessageAudioClip(audioData: audioData, sampleRate: sampleRate, side: side,
                         latencyMs: latencyMs, persistedPath: persistedPath)
  }

  /// Build a 16-bit mono WAV byte stream from the PCM data.
  func genDataForWav() -> Data {
    var header = Data(count: 44)
    let pcmSize = audioData.count
    let wavSize = pcmSize + 44
    let channels = 1, bitsPerSample = 16
    let byteRate = sampleRate * channels * bitsPerSample / 8
    func put(_ i: Int, _ b: UInt8) { header[i] = b }
    let riff: [UInt8] = Array("RIFF".utf8); for i in 0..<4 { put(i, riff[i]) }
    put(4, UInt8(wavSize & 0xff)); put(5, UInt8((wavSize >> 8) & 0xff))
    put(6, UInt8((wavSize >> 16) & 0xff)); put(7, UInt8((wavSize >> 24) & 0xff))
    let wave: [UInt8] = Array("WAVE".utf8); for i in 0..<4 { put(8 + i, wave[i]) }
    let fmt: [UInt8] = Array("fmt ".utf8); for i in 0..<4 { put(12 + i, fmt[i]) }
    put(16, 16); put(20, 1); put(22, UInt8(channels))
    put(24, UInt8(sampleRate & 0xff)); put(25, UInt8((sampleRate >> 8) & 0xff))
    put(26, UInt8((sampleRate >> 16) & 0xff)); put(27, UInt8((sampleRate >> 24) & 0xff))
    put(28, UInt8(byteRate & 0xff)); put(29, UInt8((byteRate >> 8) & 0xff))
    put(30, UInt8((byteRate >> 16) & 0xff)); put(31, UInt8((byteRate >> 24) & 0xff))
    put(32, UInt8(channels * bitsPerSample / 8)); put(34, UInt8(bitsPerSample))
    let dataTag: [UInt8] = Array("data".utf8); for i in 0..<4 { put(36 + i, dataTag[i]) }
    put(40, UInt8(pcmSize & 0xff)); put(41, UInt8((pcmSize >> 8) & 0xff))
    put(42, UInt8((pcmSize >> 16) & 0xff)); put(43, UInt8((pcmSize >> 24) & 0xff))
    return header + audioData
  }

  func getDurationInSeconds() -> Float {
    let bytesPerFrame = 2 // 16-bit mono
    return Float(audioData.count) / Float(bytesPerFrame) / Float(sampleRate)
  }
}

final class ChatMessageImageWithHistory: ChatMessage {
  let images: [UIImage]
  let totalIterations: Int
  var curIteration: Int
  init(images: [UIImage], totalIterations: Int, side: ChatSide, latencyMs: Float = 0, curIteration: Int = 0) {
    self.images = images; self.totalIterations = totalIterations; self.curIteration = curIteration
    super.init(type: .imageWithHistory, side: side, latencyMs: latencyMs)
  }
  func isRunning() -> Bool { curIteration < totalIterations - 1 }
}

final class ChatMessageClassification: ChatMessage {
  let classifications: [Classification]
  let maxBarWidth: CGFloat?
  init(classifications: [Classification], latencyMs: Float = 0, maxBarWidth: CGFloat? = nil) {
    self.classifications = classifications; self.maxBarWidth = maxBarWidth
    super.init(type: .classification, side: .agent, latencyMs: latencyMs)
  }
}

struct Stat: Hashable { let id: String; let label: String; let unit: String }
struct Histogram { let buckets: [Int]; let maxCount: Int; var highlightBucketIndex: Int = -1 }

final class ChatMessageBenchmarkResult: ChatMessage {
  let orderedStats: [Stat]
  var statValues: [String: Float]
  let values: [Float]
  let histogram: Histogram
  let warmupCurrent, warmupTotal, iterationCurrent, iterationTotal: Int
  let highlightStat: String
  init(orderedStats: [Stat], statValues: [String: Float], values: [Float], histogram: Histogram,
       warmupCurrent: Int, warmupTotal: Int, iterationCurrent: Int, iterationTotal: Int,
       latencyMs: Float = 0, highlightStat: String = "") {
    self.orderedStats = orderedStats; self.statValues = statValues; self.values = values
    self.histogram = histogram; self.warmupCurrent = warmupCurrent; self.warmupTotal = warmupTotal
    self.iterationCurrent = iterationCurrent; self.iterationTotal = iterationTotal
    self.highlightStat = highlightStat
    super.init(type: .benchmarkResult, side: .agent, latencyMs: latencyMs)
  }
  func isWarmingUp() -> Bool { warmupCurrent < warmupTotal }
  func isRunning() -> Bool { iterationCurrent < iterationTotal }
}

final class ChatMessageBenchmarkLlmResult: ChatMessage {
  let orderedStats: [Stat]
  var statValues: [String: Float]
  let running: Bool
  init(orderedStats: [Stat], statValues: [String: Float], running: Bool, latencyMs: Float = 0, accelerator: String = "") {
    self.orderedStats = orderedStats; self.statValues = statValues; self.running = running
    super.init(type: .benchmarkLlmResult, side: .agent, latencyMs: latencyMs, accelerator: accelerator)
  }
}

final class ChatMessagePromptTemplates: ChatMessage {
  let templates: [PromptTemplate]
  let showMakeYourOwn: Bool
  init(templates: [PromptTemplate], showMakeYourOwn: Bool = true) {
    self.templates = templates; self.showMakeYourOwn = showMakeYourOwn
    super.init(type: .promptTemplates, side: .system)
  }
}

final class ChatMessageWebView: ChatMessage {
  let url: String
  let iframe: Bool
  let aspectRatio: Float
  init(url: String, iframe: Bool, aspectRatio: Float, side: ChatSide = .agent, hideSenderLabel: Bool = false) {
    self.url = url; self.iframe = iframe; self.aspectRatio = aspectRatio
    super.init(type: .webview, side: side, hideSenderLabel: hideSenderLabel, disableBubbleShape: true)
  }
  override func clone() -> ChatMessage {
    ChatMessageWebView(url: url, iframe: iframe, aspectRatio: aspectRatio, side: side, hideSenderLabel: hideSenderLabel)
  }
}

struct ProgressPanelItem { let title: String; let description: String }
enum LogMessageLevel { case info, warning, error }
struct LogMessage {
  var level: LogMessageLevel = .info
  var source: String = ""
  var lineNumber: Int = -1
  var message: String = ""
}

final class ChatMessageCollapsableProgressPanel: ChatMessage {
  let title: String
  let inProgress: Bool
  let doneIcon: String // SF Symbol (was Icons.Rounded.Check)
  let items: [ProgressPanelItem]
  let logMessages: [LogMessage]
  let customData: Any?
  init(title: String, inProgress: Bool, accelerator: String, doneIcon: String = "checkmark",
       items: [ProgressPanelItem] = [], logMessages: [LogMessage] = [], customData: Any? = nil) {
    self.title = title; self.inProgress = inProgress; self.doneIcon = doneIcon
    self.items = items; self.logMessages = logMessages; self.customData = customData
    super.init(type: .collapsableProgressPanel, side: .agent, accelerator: accelerator)
  }
  override func clone() -> ChatMessage {
    ChatMessageCollapsableProgressPanel(title: title, inProgress: inProgress, accelerator: accelerator,
      doneIcon: doneIcon, items: items, logMessages: logMessages, customData: customData)
  }
}

final class ChatMessageThinking: ChatMessage {
  let content: String
  let inProgress: Bool
  init(content: String, inProgress: Bool, side: ChatSide = .agent, hideSenderLabel: Bool = false, accelerator: String = "") {
    self.content = content; self.inProgress = inProgress
    super.init(type: .thinking, side: side, accelerator: accelerator, hideSenderLabel: hideSenderLabel, disableBubbleShape: true)
  }
  override func clone() -> ChatMessage {
    ChatMessageThinking(content: content, inProgress: inProgress, side: side, hideSenderLabel: hideSenderLabel, accelerator: accelerator)
  }
}
