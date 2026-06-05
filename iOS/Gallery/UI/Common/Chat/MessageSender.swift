/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageSender.kt

import SwiftUI

/// Sender label row shown above each message bubble.
struct MessageSender: View {
  let message: ChatMessage
  var agentName: String = ""
  var imageHistoryCurIndex: Int = 0

  @Environment(\.galleryColors) private var colors

  var body: some View {
    Group {
      if message.side != .system { content }
    }
  }

  @ViewBuilder
  private var content: some View {
    let config = layoutConfig

    HStack(alignment: .center) {
      HStack(spacing: 4) {
        Text(config.userLabel)
          .font(.subheadline).fontWeight(.semibold)

        // Running indicators
        if let benchmark = message as? ChatMessageBenchmarkResult {
          if benchmark.isRunning() {
            ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
          }
          let statusLabel: String = {
            if benchmark.isWarmingUp() { return Str.warmingUp }
            if benchmark.isRunning() { return Str.running }
            return ""
          }()
          if !statusLabel.isEmpty {
            Text(statusLabel).font(.caption).foregroundColor(colors.secondary)
          }
        } else if let llm = message as? ChatMessageBenchmarkLlmResult {
          if llm.running {
            ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
          }
        } else if let imgH = message as? ChatMessageImageWithHistory {
          if imgH.isRunning() {
            ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
            Text(Str.running).font(.caption).foregroundColor(colors.secondary)
          }
        }
      }

      Spacer(minLength: 0)

      // Right-side label (iteration counter, etc.)
      if !config.rightSideLabel.isEmpty {
        Text(config.rightSideLabel).font(.caption)
      }
    }
    .frame(maxWidth: config.useFullWidth ? .infinity : nil,
           alignment: config.useFullWidth ? .leading : .trailing)
    .padding(.bottom, 2)
  }

  private struct LayoutConfig {
    var userLabel: String
    var rightSideLabel: String = ""
    var useFullWidth: Bool = false
  }

  private var layoutConfig: LayoutConfig {
    var cfg = LayoutConfig(
      userLabel: message.side == .agent ? agentName : Str.chatYou
    )
    if let bench = message as? ChatMessageBenchmarkResult {
      cfg.userLabel = "Benchmark"
      cfg.useFullWidth = true
      cfg.rightSideLabel = bench.isWarmingUp()
        ? "\(bench.warmupCurrent)/\(bench.warmupTotal)"
        : "\(bench.iterationCurrent)/\(bench.iterationTotal)"
    } else if let llm = message as? ChatMessageBenchmarkLlmResult {
      cfg.userLabel = "Stats"
      if !llm.accelerator.isEmpty { cfg.userLabel += " on \(llm.accelerator)" }
      cfg.useFullWidth = true
    } else if let imgH = message as? ChatMessageImageWithHistory {
      cfg.useFullWidth = !imgH.images.isEmpty
      cfg.rightSideLabel = "\(imageHistoryCurIndex + 1)/\(imgH.totalIterations)"
    }
    return cfg
  }
}
