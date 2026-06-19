/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageInputText.kt
//
// NOTE: CameraX (Android) → not used on iOS. Camera capture uses UIImagePickerController
// via PhotosUI's PhotosPicker. Audio permission is NSMicrophoneUsageDescription in Info.plist.
// Photo library permission is NSPhotoLibraryUsageDescription in Info.plist.

import SwiftUI
import PhotosUI
import AVFoundation

// AudioClip is defined in Common/Types.swift.
// MAX_IMAGE_COUNT / MAX_AUDIO_CLIP_COUNT are defined in Data/Consts.swift.
private let SAMPLE_RATE_FOR_CLIP = 16000

struct MessageInputText: View {
  let task: Task
  @ObservedObject var modelManagerViewModel: ModelManagerViewModel
  @Binding var curMessage: String

  var isResettingSession: Bool = false
  var inProgress: Bool = false
  var imageCount: Int = 0
  var audioClipMessageCount: Int = 0
  var skillCount: Int = 0
  var mcpCount: Int = 0
  var modelInitializing: Bool = false
  var modelPreparing: Bool = false

  var onSendMessage: ([ChatMessage]) -> Void = { _ in }
  var onStopButtonClicked: () -> Void = {}
  var onSetAudioRecorderVisible: (Bool) -> Void = { _ in }
  var onAmplitudeChanged: (Int) -> Void = { _ in }
  var onSkillsClicked: () -> Void = {}
  var onMcpClicked: () -> Void = {}
  var onPickedImagesChanged: ([UIImage]) -> Void = { _ in }
  var onPickedAudioClipsChanged: ([AudioClip]) -> Void = { _ in }  // AudioClip from Common/Types.swift
  var onOpenPromptTemplatesClicked: () -> Void = {}
  var onImageLimitExceeded: () -> Void = {}

  var showPromptTemplatesInMenu: Bool = false
  var showSkillsPicker: Bool = false
  var showMcpPicker: Bool = false
  var showImagePicker: Bool = false
  var showAudioPicker: Bool = false
  var showStopButtonWhenInProgress: Bool = false

  @State private var pickedImages: [UIImage] = []
  @State private var pickedAudioClips: [AudioClip] = []
  @State private var showAddContentMenu = false
  @State private var showTextInputHistorySheet = false
  @State private var showAudioRecorder = false
  @State private var showPhotoPicker = false
  @State private var photoPickerItems: [PhotosPickerItem] = []
  @State private var showFilePicker = false

  @Environment(\.galleryColors) private var colors
  @Environment(\.customColors) private var customColors

  private var taskIconColor: Color {
    let idx = task.index >= 0 ? task.index % customColors.taskIconColors.count : 0
    return customColors.taskIconColors.isEmpty ? colors.primary : customColors.taskIconColors[idx]
  }

  private var canSend: Bool {
    !inProgress && !isResettingSession
      && (!curMessage.isEmpty || !pickedAudioClips.isEmpty || !pickedImages.isEmpty)
  }

  private var addButtonEnabled: Bool {
    !inProgress && !isResettingSession && !modelInitializing
  }

  var body: some View {
    VStack(spacing: 0) {
      // Preview strip for picked media
      if !pickedImages.isEmpty || !pickedAudioClips.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 16) {
            Spacer().frame(width: 0)
            ForEach(pickedImages.indices, id: \.self) { i in
              ZStack(alignment: .topTrailing) {
                Image(uiImage: pickedImages[i])
                  .resizable()
                  .scaledToFill()
                  .frame(width: 80, height: 80)
                  .clipShape(RoundedRectangle(cornerRadius: 8))
                  .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.outline, lineWidth: 1))
                  .shadow(radius: 2)
                Button {
                  pickedImages.remove(at: i)
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundColor(colors.onSurface)
                    .background(Circle().fill(colors.surface))
                }
                .offset(x: 8, y: -8)
              }
            }
            ForEach(pickedAudioClips.indices, id: \.self) { i in
              let clip = pickedAudioClips[i]
              ZStack(alignment: .topTrailing) {
                AudioPlaybackPanel(
                  audioData: clip.audioData,
                  sampleRate: clip.sampleRate
                )
                .padding(.trailing, 8)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.outline, lineWidth: 1))
                .shadow(radius: 2)
                Button {
                  pickedAudioClips.remove(at: i)
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundColor(colors.onSurface)
                    .background(Circle().fill(colors.surface))
                }
                .offset(x: 8, y: -8)
              }
            }
            Spacer().frame(width: 0)
          }
          .padding(.vertical, 8)
        }
      }

      // Main input row
      ZStack {
        if showAudioRecorder {
          AudioRecorderPanel(
            task: task,
            onAmplitudeChanged: onAmplitudeChanged,
            onSendAudioClip: { data in
              let clip = AudioClip(audioData: data, sampleRate: SAMPLE_RATE_FOR_CLIP)
              DispatchQueue.main.async {
                let maxAllowed = max(0, MAX_AUDIO_CLIP_COUNT - audioClipMessageCount)
                if pickedAudioClips.count < maxAllowed {
                  pickedAudioClips.append(clip)
                }
                showAudioRecorder = false
                onSetAudioRecorderVisible(false)
              }
            },
            onClose: {
              showAudioRecorder = false
              onSetAudioRecorderVisible(false)
            }
          )
          .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
          inputField
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .animation(.spring(response: 0.3), value: showAudioRecorder)
    }
    .onChange(of: pickedImages) { onPickedImagesChanged($0) }
    .onChange(of: pickedAudioClips) { onPickedAudioClipsChanged($0) }
    .onChange(of: photoPickerItems) { items in
      _Concurrency.Task {
        var bitmaps: [UIImage] = []
        for item in items {
          if let data = try? await item.loadTransferable(type: Data.self),
             let img = UIImage(data: data) {
            bitmaps.append(img)
          }
        }
        if !bitmaps.isEmpty {
          let maxAllowed = max(0, MAX_IMAGE_COUNT - imageCount - pickedImages.count)
          if bitmaps.count <= maxAllowed {
            pickedImages += bitmaps
          } else {
            onImageLimitExceeded()
            pickedImages += Array(bitmaps.prefix(maxAllowed))
          }
        }
        photoPickerItems = []
      }
    }
    // Text input history sheet
    .sheet(isPresented: $showTextInputHistorySheet) {
      TextInputHistorySheet(
        history: modelManagerViewModel.uiState.textInputHistory,
        onHistoryItemClicked: { item in
          let msgs = createMessagesToSend(
            images: pickedImages, audioClips: pickedAudioClips, text: item)
          onSendMessage(msgs)
          pickedImages = []
          pickedAudioClips = []
          modelManagerViewModel.promoteTextInputHistoryItem(item)
          showTextInputHistorySheet = false
        },
        onHistoryItemDeleted: { modelManagerViewModel.deleteTextInputHistory($0) },
        onHistoryItemsDeleteAll: { modelManagerViewModel.clearTextInputHistory() },
        onDismissed: { showTextInputHistorySheet = false }
      )
    }
    // Image picker
    .photosPicker(
      isPresented: $showPhotoPicker,
      selection: $photoPickerItems,
      maxSelectionCount: MAX_IMAGE_COUNT,
      matching: .images
    )
  }

  // MARK: - Main text field + bottom buttons

  @ViewBuilder
  private var inputField: some View {
    VStack(spacing: 0) {
      // Text field row
      HStack(alignment: .center) {
        TextField(task.textInputPlaceHolder, text: $curMessage, axis: .vertical)
          .lineLimit(1...3)
          .font(.body)
          .padding(.leading, 4)
          .frame(maxWidth: .infinity)
      }
      .padding(.horizontal, 12)

      // Buttons row
      HStack(alignment: .center, spacing: 4) {
        // + / add-content button
        Menu {
          if showImagePicker {
            // NOTE: No CameraX on iOS. Using PhotosPicker for album images.
            // Camera capture uses UIImagePickerController (sourceType: .camera).
            Button {
              showPhotoPicker = true
            } label: {
              Label("앨범에서 선택", systemImage: "photo")
            }
          }

          if showAudioPicker {
            Button {
              requestMicPermissionAndRecord()
            } label: {
              Label("오디오 클립 녹음", systemImage: "mic")
            }

            Button {
              showFilePicker = true
            } label: {
              Label("WAV 파일 선택", systemImage: "waveform")
            }
          }

          Button {
            showTextInputHistorySheet = true
          } label: {
            Label("입력 기록", systemImage: "clock.arrow.circlepath")
          }
        } label: {
          Image(systemName: "plus")
            .foregroundColor(addButtonEnabled ? colors.onSurface : colors.onSurface.opacity(0.2))
            .frame(width: 36, height: 36)
            .overlay(
              RoundedRectangle(cornerRadius: 8)
                .stroke(
                  addButtonEnabled
                    ? colors.outlineVariant
                    : colors.outlineVariant.opacity(0.1),
                  lineWidth: 1
                )
            )
        }
        .disabled(!addButtonEnabled)

        // Skills button
        if showSkillsPicker {
          Button(action: onSkillsClicked) {
            HStack(spacing: 4) {
              Text("스킬")
              Text("\(skillCount)")
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(colors.surfaceContainer, in: Capsule())
            }
            .font(.subheadline)
          }
          .buttonStyle(.bordered)
          .disabled(!addButtonEnabled)
        }

        // MCP button
        if showMcpPicker {
          Button(action: onMcpClicked) {
            HStack(spacing: 4) {
              Text("MCP")
              Text("\(mcpCount)")
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(colors.surfaceContainer, in: Capsule())
            }
            .font(.subheadline)
          }
          .buttonStyle(.bordered)
          .disabled(!addButtonEnabled)
        }

        Spacer()

        // Stop or send button
        if inProgress && showStopButtonWhenInProgress && !modelInitializing && !modelPreparing {
          Button(action: onStopButtonClicked) {
            Image(systemName: "stop.fill")
              .foregroundColor(colors.primary)
              .frame(width: 40, height: 40)
              .background(colors.secondaryContainer)
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
        } else {
          Button {
            let text = curMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            let msgs = createMessagesToSend(images: pickedImages, audioClips: pickedAudioClips, text: text)
            onSendMessage(msgs)
            pickedImages = []
            pickedAudioClips = []
          } label: {
            Image(systemName: "paperplane.fill")
              .rotationEffect(.degrees(0))
              .foregroundColor(.white)
              .frame(width: 40, height: 40)
              .background(canSend ? taskIconColor : taskIconColor.opacity(0.3))
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
          .disabled(!canSend)
        }
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 8)
      .offset(y: -8)
    }
    .padding(.vertical, 8)
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(colors.outlineVariant, lineWidth: 1)
    )
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    // File picker for WAV
    .fileImporter(
      isPresented: $showFilePicker,
      allowedContentTypes: [.audio],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      _Concurrency.Task.detached { @MainActor in
        if let data = try? Data(contentsOf: url) {
          let stripped = self.stripWavHeader(data)
          let clip = AudioClip(audioData: stripped, sampleRate: SAMPLE_RATE_FOR_CLIP)
          let maxAllowed = max(0, MAX_AUDIO_CLIP_COUNT - self.audioClipMessageCount)
          if self.pickedAudioClips.count < maxAllowed {
            self.pickedAudioClips.append(clip)
          }
        }
      }
    }
  }

  // MARK: - Helpers

  private func requestMicPermissionAndRecord() {
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      DispatchQueue.main.async {
        if granted {
          showAudioRecorder = true
          onSetAudioRecorderVisible(true)
        }
      }
    }
  }

  private func stripWavHeader(_ data: Data) -> Data {
    let headerSize = 44
    return data.count > headerSize ? data.subdata(in: headerSize..<data.count) : data
  }

  private func createMessagesToSend(
    images: [UIImage],
    audioClips: [AudioClip],
    text: String
  ) -> [ChatMessage] {
    var msgs: [ChatMessage] = []
    if !images.isEmpty {
      msgs.append(ChatMessageImage(images: Array(images.prefix(MAX_IMAGE_COUNT)), side: .user))
    }
    for clip in Array(audioClips.prefix(MAX_AUDIO_CLIP_COUNT)) {
      msgs.append(ChatMessageAudioClip(audioData: clip.audioData, sampleRate: clip.sampleRate, side: .user))
    }
    if !text.isEmpty {
      msgs.append(ChatMessageText(content: text, side: .user))
    }
    return msgs
  }
}
