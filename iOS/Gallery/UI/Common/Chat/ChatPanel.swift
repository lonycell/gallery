/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/ChatPanel.kt

import SwiftUI

private let CHAT_BUBBLE_CORNER_RADIUS: CGFloat = 18

struct ChatPanel: View {
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  let task: Task
  let selectedModel: Model
  @ObservedObject var viewModel: ChatViewModel
  var skillCount: Int = 0
  var mcpCount: Int = 0
  var onSendMessage: (Model, [ChatMessage]) -> Void = { _, _ in }
  var onRunAgainClicked: (Model, ChatMessage) -> Void = { _, _ in }
  var onBenchmarkClicked: (Model, ChatMessage, Int, Int) -> Void = { _, _, _, _ in }
  var navigateUp: () -> Void = {}
  var onStreamImageMessage: (Model, ChatMessageImage) -> Void = { _, _ in }
  var onStreamEnd: (Int) -> Void = { _ in }
  var onStopButtonClicked: () -> Void = {}
  var onImageSelected: ([UIImage], Int) -> Void = { _, _ in }
  var onSkillClicked: () -> Void = {}
  var onMcpClicked: () -> Void = {}
  var showStopButtonInInputWhenInProgress: Bool = false
  var showImagePicker: Bool = false
  var showAudioPicker: Bool = false
  var emptyStateView: AnyView = AnyView(EmptyView())

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  @State private var curMessage = ""
  @State private var showBenchmarkDialog = false
  @State private var benchmarkMessage: ChatMessage?
  @State private var showErrorDialog = false
  @State private var showAudioRecorder = false
  @State private var curAmplitude = 0
  @State private var pickedImagesCount = 0
  @State private var pickedAudioClipsCount = 0
  @State private var showImageLimitBanner = false
  @State private var scrollProxy: ScrollViewProxy?
  // Track last message count to trigger auto-scroll
  @State private var lastUserMessageId: UUID?

  private var messages: [ChatMessage] {
    viewModel.uiState.messagesByModel[selectedModel.name] ?? []
  }

  private var modelInitStatus: ModelInitializationStatus? {
    modelManagerViewModel.uiState.modelInitializationStatus[selectedModel.name]
  }

  private var isModelInitializing: Bool {
    modelInitStatus?.status == .initializing
  }

  private var isFirstInitializing: Bool {
    modelInitStatus?.status == .initializing
      && modelInitStatus?.isFirstInitialization(model: selectedModel) == true
  }

  private var imageCountToLastConfigChange: Int {
    var count = 0
    for msg in messages.reversed() {
      if msg is ChatMessageConfigValuesChange { break }
      if let img = msg as? ChatMessageImage { count += img.images.count }
    }
    return count
  }

  private var audioClipCountToLastConfigChange: Int {
    var count = 0
    for msg in messages.reversed() {
      if msg is ChatMessageConfigValuesChange { break }
      if msg is ChatMessageAudioClip { count += 1 }
    }
    return count
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      // Audio recording animation overlay
      if showAudioRecorder {
        Color(colors.surface).opacity(0.8)
          .ignoresSafeArea()
          .transition(.opacity)
      }

      VStack(spacing: 0) {
        // Message list
        ZStack(alignment: .bottom) {
          ScrollViewReader { proxy in
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                  messageRow(message: message, index: index)
                }
                // Bottom anchor for auto-scroll
                Color.clear.frame(height: 1).id("bottomAnchor")
              }
              .padding(.bottom, 8)
            }
            .onAppear { scrollProxy = proxy }
            .onChange(of: messages.count) { _ in
              scrollToBottom(proxy: proxy)
            }
          }

          // Overlay: first-init loading screen
          if isFirstInitializing {
            firstInitOverlay
          }

          // Empty state
          if messages.isEmpty && pickedImagesCount == 0 && pickedAudioClipsCount == 0 && !isFirstInitializing {
            emptyStateView
          }

          // Image limit banner
          if showImageLimitBanner {
            VStack {
              Text(Str.aicoreImageLimitMessage)
                .font(.caption)
                .padding(12)
                .background(colors.surfaceContainerHigh)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 2)
                .padding(.horizontal, 16)
                .padding(.top, 8)
              Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        // Input bar
        MessageInputText(
          task: task,
          modelManagerViewModel: modelManagerViewModel,
          curMessage: $curMessage,
          isResettingSession: viewModel.uiState.isResettingSession,
          inProgress: viewModel.uiState.inProgress,
          imageCount: imageCountToLastConfigChange,
          audioClipMessageCount: audioClipCountToLastConfigChange,
          skillCount: skillCount,
          mcpCount: mcpCount,
          modelInitializing: isModelInitializing,
          modelPreparing: viewModel.uiState.preparing,
          onSendMessage: { msgs in
            onSendMessage(selectedModel, msgs)
            curMessage = ""
          },
          onStopButtonClicked: onStopButtonClicked,
          onSetAudioRecorderVisible: { visible in
            withAnimation { showAudioRecorder = visible }
            if !visible { curAmplitude = 0 }
          },
          onAmplitudeChanged: { curAmplitude = $0 },
          onSkillsClicked: onSkillClicked,
          onMcpClicked: onMcpClicked,
          onPickedImagesChanged: { pickedImagesCount = $0.count },
          onPickedAudioClipsChanged: { pickedAudioClipsCount = $0.count },
          onOpenPromptTemplatesClicked: {
            onSendMessage(selectedModel, [
              ChatMessagePromptTemplates(
                templates: selectedModel.llmPromptTemplates,
                showMakeYourOwn: false
              )
            ])
          },
          onImageLimitExceeded: {
            withAnimation { showImageLimitBanner = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
              withAnimation { showImageLimitBanner = false }
            }
          },
          showSkillsPicker: task.id == BuiltInTaskId.LLM_AGENT_CHAT,
          showMcpPicker: task.id == BuiltInTaskId.LLM_AGENT_CHAT,
          showImagePicker: selectedModel.llmSupportImage && showImagePicker,
          showAudioPicker: selectedModel.llmSupportAudio && showAudioPicker,
          showStopButtonWhenInProgress: showStopButtonInInputWhenInProgress
        )
      }
    }
    .onChange(of: modelInitStatus?.status) { status in
      showErrorDialog = status == .error
    }
    .alert("모델 초기화 오류", isPresented: $showErrorDialog) {
      Button(Str.ok) { showErrorDialog = false }
    } message: {
      Text(modelInitStatus?.error ?? "알 수 없는 오류")
    }
    .sheet(isPresented: $showBenchmarkDialog) {
      BenchmarkConfigDialog(
        messageToBenchmark: benchmarkMessage,
        onDismissed: { showBenchmarkDialog = false },
        onBenchmarkClicked: { msg, warmUp, iterations in
          onBenchmarkClicked(selectedModel, msg, warmUp, iterations)
        }
      )
    }
  }

  // MARK: - Message row builder

  @ViewBuilder
  private func messageRow(message: ChatMessage, index: Int) -> some View {
    let isUser = message.side == .user
    let isAgent = message.side == .agent
    let isSystem = message.side == .system

    // Padding / alignment
    let extraPaddingLeading: CGFloat = {
      if isUser { return 48 }
      if isSystem {
        return message.type == .promptTemplates ? 12 : 24
      }
      return 0
    }()
    let extraPaddingTrailing: CGFloat = {
      if isUser { return 0 }
      if isSystem {
        return message.type == .promptTemplates ? 12 : 24
      }
      if isAgent {
        if message.type == .loading || message.type == .webview || message.type == .collapsableProgressPanel {
          return 0
        }
        if message.type == .text { return 0 }
        return 48
      }
      return 0
    }()

    let hAlignment: HorizontalAlignment = isUser ? .trailing : .leading

    MessageColumn {
      // Sender label
      let agentName: String = {
        var name = task.agentName
        if !message.accelerator.isEmpty { name += " on \(message.accelerator)" }
        return name
      }()

      if !message.hideSenderLabel {
        MessageSender(
          message: message,
          agentName: agentName,
          imageHistoryCurIndex: imageHistoryCurIndexFor(message: message)
        )
        .padding(.horizontal, 4)
      }

      // Body
      let useBubble = !message.disableBubbleShape && !(message.type == .text && isAgent)
      if useBubble {
        bubbleStyled(body: AnyView(messageBody(message: message)), message: message, isAgent: isAgent, isUser: isUser)
      } else {
        messageBody(message: message)
      }

      // Agent action row (latency + copy)
      if isAgent {
        HStack(spacing: 8) {
          LatencyText(message: message)
          if let txt = message as? ChatMessageText, !viewModel.uiState.inProgress {
            Button {
              UIPasteboard.general.string = txt.content
            } label: {
              Image(systemName: "doc.on.doc")
                .frame(width: 28, height: 28)
                .foregroundColor(colors.onSurfaceVariant.opacity(0.6))
            }
            .buttonStyle(.plain)
          }
        }
      }

      // User action buttons (run again, benchmark)
      if isUser {
        HStack(spacing: 4) {
          if selectedModel.showRunAgainButton {
            MessageActionButton(
              label: Str.runAgain,
              systemImage: "arrow.clockwise",
              onClick: { onRunAgainClicked(selectedModel, message) },
              enabled: !viewModel.uiState.inProgress
            )
          }
          if selectedModel.showBenchmarkButton {
            MessageActionButton(
              label: Str.runBenchmark,
              systemImage: "timer",
              onClick: {
                benchmarkMessage = message
                showBenchmarkDialog = true
              },
              enabled: !viewModel.uiState.inProgress
            )
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    .padding(.leading, 16 + extraPaddingLeading)
    .padding(.trailing, 12 + extraPaddingTrailing)
    .padding(.vertical, 6)
  }

  @ViewBuilder
  private func messageBody(message: ChatMessage) -> some View {
    switch message {
    case let m as ChatMessageLoading:
      MessageBodyLoading(message: m)
    case let m as ChatMessageInfo:
      MessageBodyInfo(message: m)
    case let m as ChatMessageWarning:
      MessageBodyWarning(message: m)
    case let m as ChatMessageError:
      MessageBodyError(message: m)
    case let m as ChatMessageConfigValuesChange:
      MessageBodyConfigUpdate(message: m)
    case let m as ChatMessagePromptTemplates:
      MessageBodyPromptTemplates(message: m, task: task) { template in
        onSendMessage(selectedModel, [ChatMessageText(content: template.prompt, side: .user)])
      }
    case let m as ChatMessageText:
      MessageBodyText(
        message: m,
        inProgress: viewModel.uiState.inProgress,
        horizontalPadding: (m.type == .text && m.side == .agent) ? 0 : 12,
        onCopyClicked: { UIPasteboard.general.string = $0 }
      )
    case let m as ChatMessageImage:
      MessageBodyImage(message: m, onImageClicked: onImageSelected)
    case let m as ChatMessageAudioClip:
      MessageBodyAudioClip(message: m)
    case let m as ChatMessageBenchmarkResult:
      MessageBodyBenchmark(message: m)
    case let m as ChatMessageBenchmarkLlmResult:
      MessageBodyBenchmarkLlm(message: m)
    case let m as ChatMessageWebView:
      MessageBodyWebview(message: m)
    case let m as ChatMessageCollapsableProgressPanel:
      MessageBodyCollapsableProgressPanel(message: m)
    case let m as ChatMessageThinking:
      MessageBodyThinking(
        thinkingText: m.content,
        inProgress: m.inProgress,
        onCopyClicked: { UIPasteboard.general.string = $0 }
      )
    case let m as ChatMessageImageWithHistory:
      imageWithHistoryBody(message: m)
    case let m as ChatMessageClassification:
      MessageBodyClassification(message: m)
    default:
      EmptyView()
    }
  }

  // Separate subview for ImageWithHistory to manage its @State
  @ViewBuilder
  private func imageWithHistoryBody(message: ChatMessageImageWithHistory) -> some View {
    ImageWithHistoryWrapper(message: message)
  }

  @ViewBuilder
  private func bubbleStyled(body: AnyView, message: ChatMessage, isAgent: Bool, isUser: Bool) -> some View {
    let isMultiImage = (message as? ChatMessageImage)?.images.count ?? 0 > 1
    let bgColor: Color = {
      if message.type == .image { return .clear }
      return isUser ? customColors.userBubbleBgColor : customColors.agentBubbleBgColor
    }()

    if isMultiImage {
      body.clipShape(RoundedRectangle(cornerRadius: 6)).background(bgColor)
    } else {
      body
        .background(bgColor)
        .clipShape(
          MessageBubbleShape(
            radius: CHAT_BUBBLE_CORNER_RADIUS,
            hardCornerAtLeftOrRight: isAgent
          )
        )
    }
  }

  // MARK: - Helpers

  private func imageHistoryCurIndexFor(message: ChatMessage) -> Int {
    // ChatMessageImageWithHistory current index is managed by ImageWithHistoryWrapper
    return 0
  }

  private func scrollToBottom(proxy: ScrollViewProxy) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      withAnimation(.easeOut(duration: 0.3)) {
        proxy.scrollTo("bottomAnchor", anchor: .bottom)
      }
    }
  }

  @ViewBuilder
  private var firstInitOverlay: some View {
    ZStack {
      colors.surface.ignoresSafeArea()
      VStack(spacing: 8) {
        ProgressView()
          .progressViewStyle(.circular)
          .scaleEffect(1.5)
        Text(Str.aichatInitializingTitle)
          .font(.title2).fontWeight(.bold)
        Text(Str.aichatInitializingContent)
          .font(.body)
          .foregroundColor(colors.onSurfaceVariant)
          .multilineTextAlignment(.center)
      }
    }
    .transition(.opacity.combined(with: .scale(scale: 0.9)))
  }
}

// MARK: - Helper container view

/// Simple VStack-like column helper so messageRow body compiles as ViewBuilder chain.
private struct MessageColumn<Content: View>: View {
  @ViewBuilder let content: () -> Content
  var body: some View { VStack(alignment: .leading, spacing: 2) { content() } }
}

/// Wraps ChatMessageImageWithHistory to own the @State curIndex.
private struct ImageWithHistoryWrapper: View {
  let message: ChatMessageImageWithHistory
  @State private var curIndex = 0

  var body: some View {
    MessageBodyImageWithHistory(message: message, curIndex: $curIndex)
  }
}
