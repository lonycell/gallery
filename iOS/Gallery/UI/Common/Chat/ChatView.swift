/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/ChatView.kt
//
// The reusable chat screen: scrolling message list + input bar.
// Feature screens (LlmChat, AgentChat) embed this view.
// Mirrors the Kotlin ChatView @Composable signature faithfully.

import SwiftUI

/// Trigger data for externally-initiated send (e.g. deep-link query).
struct SendMessageTrigger: Equatable {
  let model: Model
  let messages: [ChatMessage]
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.model.name == rhs.model.name }
}

/// Helper to build a history-prefixed first message when restoring a session.
private func buildFirstMessageWithHistory(
  history: [ChatMessage],
  originalShortMessage: ChatMessageText
) -> ChatMessageText? {
  let prefix = history.compactMap { msg -> String? in
    guard let txt = msg as? ChatMessageText else { return nil }
    return txt.side == .user ? "User:\n\(txt.content)" : "Model:\n\(txt.content)"
  }.joined(separator: "\n\n")
  guard !prefix.isEmpty else { return nil }
  return ChatMessageText(
    content: "\(prefix)\n\nUser:\n\(originalShortMessage.content)",
    side: originalShortMessage.side,
    latencyMs: originalShortMessage.latencyMs,
    isMarkdown: originalShortMessage.isMarkdown,
    llmBenchmarkResult: originalShortMessage.llmBenchmarkResult,
    accelerator: originalShortMessage.accelerator,
    hideSenderLabel: originalShortMessage.hideSenderLabel,
    data: originalShortMessage.data
  )
}

/// Deserializes persisted proto messages back into the UI ChatMessage hierarchy.
private func deserializeProtoMessages(_ protos: [ChatMessageProto]) -> [ChatMessage] {
  protos.compactMap { p in
    let side: ChatSide = {
      switch p.side {
      case .user: return .user
      case .model: return .agent
      default: return .system
      }
    }()
    switch p.messageType {
    case "TEXT":
      return ChatMessageText(content: p.content, side: side, latencyMs: p.latencyMs,
                             isMarkdown: p.isMarkdown, accelerator: p.accelerator,
                             hideSenderLabel: p.hideSenderLabel)
    case "THINKING":
      return ChatMessageThinking(content: p.content, inProgress: p.inProgress, side: side,
                                 hideSenderLabel: p.hideSenderLabel, accelerator: p.accelerator)
    case "INFO":   return ChatMessageInfo(content: p.content)
    case "WARNING": return ChatMessageWarning(content: p.content)
    case "ERROR":  return ChatMessageError(content: p.content)
    case "IMAGE":
      let images = p.imageFilePaths.compactMap { path in
        (try? Data(contentsOf: URL(fileURLWithPath: path))).flatMap { UIImage(data: $0) }
      }
      guard !images.isEmpty else { return nil }
      return ChatMessageImage(images: images, side: side, latencyMs: p.latencyMs,
                              accelerator: p.accelerator, hideSenderLabel: p.hideSenderLabel,
                              persistedPaths: p.imageFilePaths)
    case "AUDIO_CLIP":
      guard let first = p.audioClips.first,
            let data = try? Data(contentsOf: URL(fileURLWithPath: first.filePath)) else { return nil }
      return ChatMessageAudioClip(audioData: data, sampleRate: Int(first.sampleRate),
                                  side: side, latencyMs: p.latencyMs,
                                  persistedPath: first.filePath)
    default:
      return nil
    }
  }
}

// MARK: - ChatView

struct ChatView: View {
  // Required parameters
  let task: Task
  @ObservedObject var viewModel: ChatViewModel
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  var onSendMessage: (Model, [ChatMessage]) -> Void = { _, _ in }
  var onRunAgainClicked: (Model, ChatMessage) -> Void = { _, _ in }
  var onBenchmarkClicked: (Model, ChatMessage, Int, Int) -> Void = { _, _, _, _ in }
  var navigateUp: () -> Void = {}

  // Optional parameters mirroring Kotlin defaults
  var skillCount: Int = 0
  var mcpCount: Int = 0
  var onResetSessionClicked: (Model, [ChatMessage], Bool, () -> Void) -> Void = { _, _, _, done in done() }
  var onStreamImageMessage: (Model, ChatMessageImage) -> Void = { _, _ in }
  var onStopButtonClicked: (Model) -> Void = { _ in }
  var onSkillClicked: () -> Void = {}
  var onMcpClicked: () -> Void = {}
  var showStopButtonInInputWhenInProgress: Bool = false
  var composableBelowMessageList: ((Model) -> AnyView)? = nil
  var showImagePicker: Bool = false
  var showAudioPicker: Bool = false
  var emptyStateView: ((Model) -> AnyView)? = nil
  var allowEditingSystemPrompt: Bool = false
  var curSystemPrompt: String = ""
  var onSystemPromptChanged: (String) -> Void = { _ in }
  var sendMessageTrigger: SendMessageTrigger? = nil

  // Internal state
  @State private var selectedImageIndex = -1
  @State private var allImageViewerImages: [UIImage] = []
  @State private var showImageViewer = false
  @State private var showHistorySheet = false
  @State private var snackbarMessage: String? = nil

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  private var selectedModel: Model { modelManagerViewModel.uiState.selectedModel }
  private var modelDownloadStatus: ModelDownloadStatus? {
    modelManagerViewModel.uiState.modelDownloadStatus[selectedModel.name]
  }
  private var isModelDownloaded: Bool { modelDownloadStatus?.status == .succeeded }
  private var historySessions: [ChatSessionProto] {
    viewModel.historySessions.filter { $0.taskId == task.id }
  }

  var body: some View {
    ZStack {
      // Optional below-message-list layer (e.g. camera preview)
      composableBelowMessageList?(selectedModel)

      VStack(spacing: 0) {
        // Main content: either chat panel or download panel
        if isModelDownloaded {
          ChatPanel(
            modelManagerViewModel: modelManagerViewModel,
            task: task,
            selectedModel: selectedModel,
            viewModel: viewModel,
            skillCount: skillCount,
            mcpCount: mcpCount,
            onSendMessage: onSendMessage,
            onRunAgainClicked: onRunAgainClicked,
            onBenchmarkClicked: onBenchmarkClicked,
            navigateUp: navigateUp,
            onStreamImageMessage: onStreamImageMessage,
            onStreamEnd: { fps in
              viewModel.addMessage(
                model: selectedModel,
                message: ChatMessageInfo(content: "라이브 카메라 세션 종료됨. 평균 FPS: \(fps)")
              )
            },
            onStopButtonClicked: { onStopButtonClicked(selectedModel) },
            onImageSelected: { images, index in
              selectedImageIndex = index
              allImageViewerImages = images
              showImageViewer = true
            },
            onSkillClicked: onSkillClicked,
            onMcpClicked: onMcpClicked,
            showStopButtonInInputWhenInProgress: showStopButtonInInputWhenInProgress,
            showImagePicker: showImagePicker,
            showAudioPicker: showAudioPicker,
            emptyStateView: emptyStateView?(selectedModel) ?? AnyView(EmptyView())
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .transition(.opacity)
        } else {
          ModelDownloadStatusInfoPanel(
            model: selectedModel,
            task: task,
            modelManagerViewModel: modelManagerViewModel
          )
          .transition(.opacity)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: isModelDownloaded)

      // Snackbar
      if let msg = snackbarMessage {
        VStack {
          Spacer()
          Text(msg)
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(colors.inverseSurface)
            .foregroundColor(colors.inverseOnSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 100)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
    }
    // Image viewer fullscreen
    .fullScreenCover(isPresented: $showImageViewer) {
      imageViewerScreen
    }
    // Chat history side sheet
    .sheet(isPresented: $showHistorySheet) {
      NavigationView {
        ChatHistorySideSheetContent(
          history: historySessions,
          onHistoryItemClicked: { sessionId in
            if let session = historySessions.first(where: { $0.sessionId == sessionId }) {
              Task {
                viewModel.setIsResettingSession(true)
                let messages = deserializeProtoMessages(session.messages)
                viewModel.clearAllMessages(model: selectedModel)
                for msg in messages { viewModel.addMessage(model: selectedModel, message: msg) }
                onResetSessionClicked(selectedModel, messages, false) {
                  viewModel.setIsResettingSession(false)
                }
                viewModel.currentSessionId = session.sessionId
              }
            }
            showHistorySheet = false
          },
          onHistoryItemDeleted: { sessionId in
            viewModel.deleteSession(sessionId: sessionId)
            if sessionId == viewModel.currentSessionId {
              onResetSessionClicked(selectedModel, [], true) {}
              viewModel.currentSessionId = UUID().uuidString
            }
          },
          onHistoryItemsDeleteAll: {
            viewModel.clearAllSessions()
            onResetSessionClicked(selectedModel, [], true) {}
            viewModel.currentSessionId = UUID().uuidString
            showHistorySheet = false
          },
          onNewChatClicked: {
            onResetSessionClicked(selectedModel, [], true) {}
            viewModel.currentSessionId = UUID().uuidString
            showHistorySheet = false
          },
          onDismissed: { showHistorySheet = false }
        )
      }
    }
    // Trigger external send
    .onChange(of: sendMessageTrigger) { trigger in
      if let t = trigger { onSendMessage(t.model, t.messages) }
    }
    // Auto-save session when response completes
    .onChange(of: viewModel.uiState.inProgress) { inProgress in
      if !inProgress {
        let msgs = viewModel.uiState.messagesByModel[selectedModel.name] ?? []
        if !msgs.isEmpty {
          viewModel.saveSession(
            sessionId: viewModel.currentSessionId,
            messages: msgs,
            originalModel: selectedModel.name,
            taskId: task.id
          )
        }
      }
    }
    // Initialize model when download status changes to succeeded
    .onChange(of: modelDownloadStatus?.status) { status in
      if status == .succeeded {
        modelManagerViewModel.initializeModel(task: task, model: selectedModel)
      }
    }
    // Expose history button via toolbar (integrators can override the toolbar)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          showHistorySheet = true
        } label: {
          Image(systemName: "clock.arrow.circlepath")
        }
      }
    }
  }

  // MARK: - Image Viewer

  @ViewBuilder
  private var imageViewerScreen: some View {
    ZStack {
      Color.black.opacity(0.95).ignoresSafeArea()

      // Pager
      if !allImageViewerImages.isEmpty {
        TabView(selection: $selectedImageIndex) {
          ForEach(allImageViewerImages.indices, id: \.self) { i in
            ZoomableImage(image: allImageViewerImages[i])
              .tag(i)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
      }

      // Top: back button
      VStack {
        HStack {
          Button {
            showImageViewer = false
          } label: {
            Image(systemName: "arrow.left")
              .foregroundColor(.white)
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .padding(.leading, 16)
          Spacer()
        }
        .padding(.top, 8)
        Spacer()

        // Bottom: Share, Copy, Save
        if let curImage = allImageViewerImages.indices.contains(selectedImageIndex)
            ? allImageViewerImages[selectedImageIndex] : nil {
          HStack(spacing: 32) {
            imageViewerActionButton(
              systemImage: "square.and.arrow.up",
              label: Str.share
            ) {
              shareImage(curImage)
            }
            imageViewerActionButton(
              systemImage: "doc.on.doc",
              label: Str.copy
            ) {
              UIPasteboard.general.image = curImage
              showSnackbar("클립보드에 복사되었습니다.")
            }
            imageViewerActionButton(
              systemImage: "square.and.arrow.down",
              label: Str.save
            ) {
              saveImageToPhotos(curImage)
            }
          }
          .padding(.bottom, 32)
        }
      }
    }
  }

  @ViewBuilder
  private func imageViewerActionButton(
    systemImage: String,
    label: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: systemImage).foregroundColor(.white)
        Text(label).foregroundColor(.white).font(.caption2)
      }
      .frame(width: 64, height: 64)
    }
    .buttonStyle(.plain)
  }

  private func shareImage(_ image: UIImage) {
    let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let rootVC = windowScene.windows.first?.rootViewController {
      rootVC.present(vc, animated: true)
    }
  }

  private func saveImageToPhotos(_ image: UIImage) {
    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    showSnackbar("사진 앨범에 저장되었습니다.")
  }

  private func showSnackbar(_ message: String) {
    withAnimation { snackbarMessage = message }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
      withAnimation { snackbarMessage = nil }
    }
  }
}
