// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Port of customtasks/voiceassistant/VoiceAssistantViewModel.kt
//
// Android used android.speech.SpeechRecognizer + TextToSpeech + sherpa-onnx.
// iOS uses AVSpeechSynthesizer / SFSpeechRecognizer directly.
// NOTE: Replace stub speech engines with real implementations when available.

import Foundation
import AVFoundation
import Speech
import Combine

// MARK: - Shared data types

/// A single message in the voice conversation (distinct from the Chat foundation's
/// `ChatMessage` which is richer — this module keeps its own lean type).
struct VoiceMessage: Equatable {
    enum Role { case user, assistant }
    let role: Role
    let text: String
    var isStreaming: Bool = false
}

/// A selectable TTS voice.
struct VoiceOption: Identifiable, Equatable {
    let id: String
    let label: String
    var subtitle: String = ""
    var isNeural: Bool = false
    var isCloud: Bool = false
}

/// Neural-voice / STT download/preparation lifecycle.
enum NeuralVoiceStage { case notInstalled, downloading, preparing, ready, error }

/// Detailed state of the neural-voice preparation pipeline.
struct NeuralVoiceState: Equatable {
    var stage: NeuralVoiceStage = .notInstalled
    var downloadPercent: Int = -1
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var bytesPerSecond: Int64 = 0
    var remainingMs: Int64 = 0
    var unpackPercent: Int = -1
    var error: String = ""
}

/// Availability of a downloadable neural recognizer.
struct NeuralSttState: Equatable {
    var stage: NeuralVoiceStage = .notInstalled
    var downloadPercent: Int = -1
    var bytesPerSecond: Int64 = 0
    var remainingMs: Int64 = 0
    var error: String = ""
}

/// Which engine recognizes the user's speech.
enum SttEngine { case system, neural, whisper }

/// When the assistant's spoken reply is produced.
enum TtsSpeakMode { case afterComplete, streaming }

/// How the user provides input.
enum ChatInputMode { case standard, call }

/// Full UI state for the Voice Assistant.
struct VoiceAssistantUiState {
    var messages: [VoiceMessage] = []
    var isListening: Bool = false
    var isSpeaking: Bool = false
    var isThinking: Bool = false
    var partialTranscript: String = ""
    var error: String = ""
    var topicTitle: String = ""
    var starters: [String] = []
    var ttsReady: Bool = false
    var voices: [VoiceOption] = []
    var selectedVoiceId: String = ""
    var speakMode: TtsSpeakMode = .afterComplete
    var neuralVoice: NeuralVoiceState = NeuralVoiceState()
    var meloVoice: NeuralVoiceState = NeuralVoiceState()
    var sttEngine: SttEngine = .system
    var neuralStt: NeuralSttState = NeuralSttState()
    var whisperStt: NeuralSttState = NeuralSttState()
    var mcpToolCount: Int = 0
    var skillCount: Int = 0
    var toolActivity: String = ""
    var inputMode: ChatInputMode = .standard
}

// MARK: - VAPermissionResult (mirrors common/Types.kt)

enum VAPermissionResult { case allow, alwaysAllow, deny }

// MARK: - MCP permission request (stub until AgentChat is ported)

/// Pending MCP tool-call permission request surfaced as a dialog.
struct McpToolCallPermissionRequest: Identifiable {
    let id = UUID()
    let toolName: String
    let argument: String
    /// Call this continuation with the user's decision to unblock the tool call.
    var completion: (VAPermissionResult) -> Void
}

// MARK: - Call-mode timing constants

private let CALL_RELISTEN_DEBOUNCE_MS: UInt64   = 450_000_000
private let GENERATION_STALL_TIMEOUT_NS: UInt64 = 45_000_000_000
private let CALL_SILENT_COOLDOWN_NS: UInt64     = 1_100_000_000
private let CALL_SILENT_BACKOFF_CAP             = 3
private let STREAMING_SOFT_FLUSH_CHARS          = 60
private let SENTENCE_TERMINATORS: [Swift.Character]   = [".", "!", "?", "…", "。", "！", "？", "\n"]

private let GREETING_PROMPT =
    "(사용자가 방금 너와 대화를 시작했어. 너의 성격과 말투를 살려서, 짧고 자연스럽게 먼저 인사하며 " +
    "말을 걸어줘. 한두 문장으로만 해줘.)"
private let CONTINUE_PROMPT =
    "(사용자는 말없이 너의 이야기를 더 듣고 싶어 해. 지금까지의 흐름을 이어서, 너의 성격과 말투를 살려 " +
    "자연스럽게 한두 문장 더 이야기를 건네줘. 대화가 처음이라면 가볍게 먼저 말을 걸어줘.)"

// MARK: - VoiceAssistantViewModel

@MainActor
final class VoiceAssistantViewModel: ObservableObject {

    @Published private(set) var uiState = VoiceAssistantUiState()

    // Per-conversation history, keyed by characterId.
    private var messagesByConversation: [String: [VoiceMessage]] = [:]
    private var activeConversationId: String = ""

    // Emotion cue publisher — one-shot emoji bursts for the overlay.
    let emotionCues = PassthroughSubject<EmotionCue, Never>()
    private var emotionCueSeq: Int64 = 0

    private let promptSource: VoiceAssistantPromptSource
    private let entryParams: VoiceAssistantEntryParams
    private let chatHistoryStore: ChatHistoryStore
    private let characterRepository: CharacterRepository

    /// The model the ViewModel speaks to (set by the screen / wiring).
    private var pendingModel: Model?

    // MARK: - TTS
    // NOTE: The iOS port uses AVSpeechSynthesizer (system TTS) as the default.
    // When neural (sherpa-onnx VITS / MeloTTS) engines are available, inject them
    // via `onKoreanTtsStatus` / `onMeloTtsStatus` and they will be offered as selectable
    // voices. The `NeuralTtsEngine` protocol in Speech/KoreanNeuralTts.swift is the bridge.
    private let synthesizer = AVSpeechSynthesizer()
    private var ttsDelegate: SynthDelegate?
    private var neuralTts: NeuralTtsEngine?
    private var meloTts: NeuralTtsEngine?
    private let audioPlayer = AudioPlayer()

    // Streaming TTS (sentence-by-sentence) state.
    private var speakChannel: AsyncStream<String>.Continuation?
    private var speakConsumerTask: _Concurrency.Task<Void, Never>?
    private var spokenChars = 0
    private var streamingTurnActive = false

    // MARK: - STT
    // NOTE: The iOS port uses SFSpeechRecognizer as the system engine.
    // Neural (sherpa-onnx SenseVoice / Whisper) engines map to `NeuralSttEngine`
    // stubs (not yet ported). Use `selectSttEngine(.system)` until they arrive.
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var consecutiveSilentTurns = 0
    private var usingNeuralCapture = false
    private let audioRecorder = AudioRecorder(sampleRate: SPEECH_SAMPLE_RATE)

    // Neural STT stubs (populated when the downloads complete).
    private var neuralSttEngine: Any? = nil  // NOTE: Replace with NeuralSttEngine when ported.
    private var loadedSttEngine: SttEngine? = nil

    // MARK: - Call-mode loop
    private var callLoopTask: _Concurrency.Task<Void, Never>?

    // MARK: - Generation tracking
    private var generationSeq: Int64 = 0
    private var watchdogTask: _Concurrency.Task<Void, Never>?

    // MARK: - MCP permission
    @Published private(set) var mcpPermissionRequest: McpToolCallPermissionRequest? = nil

    // MARK: - Init

    init(promptSource: VoiceAssistantPromptSource,
         entryParams: VoiceAssistantEntryParams,
         chatHistoryStore: ChatHistoryStore,
         characterRepository: CharacterRepository) {
        self.promptSource = promptSource
        self.entryParams = entryParams
        self.chatHistoryStore = chatHistoryStore
        self.characterRepository = characterRepository

        // Wire TTS delegate so state updates flow back.
        let delegate = SynthDelegate { [weak self] speaking in
            guard let self else { return }
            if !self.streamingTurnActive {
                self.uiState.isSpeaking = speaking
            }
        }
        self.ttsDelegate = delegate
        synthesizer.delegate = delegate

        _Concurrency.Task { await self.loadTopicAndInitTts() }
    }

    private func loadTopicAndInitTts() async {
        let topic = entryParams.topic
        let prompt = await promptSource.getPromptForTopic(topic)
        uiState.topicTitle = prompt.title
        uiState.starters = prompt.starters
        initSystemTts(languageCode: prompt.bcp47Language ?? "ko-KR")
    }

    private func initSystemTts(languageCode: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode))
        // AVSpeechSynthesizer works without explicit initialization; just mark ready.
        uiState.ttsReady = true
        rebuildVoiceOptions()
    }

    // MARK: - Voice options

    private func rebuildVoiceOptions() {
        var options: [VoiceOption] = []
        // Neural (KSS) speakers.
        if let kss = neuralTts {
            let speakers = max(1, kss.numSpeakers)
            if speakers <= 1 {
                options.append(VoiceOption(id: "neural:kss", label: "신경망 음성 (KSS)",
                                           subtitle: "고품질·기기 독립", isNeural: true))
            } else {
                for sid in 0..<speakers {
                    options.append(VoiceOption(id: "neural:kss#\(sid)", label: "KSS 화자 \(sid + 1)",
                                               subtitle: "고품질·기기 독립", isNeural: true))
                }
            }
        }
        // MeloTTS speakers.
        if let melo = meloTts {
            let speakers = max(1, melo.numSpeakers)
            if speakers <= 1 {
                options.append(VoiceOption(id: "neural:melo", label: "MeloTTS (ko)",
                                           subtitle: "자연스러운 한국어", isNeural: true))
            } else {
                for sid in 0..<speakers {
                    options.append(VoiceOption(id: "neural:melo#\(sid)", label: "MeloTTS 화자 \(sid + 1)",
                                               subtitle: "자연스러운 한국어", isNeural: true))
                }
            }
        }
        // System (AVSpeech) Korean voices.
        // NOTE: On iOS, AVSpeechSynthesisVoice.speechVoices() gives the installed voices.
        let koVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ko") }
        for (i, v) in koVoices.enumerated() {
            options.append(VoiceOption(id: "system:\(v.identifier)",
                                       label: "시스템 음성 \(i + 1)",
                                       subtitle: v.name))
        }
        if options.isEmpty {
            // Fallback: generic system voice.
            options.append(VoiceOption(id: "system:default", label: "시스템 음성"))
        }
        let current = uiState.selectedVoiceId
        let stillValid = options.contains { $0.id == current }
        let selected: String
        if stillValid {
            selected = current
        } else if let neural = options.first(where: { $0.isNeural && !$0.isCloud }) {
            selected = neural.id
        } else if let first = options.first {
            selected = first.id
        } else {
            selected = ""
        }
        uiState.voices = options
        uiState.selectedVoiceId = selected
    }

    func selectVoice(id: String) {
        guard id != uiState.selectedVoiceId else { return }
        stopSpeaking()
        uiState.selectedVoiceId = id
    }

    func setSpeakMode(_ mode: TtsSpeakMode) {
        guard mode != uiState.speakMode else { return }
        stopSpeaking()
        uiState.speakMode = mode
    }

    // MARK: - Neural TTS download pipeline (KSS)

    func onKoreanTtsStatus(model: Model?, downloadStatus: ModelDownloadStatus?) {
        guard let model else {
            uiState.neuralVoice = NeuralVoiceState(stage: .notInstalled)
            return
        }
        if neuralTts != nil { return }
        updateNeuralStageFromDownload(status: downloadStatus,
                                      stateKeyPath: \.neuralVoice,
                                      prepare: { [weak self] in self?.prepareNeuralEngine(model) })
    }

    func onMeloTtsStatus(model: Model?, downloadStatus: ModelDownloadStatus?) {
        guard let model else {
            uiState.meloVoice = NeuralVoiceState(stage: .notInstalled)
            return
        }
        if meloTts != nil { return }
        updateNeuralStageFromDownload(status: downloadStatus,
                                      stateKeyPath: \.meloVoice,
                                      prepare: { [weak self] in self?.prepareMeloEngine(model) })
    }

    private func updateNeuralStageFromDownload(status: ModelDownloadStatus?,
                                               stateKeyPath: WritableKeyPath<VoiceAssistantUiState, NeuralVoiceState>,
                                               prepare: @escaping () -> Void) {
        guard let status else {
            uiState[keyPath: stateKeyPath] = NeuralVoiceState(stage: .notInstalled)
            return
        }
        switch status.status {
        case .inProgress, .partiallyDownloaded, .unzipping:
            let total = status.totalBytes
            let recv = status.receivedBytes
            let pct = total > 0 ? Int(recv * 100 / total) : -1
            uiState[keyPath: stateKeyPath] = NeuralVoiceState(stage: .downloading,
                downloadPercent: pct, downloadedBytes: recv, totalBytes: total,
                bytesPerSecond: status.bytesPerSecond, remainingMs: status.remainingMs)
        case .succeeded:
            prepare()
        case .failed:
            uiState[keyPath: stateKeyPath] = NeuralVoiceState(stage: .error,
                error: status.errorMessage.isEmpty ? "다운로드에 실패했습니다." : status.errorMessage)
        default:
            let stage = uiState[keyPath: stateKeyPath].stage
            if stage != .preparing {
                uiState[keyPath: stateKeyPath] = NeuralVoiceState(stage: .notInstalled)
            }
        }
    }

    private var preparingNeural = false
    private func prepareNeuralEngine(_ model: Model) {
        guard !preparingNeural, neuralTts == nil else { return }
        preparingNeural = true
        uiState.neuralVoice = NeuralVoiceState(stage: .preparing)
        // NOTE: KoreanNeuralTts.load is synchronous in the iOS stub; run it on a background thread
        // so it doesn't block the main actor. When a real async engine is available, use await.
        _Concurrency.Task.detached { [weak self] in
            let result = KoreanNeuralTts.load(model: model) { pct in
                _Concurrency.Task { @MainActor [weak self] in
                    self?.uiState.neuralVoice = NeuralVoiceState(stage: .preparing, unpackPercent: pct)
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let engine):
                    self.neuralTts = engine
                    self.uiState.neuralVoice = NeuralVoiceState(stage: .ready)
                    self.rebuildVoiceOptions()
                case .notDownloaded:
                    self.uiState.neuralVoice = NeuralVoiceState(stage: .notInstalled)
                case .failure(let msg, _):
                    self.uiState.neuralVoice = NeuralVoiceState(stage: .error, error: msg)
                }
                self.preparingNeural = false
            }
        }
    }

    func retryNeuralPreparation() {
        // NOTE: KoreanNeuralTts.clearExtracted is the bridge point for clearing stale files.
        preparingNeural = false
        if let m = pendingModel { prepareNeuralEngine(m) }
    }

    private var preparingMelo = false
    private func prepareMeloEngine(_ model: Model) {
        guard !preparingMelo, meloTts == nil else { return }
        preparingMelo = true
        uiState.meloVoice = NeuralVoiceState(stage: .preparing)
        // NOTE: MeloNeuralTts.load is synchronous in the iOS stub; run off the main actor.
        _Concurrency.Task.detached { [weak self] in
            let result = MeloNeuralTts.load(model: model) { pct in
                _Concurrency.Task { @MainActor [weak self] in
                    self?.uiState.meloVoice = NeuralVoiceState(stage: .preparing, unpackPercent: pct)
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let engine):
                    self.meloTts = engine
                    self.uiState.meloVoice = NeuralVoiceState(stage: .ready)
                    self.rebuildVoiceOptions()
                case .notDownloaded:
                    self.uiState.meloVoice = NeuralVoiceState(stage: .notInstalled)
                case .failure(let msg, _):
                    self.uiState.meloVoice = NeuralVoiceState(stage: .error, error: msg)
                }
                self.preparingMelo = false
            }
        }
    }

    func retryMeloPreparation() {
        preparingMelo = false
        if let m = pendingModel { prepareMeloEngine(m) }
    }

    // MARK: - Neural STT download pipeline

    func onNeuralSttStatus(model: Model?, downloadStatus: ModelDownloadStatus?) {
        updateSttAvailability(.neural, model: model, downloadStatus: downloadStatus)
    }

    func onWhisperSttStatus(model: Model?, downloadStatus: ModelDownloadStatus?) {
        updateSttAvailability(.whisper, model: model, downloadStatus: downloadStatus)
    }

    private func updateSttAvailability(_ engine: SttEngine, model: Model?,
                                       downloadStatus: ModelDownloadStatus?) {
        guard let model else {
            setSttEngineState(engine, state: NeuralSttState(stage: .notInstalled))
            return
        }
        switch downloadStatus?.status {
        case .inProgress, .partiallyDownloaded, .unzipping:
            let total = downloadStatus!.totalBytes
            let recv = downloadStatus!.receivedBytes
            let pct = total > 0 ? Int(recv * 100 / total) : -1
            setSttEngineState(engine, state: NeuralSttState(stage: .downloading,
                downloadPercent: pct,
                bytesPerSecond: downloadStatus!.bytesPerSecond,
                remainingMs: downloadStatus!.remainingMs))
        case .succeeded:
            setSttEngineState(engine, state: NeuralSttState(stage: .ready))
            if uiState.sttEngine == engine { ensureActiveRecognizer(engine, model: model) }
        case .failed:
            let msg = downloadStatus!.errorMessage.isEmpty ? "다운로드에 실패했습니다." : downloadStatus!.errorMessage
            setSttEngineState(engine, state: NeuralSttState(stage: .error, error: msg))
        default:
            let cur = sttEngineState(engine)
            if cur.stage != .ready {
                setSttEngineState(engine, state: NeuralSttState(stage: .notInstalled))
            }
        }
    }

    private func ensureActiveRecognizer(_ engine: SttEngine, model: Model) {
        // NOTE: Neural on-device STT (sherpa-onnx SenseVoice / Whisper) is not yet available
        // as an iOS library. When ported, implement NeuralSttEngine and load it here.
        // For now, all "neural" selections gracefully fall back to SFSpeechRecognizer.
        setSttEngineState(engine, state: NeuralSttState(stage: .ready))
    }

    func selectSttEngine(_ engine: SttEngine) {
        guard engine != uiState.sttEngine else { return }
        if uiState.isListening { stopListening() }
        uiState.sttEngine = engine
    }

    func retryNeuralSttPreparation() { /* no-op until native engine is available */ }
    func retryWhisperSttPreparation() { /* no-op until native engine is available */ }

    private func setSttEngineState(_ engine: SttEngine, state: NeuralSttState) {
        switch engine {
        case .whisper: uiState.whisperStt = state
        default:       uiState.neuralStt  = state
        }
    }

    private func sttEngineState(_ engine: SttEngine) -> NeuralSttState {
        engine == .whisper ? uiState.whisperStt : uiState.neuralStt
    }

    // MARK: - Speech recognition (STT)

    func startListening() {
        guard !uiState.isListening else { return }
        stopSpeaking()
        uiState.isListening = true
        uiState.partialTranscript = ""
        uiState.error = ""

        // NOTE: iOS uses SFSpeechRecognizer for on-device speech recognition.
        // Neural engines (SenseVoice / Whisper) are stubs — both map to this path.
        startSystemListening()
    }

    private func startSystemListening() {
        guard let rec = recognizer ?? SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")) else {
            uiState.isListening = false
            uiState.error = "이 기기에서는 음성 인식을 사용할 수 없습니다."
            consecutiveSilentTurns += 1
            return
        }
        recognizer = rec

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let node = audioEngine.inputNode
        let fmt = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            self?.recognitionRequest?.append(buf)
        }
        do { try audioEngine.start() } catch {
            cleanup()
            uiState.isListening = false
            uiState.error = "녹음을 시작할 수 없습니다."
            consecutiveSilentTurns += 1
            return
        }

        recognitionTask = rec.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let transcript = result.bestTranscription.formattedString
                if result.isFinal {
                    _Concurrency.Task { @MainActor in
                        self.cleanup()
                        self.uiState.isListening = false
                        self.uiState.partialTranscript = ""
                        if !transcript.isEmpty {
                            self.consecutiveSilentTurns = 0
                            self.submitUserInput(transcript)
                        } else {
                            self.consecutiveSilentTurns += 1
                        }
                    }
                } else {
                    _Concurrency.Task { @MainActor in self.uiState.partialTranscript = transcript }
                }
            }
            if let error {
                _Concurrency.Task { @MainActor in
                    let wasListening = self.uiState.isListening
                    self.cleanup()
                    self.uiState.isListening = false
                    if wasListening { self.consecutiveSilentTurns += 1 }
                    let msg = error.localizedDescription
                    // Suppress low-level "no match" / abort errors which are common and unactionable.
                    let code = (error as NSError).code
                    if code != 203 && code != 216 { // 203 = no speech, 216 = cancelled
                        self.uiState.error = msg
                    }
                }
            }
        }
    }

    func stopListening() {
        guard uiState.isListening else { return }
        cleanup()
        uiState.isListening = false
    }

    private func cleanup() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
    }

    // MARK: - Call mode (hands-free)

    func setInputMode(_ mode: ChatInputMode) {
        guard mode != uiState.inputMode else { return }
        uiState.inputMode = mode
        if mode == .call { startCallLoop() } else { stopCallLoop() }
    }

    func toggleInputMode() {
        setInputMode(uiState.inputMode == .call ? .standard : .call)
    }

    private func startCallLoop() {
        consecutiveSilentTurns = 0
        callLoopTask?.cancel()
        callLoopTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            // Open mic immediately on entering call mode.
            self.startListening()
            while !_Concurrency.Task.isCancelled {
                // Observe state changes; wait for the assistant to be fully idle.
                try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 100 ms poll
                let s = await self.uiState
                let idle = s.inputMode == .call && !s.isListening && !s.isThinking && !s.isSpeaking
                if idle {
                    // Back off longer after silent turns.
                    let cooldown = self.consecutiveSilentTurns > 0
                        ? CALL_SILENT_COOLDOWN_NS * UInt64(min(self.consecutiveSilentTurns, CALL_SILENT_BACKOFF_CAP))
                        : CALL_RELISTEN_DEBOUNCE_MS
                    try? await _Concurrency.Task.sleep(nanoseconds: cooldown)
                    let now = await self.uiState
                    if now.inputMode == .call && !now.isListening && !now.isThinking && !now.isSpeaking {
                        await self.startListening()
                    }
                }
            }
        }
    }

    private func stopCallLoop() {
        callLoopTask?.cancel()
        callLoopTask = nil
        stopListening()
        stopSpeaking()
    }

    // MARK: - Conversation management

    func setConversation(_ conversationId: String) {
        guard conversationId != activeConversationId else { return }
        stopListening()
        stopSpeaking()
        if !activeConversationId.isEmpty {
            let finalized = uiState.messages.map {
                $0.isStreaming ? VoiceMessage(role: $0.role, text: $0.text, isStreaming: false) : $0
            }
            messagesByConversation[activeConversationId] = finalized
            persist(activeConversationId, messages: finalized)
        }
        activeConversationId = conversationId
        if let cached = messagesByConversation[conversationId] {
            uiState.messages = cached
            uiState.isThinking = false
            uiState.partialTranscript = ""
            uiState.error = ""
        } else {
            uiState.messages = []
            uiState.isThinking = false
            uiState.partialTranscript = ""
            uiState.error = ""
            _Concurrency.Task {
                let loaded = await _Concurrency.Task.detached {
                    self.chatHistoryStore.load(conversationId)
                }.value
                if self.activeConversationId == conversationId, !loaded.isEmpty {
                    self.messagesByConversation[conversationId] = loaded
                    self.uiState.messages = loaded
                }
            }
        }
    }

    private func syncActiveMessages() {
        guard !activeConversationId.isEmpty else { return }
        messagesByConversation[activeConversationId] = uiState.messages
    }

    func deleteMessagesBefore(index: Int) {
        let current = uiState.messages
        guard index > 0, index < current.count else { return }
        let trimmed = Array(current[index...])
        uiState.messages = trimmed
        syncActiveMessages()
        persistActive()
    }

    func regenerate(assistantIndex: Int) {
        guard !uiState.isThinking, let model = pendingModel else { return }
        let messages = uiState.messages
        guard assistantIndex < messages.count,
              messages[assistantIndex].role == .assistant else { return }
        let userIndex = (0..<assistantIndex).reversed().first { messages[$0].role == .user }
        guard let userIndex else { return }
        let userText = messages[userIndex].text
        guard !userText.isEmpty else { return }
        stopSpeaking()
        let kept = Array(messages[0...userIndex])
        uiState.messages = kept + [VoiceMessage(role: .assistant, text: "", isStreaming: true)]
        uiState.isThinking = true
        uiState.error = ""
        syncActiveMessages()
        runLlm(model, input: userText)
    }

    func greet(_ model: Model) {
        guard !uiState.isThinking, uiState.messages.isEmpty else { return }
        uiState.messages = [VoiceMessage(role: .assistant, text: "", isStreaming: true)]
        uiState.isThinking = true
        uiState.error = ""
        syncActiveMessages()
        runLlm(model, input: GREETING_PROMPT)
    }

    func continueTalking(_ model: Model) {
        guard !uiState.isThinking else { return }
        stopSpeaking()
        uiState.messages.append(VoiceMessage(role: .assistant, text: "", isStreaming: true))
        uiState.isThinking = true
        uiState.error = ""
        syncActiveMessages()
        runLlm(model, input: CONTINUE_PROMPT)
    }

    func clearConversation() {
        stopListening()
        stopSpeaking()
        uiState.messages = []
        uiState.isThinking = false
        uiState.partialTranscript = ""
        uiState.error = ""
        syncActiveMessages()
        persistActive()
    }

    func sendStarter(_ text: String, model: Model) {
        submitUserInput(text, model: model)
    }

    func setActiveModel(_ model: Model) {
        pendingModel = model
    }

    // MARK: - Tool / MCP

    /// Called by the wiring to attach skill + MCP counts and set up the action channel.
    /// NOTE: Full AgentTools integration requires the AgentChat module (not yet ported).
    /// The `setMcpToolCount` / `setSkillCount` paths below are wired by VoiceChatPlumbing.
    func setMcpToolCount(_ count: Int) {
        guard count != uiState.mcpToolCount else { return }
        uiState.mcpToolCount = count
    }

    func setSkillCount(_ count: Int) {
        guard count != uiState.skillCount else { return }
        uiState.skillCount = count
    }

    func resolveMcpPermission(_ result: VAPermissionResult) {
        mcpPermissionRequest?.completion(result)
        mcpPermissionRequest = nil
    }

    func clearError() { uiState.error = "" }

    // MARK: - LLM inference

    private func submitUserInput(_ text: String, model: Model? = nil) {
        let activeModel = model ?? pendingModel
        guard let activeModel else {
            uiState.error = "모델이 아직 준비되지 않았습니다."
            return
        }
        uiState.messages.append(VoiceMessage(role: .user, text: text))
        uiState.messages.append(VoiceMessage(role: .assistant, text: "", isStreaming: true))
        uiState.isThinking = true
        uiState.error = ""
        syncActiveMessages()
        runLlm(activeModel, input: text)
    }

    private func runLlm(_ model: Model, input: String) {
        let builder = NSMutableString()
        let convId = activeConversationId
        generationSeq += 1
        let genId = generationSeq
        let streaming = uiState.speakMode == .streaming
        if streaming { beginStreamingSpeech() }

        // Stall watchdog.
        let lastOutputAt = AtomicTimestamp()
        watchdogTask?.cancel()
        watchdogTask = _Concurrency.Task { [weak self] in
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                let idleNs = lastOutputAt.elapsed()
                if idleNs >= GENERATION_STALL_TIMEOUT_NS {
                    guard self.generationSeq == genId else { return }
                    self.generationSeq += 1
                    if streaming { self.cancelStreamingSpeech() }
                    var messages = self.uiState.messages
                    if let last = messages.indices.last(where: { messages[$0].role == .assistant }) {
                        messages[last] = VoiceMessage(role: .assistant, text: messages[last].text, isStreaming: false)
                    }
                    self.uiState.messages = messages
                    self.uiState.isThinking = false
                    self.uiState.error = "응답이 너무 지연돼 멈췄어요. 다시 시도해 주세요."
                    return
                }
            }
        }

        model.runtimeHelper?.runInference(
            model: model,
            input: input,
            resultListener: { [weak self] partial, done, _ in
                guard let self else { return }
                _Concurrency.Task { @MainActor in
                    guard self.activeConversationId == convId,
                          self.generationSeq == genId else { return }
                    lastOutputAt.update()
                    if !partial.hasPrefix("<ctrl") {
                        builder.append(partial)
                        let full = builder as String
                        self.updateStreamingAssistant(full, streaming: !done)
                        if streaming {
                            self.enqueueReadySentences(speakableStreamingView(full))
                        }
                    }
                    if done {
                        self.finishGeneration()
                        let full = (builder as String).trimmingCharacters(in: .whitespacesAndNewlines)
                        self.uiState.isThinking = false
                        if streaming {
                            self.finishStreamingSpeech(speakableStreamingView(builder as String))
                        } else if !full.isEmpty {
                            self.speak(full)
                        }
                        let emojis = extractEmojis(builder as String)
                        if !emojis.isEmpty {
                            self.emotionCues.send(EmotionCue(emojis: Array(Set(emojis)), id: self.emotionCueSeq))
                            self.emotionCueSeq += 1
                        }
                        self.persistActive()
                    }
                }
            },
            cleanUpListener: {},
            onError: { [weak self] message in
                guard let self else { return }
                _Concurrency.Task { @MainActor in
                    if streaming { self.cancelStreamingSpeech() }
                    guard self.activeConversationId == convId,
                          self.generationSeq == genId else { return }
                    self.finishGeneration()
                    self.uiState.isThinking = false
                    self.uiState.error = message.isEmpty ? "문제가 발생했습니다." : message
                    self.updateStreamingAssistant(builder as String, streaming: false)
                }
            }
        )
    }

    private func finishGeneration() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    private func updateStreamingAssistant(_ content: String, streaming: Bool) {
        guard let last = uiState.messages.indices.last(where: { uiState.messages[$0].role == .assistant }) else { return }
        uiState.messages[last] = VoiceMessage(role: .assistant, text: content, isStreaming: streaming)
        syncActiveMessages()
    }

    // MARK: - TTS (speak)

    private func resolveNeuralVoice(_ selectedId: String) -> (NeuralTtsEngine?, Int) {
        let base = selectedId.components(separatedBy: "#").first ?? selectedId
        let sid = Int(selectedId.components(separatedBy: "#").last ?? "") ?? 0
        if let melo = meloTts, base == "neural:melo" { return (melo, sid) }
        if let kss = neuralTts, base == "neural:kss" || selectedId.isEmpty { return (kss, sid) }
        return (nil, 0)
    }

    private func speak(_ text: String) {
        let spoken = sanitizeForSpeech(text)
        guard !spoken.isEmpty else { return }
        let selectedId = uiState.selectedVoiceId
        let (engine, sid) = resolveNeuralVoice(selectedId)
        if let engine {
            speakNeural(engine, text: spoken, sid: sid)
        } else {
            speakSystem(spoken)
        }
    }

    private func speakSystem(_ text: String) {
        let langCode = uiState.starters.isEmpty ? "ko-KR" : "ko-KR" // always Korean
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: langCode)
        utterance.rate = 0.52
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    private func speakNeural(_ engine: NeuralTtsEngine, text: String, sid: Int) {
        _Concurrency.Task.detached { [weak self] in
            let safeSid = max(0, min(sid, engine.numSpeakers - 1))
            guard let result = engine.generate(text: text, sid: safeSid, speed: 1.0) else { return }
            await MainActor.run { self?.uiState.isSpeaking = true }
            await self?.audioPlayer.playToCompletion(samples: result.samples, sampleRate: result.sampleRate)
            await MainActor.run { self?.uiState.isSpeaking = false }
        }
    }

    // MARK: - Streaming TTS (sentence-by-sentence)

    private func beginStreamingSpeech() {
        cancelStreamingSpeech()
        spokenChars = 0
        streamingTurnActive = true
        var continuation: AsyncStream<String>.Continuation!
        let stream = AsyncStream<String> { continuation = $0 }
        speakChannel = continuation
        speakConsumerTask = _Concurrency.Task { [weak self] in
            var first = true
            for await segment in stream {
                guard let self else { break }
                if first { self.uiState.isSpeaking = true }
                await self.speakSegmentToCompletion(segment, flush: first)
                first = false
            }
            self?.streamingTurnActive = false
            self?.uiState.isSpeaking = false
        }
    }

    private func enqueueReadySentences(_ full: String) {
        guard let ch = speakChannel else { return }
        for seg in extractReadySegments(full) { ch.yield(seg) }
    }

    private func finishStreamingSpeech(_ full: String) {
        guard let ch = speakChannel else { return }
        let tail = spokenChars < full.count
            ? String(full.dropFirst(spokenChars)).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        if !tail.isEmpty { ch.yield(tail) }
        spokenChars = full.count
        ch.finish()
    }

    private func cancelStreamingSpeech() {
        speakChannel?.finish()
        speakChannel = nil
        speakConsumerTask?.cancel()
        speakConsumerTask = nil
        streamingTurnActive = false
    }

    private func extractReadySegments(_ full: String) -> [String] {
        guard spokenChars < full.count else { return [] }
        let pending = String(full.dropFirst(spokenChars))
        var cut = pending.lastIndex(where: { SENTENCE_TERMINATORS.contains($0) }).map {
            pending.distance(from: pending.startIndex, to: $0)
        } ?? -1
        if cut < 0, pending.count >= STREAMING_SOFT_FLUSH_CHARS {
            cut = pending.lastIndex(of: " ").map {
                pending.distance(from: pending.startIndex, to: $0)
            } ?? -1
        }
        guard cut >= 0 else { return [] }
        spokenChars += cut + 1
        let ready = String(pending.prefix(cut + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return ready.isEmpty ? [] : [ready]
    }

    private func speakSegmentToCompletion(_ text: String, flush: Bool) async {
        let spoken = sanitizeForSpeech(text)
        guard !spoken.isEmpty else { return }
        let selectedId = uiState.selectedVoiceId
        let (engine, sid) = resolveNeuralVoice(selectedId)
        if let engine {
            let safeSid = max(0, min(sid, engine.numSpeakers - 1))
            guard let result = engine.generate(text: spoken, sid: safeSid, speed: 1.0) else { return }
            await audioPlayer.playToCompletion(samples: result.samples, sampleRate: result.sampleRate)
        } else {
            // System TTS: speak and wait via a continuation.
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let utterance = AVSpeechUtterance(string: spoken)
                utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
                utterance.rate = 0.52
                self.ttsDelegate?.onDone = { cont.resume() }
                if flush { self.synthesizer.stopSpeaking(at: .immediate) }
                self.synthesizer.speak(utterance)
            }
            ttsDelegate?.onDone = nil
        }
    }

    func stopSpeaking() {
        cancelStreamingSpeech()
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer.stop()
        uiState.isSpeaking = false
    }

    func stopAll() {
        stopListening()
        stopSpeaking()
    }

    // MARK: - Persistence

    private func persist(_ conversationId: String, messages: [VoiceMessage]) {
        _Concurrency.Task.detached { [weak self] in
            self?.chatHistoryStore.save(conversationId, messages: messages)
        }
    }

    private func persistActive() {
        guard !activeConversationId.isEmpty else { return }
        persist(activeConversationId, messages: uiState.messages)
    }

    // MARK: - Cleanup (called when the owning view disappears or is replaced)

    func onDisappear() {
        if !activeConversationId.isEmpty {
            chatHistoryStore.save(activeConversationId, messages: uiState.messages)
        }
        stopAll()
        callLoopTask?.cancel()
        cleanup()
    }
}

// MARK: - AVSpeechSynthesizerDelegate bridge

private final class SynthDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onSpeakingChanged: (Bool) -> Void
    var onDone: (() -> Void)?

    init(onSpeakingChanged: @escaping (Bool) -> Void) {
        self.onSpeakingChanged = onSpeakingChanged
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onSpeakingChanged(true)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onSpeakingChanged(false)
        onDone?()
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onSpeakingChanged(false)
        onDone?()
    }
}

// MARK: - Model runtimeHelper extension
// NOTE: Model does not have a `runtimeHelper` property in the iOS foundation.
// The shared LlmModelHelper (StubLlmModelHelper or a real backend) is held on AppContainer.
// This shim keeps call-site parity with the Android port where `model.runtimeHelper` was used.
// Replace `StubLlmModelHelper()` with `AppContainer.sharedLlmHelper` when wiring AppContainer.
private extension Model {
    var runtimeHelper: LlmModelHelper? { StubLlmModelHelper() }
}

// MARK: - AtomicTimestamp helper

private final class AtomicTimestamp {
    private let lock = NSLock()
    private var ts: UInt64 = 0

    init() { update() }

    func update() {
        lock.lock(); defer { lock.unlock() }
        ts = DispatchTime.now().uptimeNanoseconds
    }

    func elapsed() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return DispatchTime.now().uptimeNanoseconds - ts
    }
}
