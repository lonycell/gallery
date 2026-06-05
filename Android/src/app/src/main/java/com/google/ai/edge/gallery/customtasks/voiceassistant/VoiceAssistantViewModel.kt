/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.google.ai.edge.gallery.customtasks.voiceassistant

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.ai.edge.gallery.common.AgentAction
import com.google.ai.edge.gallery.common.AskInfoAgentAction
import com.google.ai.edge.gallery.common.AskMcpToolCallPermissionAction
import com.google.ai.edge.gallery.common.CallJsAgentAction
import com.google.ai.edge.gallery.common.PermissionResult
import com.google.ai.edge.gallery.common.RequestPermissionAgentAction
import com.google.ai.edge.gallery.common.SkillProgressAgentAction
import com.google.ai.edge.gallery.customtasks.agentchat.AgentTools
import com.google.ai.edge.gallery.customtasks.speech.AudioPlayer
import com.google.ai.edge.gallery.customtasks.speech.AudioRecorder
import com.google.ai.edge.gallery.customtasks.speech.KoreanNeuralStt
import com.google.ai.edge.gallery.customtasks.speech.KoreanNeuralTts
import com.google.ai.edge.gallery.customtasks.speech.KoreanTtsLoadResult
import com.google.ai.edge.gallery.customtasks.speech.MeloNeuralTts
import com.google.ai.edge.gallery.customtasks.speech.MeloTtsLoadResult
import com.google.ai.edge.gallery.customtasks.speech.NeuralSttLoadResult
import com.google.ai.edge.gallery.customtasks.speech.WhisperNeuralStt
import com.google.ai.edge.gallery.customtasks.speech.SPEECH_SAMPLE_RATE
import com.google.ai.edge.gallery.data.ModelDownloadStatus
import com.google.ai.edge.gallery.data.ModelDownloadStatusType
import com.google.ai.edge.gallery.customtasks.voiceassistant.prompts.TopicPrompt
import com.google.ai.edge.gallery.customtasks.voiceassistant.prompts.VoiceAssistantPromptSource
import com.google.ai.edge.gallery.data.Model
import com.google.ai.edge.gallery.runtime.runtimeHelper
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineTts
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.Locale
import javax.inject.Inject
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val TAG = "AGVoiceAssistant"
private const val ASSISTANT_UTTERANCE_ID = "va_assistant_utterance"

// In call mode, how long the assistant must be fully idle (not listening/thinking/speaking) before
// the mic re-opens — long enough to absorb the brief think→speak gap, short enough to feel live.
private const val CALL_RELISTEN_DEBOUNCE_MS = 450L

// "생각 중" only clears when generation produces a token, finishes (onDone), or errors. If the runtime
// goes silent — a hung tool call or a wedged engine — it would otherwise hang forever. If no output
// arrives for this long, treat it as a stall and recover the UI so the user can retry.
private const val GENERATION_STALL_TIMEOUT_MS = 45_000L

// In call mode, after a turn that captured nothing (silence / no-match), wait this much longer before
// re-opening the mic. This gives the recognizer time to fully reset (avoiding ERROR_RECOGNIZER_BUSY)
// and keeps the loop from flickering open/closed while the user is simply quiet.
private const val CALL_SILENT_COOLDOWN_MS = 1100L
// Cap on how many consecutive silent turns lengthen the cooldown, so it never stalls indefinitely.
private const val CALL_SILENT_BACKOFF_CAP = 3

// Hidden prompt that makes the character open the conversation with a short, in-persona greeting.
private const val GREETING_PROMPT =
  "(사용자가 방금 너와 대화를 시작했어. 너의 성격과 말투를 살려서, 짧고 자연스럽게 먼저 인사하며 " +
    "말을 걸어줘. 한두 문장으로만 해줘.)"

// Hidden prompt sent when the user double-taps the background to let the character keep talking on
// its own. No user message is shown; the character simply continues the conversation naturally.
private const val CONTINUE_PROMPT =
  "(사용자는 말없이 너의 이야기를 더 듣고 싶어 해. 지금까지의 흐름을 이어서, 너의 성격과 말투를 살려 " +
    "자연스럽게 한두 문장 더 이야기를 건네줘. 대화가 처음이라면 가볍게 먼저 말을 걸어줘.)"

// Characters that end a sentence (Korean + Latin + CJK), used by streaming TTS to decide when a
// chunk of the reply is complete enough to start speaking. Newlines also flush.
private val SENTENCE_TERMINATORS = charArrayOf('.', '!', '?', '…', '。', '！', '？', '\n')
// If a run of text has no terminator for this many characters, flush it anyway so streaming speech
// doesn't stall on a long terminator-less passage.
private const val STREAMING_SOFT_FLUSH_CHARS = 60

/** A single message in the voice conversation. */
data class ChatMessage(val role: Role, val text: String, val isStreaming: Boolean = false) {
  enum class Role {
    USER,
    ASSISTANT,
  }
}

/** A selectable voice for spoken replies (either the neural voice or a system TTS voice). */
data class VoiceOption(
  /** Stable id, e.g. "neural:kss" or "system:<voiceName>". */
  val id: String,
  val label: String,
  val subtitle: String = "",
  val isNeural: Boolean = false,
  /** A cloud (commercial API) voice rather than an on-device one. */
  val isCloud: Boolean = false,
)

/**
 * The lifecycle of preparing the downloadable Korean neural voice, so the UI can show appropriate
 * feedback (download progress, an unzip/initialize spinner, errors with recovery, etc).
 */
enum class NeuralVoiceStage {
  /** Not downloaded yet and not currently being prepared. */
  NOT_INSTALLED,
  /** The model archive is downloading. */
  DOWNLOADING,
  /** The archive is downloaded; being unpacked (.tar.bz2) and the engine initialized. */
  PREPARING,
  /** Ready to speak. */
  READY,
  /** Something failed (download, unpack, or init). [NeuralVoiceState.error] has details. */
  ERROR,
}

/** Detailed state of the Korean neural voice preparation pipeline. */
data class NeuralVoiceState(
  val stage: NeuralVoiceStage = NeuralVoiceStage.NOT_INSTALLED,
  /** 0..100 while downloading, or -1 if unknown. */
  val downloadPercent: Int = -1,
  val downloadedBytes: Long = 0L,
  val totalBytes: Long = 0L,
  val bytesPerSecond: Long = 0L,
  val remainingMs: Long = 0L,
  /** 0..100 while unpacking during PREPARING, or -1 before unpack progress is known. */
  val unpackPercent: Int = -1,
  val error: String = "",
)

/** Which engine recognizes the user's speech (input). */
enum class SttEngine {
  /** The device's built-in [android.speech.SpeechRecognizer] (default; no download, low latency). */
  SYSTEM,
  /** The downloadable on-device neural recognizer (sherpa-onnx SenseVoice). */
  NEURAL,
  /**
   * The downloadable on-device Whisper recognizer (sherpa-onnx, multilingual `small`). Strong
   * Korean accuracy, but a larger model and slower (autoregressive) decoding than SenseVoice.
   */
  WHISPER,
}

/** When the assistant's spoken reply is produced relative to the LLM's text generation. */
enum class TtsSpeakMode {
  /** Speak only after the full reply has been generated (default; most natural prosody). */
  AFTER_COMPLETE,
  /** Speak sentence-by-sentence as the reply streams in, for much lower time-to-first-audio. */
  STREAMING,
}

/** How the user provides input in the chat. */
enum class ChatInputMode {
  /** Text field + one-shot mic (tap to listen once). */
  STANDARD,
  /** Hands-free "phone call": the mic re-opens automatically after each assistant turn. */
  CALL,
}

/** Detailed state of the downloadable neural speech recognizer (mirrors [NeuralVoiceState]). */
data class NeuralSttState(
  val stage: NeuralVoiceStage = NeuralVoiceStage.NOT_INSTALLED,
  val downloadPercent: Int = -1,
  val bytesPerSecond: Long = 0L,
  val remainingMs: Long = 0L,
  val error: String = "",
)

/** UI state for the Voice Assistant screen. */
data class VoiceAssistantUiState(
  val messages: List<ChatMessage> = listOf(),
  val isListening: Boolean = false,
  val isSpeaking: Boolean = false,
  val isThinking: Boolean = false,
  val partialTranscript: String = "",
  val error: String = "",
  val topicTitle: String = "",
  val starters: List<String> = listOf(),
  val ttsReady: Boolean = false,
  /** Available voices the user can pick from (neural + system Korean voices). */
  val voices: List<VoiceOption> = listOf(),
  /** The currently selected voice id. */
  val selectedVoiceId: String = "",
  /** Whether the reply is spoken after completion (default) or streamed sentence-by-sentence. */
  val speakMode: TtsSpeakMode = TtsSpeakMode.AFTER_COMPLETE,
  /** State of the downloadable Korean neural voice (KSS) (download → unpack/init → ready/error). */
  val neuralVoice: NeuralVoiceState = NeuralVoiceState(),
  /** State of the downloadable MeloTTS Korean voice (same pipeline as [neuralVoice]). */
  val meloVoice: NeuralVoiceState = NeuralVoiceState(),
  /** Which engine is used to recognize the user's speech. */
  val sttEngine: SttEngine = SttEngine.SYSTEM,
  /** Availability of the downloadable SenseVoice recognizer (download → ready/error). */
  val neuralStt: NeuralSttState = NeuralSttState(),
  /** Availability of the downloadable Whisper recognizer (same lifecycle as [neuralStt]). */
  val whisperStt: NeuralSttState = NeuralSttState(),
  /** Number of connected/enabled MCP tools currently available to the assistant. */
  val mcpToolCount: Int = 0,
  /** Number of selected skills currently available to the assistant. */
  val skillCount: Int = 0,
  /** A short status line shown while the assistant is invoking a tool/skill (empty when idle). */
  val toolActivity: String = "",
  /** Whether input is the standard text+one-shot-mic, or hands-free phone-call mode. */
  val inputMode: ChatInputMode = ChatInputMode.STANDARD,
)

@HiltViewModel
class VoiceAssistantViewModel
@Inject
constructor(
  @ApplicationContext private val context: Context,
  private val promptSource: VoiceAssistantPromptSource,
  private val entryParams: VoiceAssistantEntryParams,
  private val chatHistoryStore: ChatHistoryStore,
  private val cloudTtsService: com.google.ai.edge.gallery.customtasks.speech.CloudTtsService,
) : ViewModel(), RecognitionListener {

  private val _uiState = MutableStateFlow(VoiceAssistantUiState())
  val uiState = _uiState.asStateFlow()

  // Chat history kept separately per conversation (one per character). The screen calls
  // [setConversation] when the active character changes; the live [uiState].messages mirrors the
  // active conversation, and every message mutation is written back to this map.
  private val messagesByConversation = mutableMapOf<String, List<ChatMessage>>()
  private var activeConversationId: String = ""

  // One-shot emotion cues (emoji in a reply) for the screen to animate instead of speaking them.
  private val _emotionCues = MutableSharedFlow<EmotionCue>(extraBufferCapacity = 8)
  val emotionCues = _emotionCues.asSharedFlow()
  private var emotionCueSeq = 0L

  private var topicPrompt: TopicPrompt? = null
  // The Voice Assistant defaults to Korean for both speech recognition and synthesis. A topic can
  // override this via its bcp47Language.
  private var speechLocale: Locale = Locale.KOREAN

  // Created lazily on first use rather than eagerly at construction. createSpeechRecognizer() binds
  // to the system RecognitionService, which captures the app's RECORD_AUDIO grant state at bind
  // time. Binding here (when the screen opens, before the user has granted the mic) leaves the
  // binding unprivileged, so recording later fails with ERROR_AUDIO even after the grant. Building it
  // on the first startListening() — which the screen only calls once permission is held — avoids that
  // stale-binding failure.
  private var speechRecognizer: SpeechRecognizer? = null

  // Consecutive call-mode listening turns that captured nothing (silence / no-match / busy). Used to
  // stretch the re-listen cooldown so the half-duplex loop never spins open/closed while the user is
  // quiet. Reset to 0 whenever a turn yields real speech.
  private var consecutiveSilentTurns = 0

  /** Lazily creates the system recognizer (must run on the main thread). Null if unavailable. */
  private fun ensureSpeechRecognizer(): SpeechRecognizer? {
    speechRecognizer?.let {
      return it
    }
    if (!SpeechRecognizer.isRecognitionAvailable(context)) {
      return null
    }
    return SpeechRecognizer.createSpeechRecognizer(context)
      .apply { setRecognitionListener(this@VoiceAssistantViewModel) }
      .also { speechRecognizer = it }
  }

  private var tts: TextToSpeech? = null

  // Optional higher-quality Korean neural voices (sherpa-onnx). When loaded, each is offered as one
  // of the selectable voices and played back through [AudioPlayer]. [neuralTts] is the KSS voice;
  // [meloTts] is the MeloTTS voice. Both are independent downloads.
  private var neuralTts: OfflineTts? = null
  private var meloTts: OfflineTts? = null
  private val audioPlayer = AudioPlayer()

  // --- Streaming TTS (sentence-by-sentence) state ---
  // A single consumer coroutine drains [speakChannel], speaking each completed sentence to the end
  // before starting the next. [spokenChars] tracks how much of the streaming reply has already been
  // turned into sentences. [streamingTurnActive] tells the system-TTS progress listener to leave
  // [isSpeaking] alone while the consumer owns it. Pending system-TTS utterances are awaited via
  // [utteranceCompletions] so the consumer stays in lock-step with playback.
  private var speakChannel: Channel<String>? = null
  private var speakConsumerJob: Job? = null
  private var spokenChars = 0
  private var utteranceSeq = 0
  @Volatile private var streamingTurnActive = false
  private val utteranceCompletions =
    java.util.concurrent.ConcurrentHashMap<String, CompletableDeferred<Unit>>()

  // Optional on-device neural speech recognizer. A single recognizer is kept in memory at a time
  // (SenseVoice OR Whisper, whichever the user selected) to bound memory use; it is loaded lazily on
  // selection and released when switching away. Records raw PCM via [AudioRecorder].
  private var neuralStt: OfflineRecognizer? = null
  private val audioRecorder = AudioRecorder(sampleRate = SPEECH_SAMPLE_RATE)
  // The downloadable models backing the two neural engines (fed by the screen), and which engine's
  // recognizer is currently loaded into [neuralStt].
  private var sttModel: Model? = null
  private var whisperSttModel: Model? = null
  private var loadedSttEngine: SttEngine? = null
  private var loadingStt = false

  // Tool / MCP integration (shared with Agent Skills). Set by the screen via [attachAgentTools].
  private var agentTools: AgentTools? = null
  // Pending MCP tool-call permission request awaiting the user's decision (drives a dialog).
  private val _mcpPermissionRequest = MutableStateFlow<AskMcpToolCallPermissionAction?>(null)
  val mcpPermissionRequest = _mcpPermissionRequest.asStateFlow()

  // Ids used for the neural voice options.
  private val neuralVoiceId = "neural:kss"
  private val meloVoiceId = "neural:melo"
  // System TTS voices (Korean), indexed by their VoiceOption id ("system:<voiceName>").
  private val systemVoicesById = mutableMapOf<String, Voice>()

  init {
    // Resolve the entry topic into a prompt bundle for the title + starters. We intentionally peek
    // (don't consume) so the Task's model initialization can also read the same topic.
    viewModelScope.launch {
      val topic = entryParams.topic.value
      val prompt =
        try {
          promptSource.getPromptForTopic(topic)
        } catch (e: Exception) {
          Log.w(TAG, "Failed to load prompt for topic '$topic'", e)
          null
        }
      topicPrompt = prompt
      prompt?.bcp47Language?.let { tag -> speechLocale = Locale.forLanguageTag(tag) }
      _uiState.update {
        it.copy(topicTitle = prompt?.title ?: "", starters = prompt?.starters ?: listOf())
      }
      initTts()
    }
  }

  private fun initTts() {
    tts =
      TextToSpeech(context) { status ->
        if (status == TextToSpeech.SUCCESS) {
          tts?.let { engine ->
            val result = engine.setLanguage(speechLocale)
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED
            ) {
              engine.language = Locale.US
            }
            engine.setOnUtteranceProgressListener(
              object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                  // During a streaming turn the consumer coroutine owns isSpeaking (it stays true
                  // across the whole reply); leave it alone here to avoid per-sentence flicker.
                  if (!streamingTurnActive) {
                    _uiState.update { it.copy(isSpeaking = true) }
                  }
                }

                override fun onDone(utteranceId: String?) {
                  // Unblock the streaming consumer waiting on this utterance, if any.
                  utteranceId?.let { utteranceCompletions.remove(it)?.complete(Unit) }
                  if (!streamingTurnActive) {
                    _uiState.update { it.copy(isSpeaking = false) }
                  }
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                  utteranceId?.let { utteranceCompletions.remove(it)?.complete(Unit) }
                  if (!streamingTurnActive) {
                    _uiState.update { it.copy(isSpeaking = false) }
                  }
                }
              }
            )
            collectSystemVoices(engine)
          }
          _uiState.update { it.copy(ttsReady = true) }
          rebuildVoiceOptions()
        } else {
          Log.w(TAG, "TextToSpeech init failed with status $status")
        }
      }
  }

  /** Reads the available Korean system TTS voices and remembers them for selection. */
  private fun collectSystemVoices(engine: TextToSpeech) {
    systemVoicesById.clear()
    try {
      val target = speechLocale.language // e.g. "ko"
      val koreanVoices =
        engine.voices
          ?.filter { it.locale?.language == target && !it.isNetworkConnectionRequired }
          ?.sortedBy { it.name }
          ?: emptyList()
      for (voice in koreanVoices) {
        systemVoicesById["system:${voice.name}"] = voice
      }
    } catch (e: Exception) {
      Log.w(TAG, "Failed to read system voices", e)
    }
  }

  /** Rebuilds the selectable voice list (neural + system) and ensures a valid selection. */
  private fun rebuildVoiceOptions() {
    val options = mutableListOf<VoiceOption>()
    // A neural model can host multiple speakers (sherpa-onnx `sid`). Expose one voice option per
    // speaker (id "neural:<engine>#<sid>") so a character can be assigned a specific speaker via the
    // existing per-character voice selection. Single-speaker models keep the plain base id.
    neuralTts?.let { engine ->
      val speakers = engine.numSpeakers().coerceAtLeast(1)
      if (speakers <= 1) {
        options.add(
          VoiceOption(
            id = neuralVoiceId,
            label = "신경망 음성 (KSS)",
            subtitle = "고품질·기기 독립",
            isNeural = true,
          )
        )
      } else {
        for (sid in 0 until speakers) {
          options.add(
            VoiceOption(
              id = "$neuralVoiceId#$sid",
              label = "KSS 화자 ${sid + 1}",
              subtitle = "고품질·기기 독립",
              isNeural = true,
            )
          )
        }
      }
    }
    meloTts?.let { engine ->
      val speakers = engine.numSpeakers().coerceAtLeast(1)
      if (speakers <= 1) {
        options.add(
          VoiceOption(
            id = meloVoiceId,
            label = "MeloTTS (ko)",
            subtitle = "자연스러운 한국어",
            isNeural = true,
          )
        )
      } else {
        for (sid in 0 until speakers) {
          options.add(
            VoiceOption(
              id = "$meloVoiceId#$sid",
              label = "MeloTTS 화자 ${sid + 1}",
              subtitle = "자연스러운 한국어",
              isNeural = true,
            )
          )
        }
      }
    }
    var index = 1
    for ((id, voice) in systemVoicesById) {
      options.add(
        VoiceOption(
          id = id,
          label = "시스템 음성 $index",
          subtitle = voice.name,
          isNeural = false,
        )
      )
      index++
    }

    // Cloud (commercial API) voices — always available (configured by parameters, not downloaded).
    // Added last and never auto-selected so a missing/sample credential can't break the default.
    for ((id, label) in cloudTtsService.voiceOptions()) {
      options.add(VoiceOption(id = id, label = label, isCloud = true))
    }

    // Pick a default selection if none is set or the current one disappeared. Prefer an on-device
    // neural voice, then any other on-device (system) voice — never a cloud voice by default.
    val current = _uiState.value.selectedVoiceId
    val stillValid = options.any { it.id == current }
    val selected =
      when {
        stillValid -> current
        options.any { it.isNeural && !it.isCloud } -> options.first { it.isNeural && !it.isCloud }.id
        options.any { !it.isCloud } -> options.first { !it.isCloud }.id
        options.isNotEmpty() -> options.first().id
        else -> ""
      }
    if (selected != current && selected.startsWith("system:")) {
      systemVoicesById[selected]?.let { tts?.voice = it }
    }
    _uiState.update { it.copy(voices = options, selectedVoiceId = selected) }
  }

  /** Selects the voice to use for spoken replies. */
  fun selectVoice(id: String) {
    if (id == _uiState.value.selectedVoiceId) {
      return
    }
    stopSpeaking()
    if (id.startsWith("system:")) {
      systemVoicesById[id]?.let { tts?.voice = it }
    }
    _uiState.update { it.copy(selectedVoiceId = id) }
  }

  /** Switches between speaking after the full reply (default) and streaming sentence-by-sentence. */
  fun setSpeakMode(mode: TtsSpeakMode) {
    if (mode == _uiState.value.speakMode) {
      return
    }
    stopSpeaking()
    _uiState.update { it.copy(speakMode = mode) }
  }

  // region Speech recognition (STT)

  /** Starts listening to the microphone. The caller must already hold RECORD_AUDIO permission. */
  fun startListening() {
    if (uiState.value.isListening) {
      return
    }
    // Stop any ongoing speech so the assistant doesn't hear itself.
    stopSpeaking()

    // Use the neural recognizer only when a neural engine is selected AND its recognizer is loaded;
    // otherwise fall back to the system recognizer.
    val engine = _uiState.value.sttEngine
    if (engine != SttEngine.SYSTEM && neuralStt != null && loadedSttEngine == engine) {
      startNeuralListening()
      return
    }

    val recognizer = ensureSpeechRecognizer()
    if (recognizer == null) {
      _uiState.update { it.copy(error = "이 기기에서는 음성 인식을 사용할 수 없습니다.") }
      return
    }
    val intent =
      Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, speechLocale.toLanguageTag())
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
      }
    _uiState.update { it.copy(isListening = true, partialTranscript = "", error = "") }
    try {
      recognizer.startListening(intent)
    } catch (e: Exception) {
      Log.e(TAG, "Failed to start listening", e)
      // Count the failed start as a silent turn so the call loop backs off instead of hot-looping on
      // a recognizer that keeps refusing to start.
      consecutiveSilentTurns++
      _uiState.update { it.copy(isListening = false, error = "듣기를 시작할 수 없습니다.") }
    }
  }

  /** Stops listening; final results arrive via [onResults] (system) or are decoded (neural). */
  fun stopListening() {
    if (!uiState.value.isListening) {
      return
    }
    if (usingNeuralCapture) {
      stopNeuralListeningAndTranscribe()
      return
    }
    try {
      speechRecognizer?.stopListening()
    } catch (e: Exception) {
      Log.w(TAG, "Failed to stop listening", e)
    }
    _uiState.update { it.copy(isListening = false) }
  }

  // region Input mode (standard vs hands-free call)

  private var callLoopJob: Job? = null

  /** Switches between standard input (text + one-shot mic) and hands-free call mode. */
  fun setInputMode(mode: ChatInputMode) {
    if (mode == _uiState.value.inputMode) {
      return
    }
    _uiState.update { it.copy(inputMode = mode) }
    if (mode == ChatInputMode.CALL) startCallLoop() else stopCallLoop()
  }

  fun toggleInputMode() {
    setInputMode(
      if (_uiState.value.inputMode == ChatInputMode.CALL) ChatInputMode.STANDARD
      else ChatInputMode.CALL
    )
  }

  /**
   * Half-duplex call loop: a single observer of [uiState] that re-opens the mic whenever the
   * assistant's turn is fully over — but never while it is listening, thinking, or speaking, so the
   * assistant's own TTS is never captured (echo-free). The debounce absorbs the brief think→speak
   * gap so the mic doesn't re-open prematurely.
   */
  private fun startCallLoop() {
    consecutiveSilentTurns = 0
    callLoopJob?.cancel()
    callLoopJob =
      viewModelScope.launch {
        var relisten: Job? = null
        uiState.collect { s ->
          val idle =
            s.inputMode == ChatInputMode.CALL &&
              pendingModel != null &&
              !s.isListening &&
              !s.isThinking &&
              !s.isSpeaking
          if (idle) {
            if (relisten == null) {
              relisten =
                launch {
                  // Snappy after the assistant just spoke; progressively calmer after silent turns so
                  // the mic doesn't flicker open/closed while the user is quiet (and so a busy engine
                  // has time to reset).
                  val cooldown =
                    if (consecutiveSilentTurns > 0)
                      CALL_SILENT_COOLDOWN_MS *
                        consecutiveSilentTurns.coerceAtMost(CALL_SILENT_BACKOFF_CAP)
                    else CALL_RELISTEN_DEBOUNCE_MS
                  delay(cooldown)
                  val now = _uiState.value
                  if (
                    now.inputMode == ChatInputMode.CALL &&
                      !now.isListening &&
                      !now.isThinking &&
                      !now.isSpeaking
                  ) {
                    startListening()
                  }
                  relisten = null
                }
            }
          } else {
            relisten?.cancel()
            relisten = null
          }
        }
      }
    // Open the mic right away on entering call mode.
    startListening()
  }

  private fun stopCallLoop() {
    callLoopJob?.cancel()
    callLoopJob = null
    stopListening()
    stopSpeaking()
  }

  // endregion

  // Whether the in-progress capture is using the neural recorder (vs the system recognizer).
  private var usingNeuralCapture = false

  private fun startNeuralListening() {
    try {
      audioRecorder.start()
      usingNeuralCapture = true
      _uiState.update { it.copy(isListening = true, partialTranscript = "", error = "") }
    } catch (e: Throwable) {
      Log.e(TAG, "Failed to start neural recording", e)
      usingNeuralCapture = false
      _uiState.update { it.copy(isListening = false, error = "녹음을 시작할 수 없습니다.") }
    }
  }

  private fun stopNeuralListeningAndTranscribe() {
    usingNeuralCapture = false
    val samples = audioRecorder.stop()
    _uiState.update { it.copy(isListening = false) }
    val engine = neuralStt
    if (engine == null || samples.isEmpty()) {
      return
    }
    viewModelScope.launch {
      val text =
        withContext(Dispatchers.Default) {
          val stream = engine.createStream()
          try {
            stream.acceptWaveform(samples = samples, sampleRate = SPEECH_SAMPLE_RATE)
            engine.decode(stream)
            engine.getResult(stream).text
          } finally {
            stream.release()
          }
        }
      val trimmed = text.trim()
      if (trimmed.isNotEmpty()) {
        consecutiveSilentTurns = 0
        submitUserInput(trimmed)
      } else {
        consecutiveSilentTurns++
      }
    }
  }

  override fun onReadyForSpeech(params: Bundle?) {}

  override fun onBeginningOfSpeech() {}

  override fun onRmsChanged(rmsdB: Float) {}

  override fun onBufferReceived(buffer: ByteArray?) {}

  override fun onEndOfSpeech() {
    // The user stopped speaking, but the recognizer is still decoding — results haven't arrived yet.
    // Deliberately keep isListening=true until a terminal callback (onResults/onError). Clearing it
    // here would let the call loop re-arm the mic mid-decode, which cancels the in-flight recognition
    // (losing the user's words) and triggers ERROR_RECOGNIZER_BUSY — the open/close spin.
  }

  override fun onError(error: Int) {
    val wasListening = uiState.value.isListening
    _uiState.update { it.copy(isListening = false) }
    // No speech captured this turn → lengthen the call-mode cooldown so we don't spin.
    if (wasListening) consecutiveSilentTurns++
    // A busy/client error means the previous session hadn't fully released; reset the recognizer so
    // the next startListening() gets a clean engine instead of bouncing on BUSY again.
    if (error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY || error == SpeechRecognizer.ERROR_CLIENT) {
      try {
        speechRecognizer?.cancel()
      } catch (e: Exception) {
        Log.w(TAG, "Failed to cancel recognizer after error $error", e)
      }
    }
    // Ignore "no match" / "speech timeout" which are common and not worth surfacing loudly.
    if (error != SpeechRecognizer.ERROR_NO_MATCH && error != SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
      Log.w(TAG, "SpeechRecognizer error: $error")
      // Surface a clear, actionable message for the cases the user can do something about, instead
      // of silently bouncing back to idle.
      val message =
        when (error) {
          SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
            "마이크 권한이 필요해요. 설정에서 마이크 권한을 허용해 주세요."
          SpeechRecognizer.ERROR_NETWORK,
          SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
            "네트워크 음성 인식에 실패했어요. 설정에서 오프라인 음성 인식 모델을 받아보세요."
          else -> ""
        }
      if (message.isNotEmpty()) {
        _uiState.update { it.copy(error = message) }
      }
    }
  }

  override fun onResults(results: Bundle?) {
    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
    val text = matches?.firstOrNull().orEmpty().trim()
    _uiState.update { it.copy(isListening = false, partialTranscript = "") }
    if (text.isNotEmpty()) {
      consecutiveSilentTurns = 0
      submitUserInput(text)
    } else {
      // Empty result counts as a silent turn (back off the next re-listen).
      consecutiveSilentTurns++
    }
  }

  override fun onPartialResults(partialResults: Bundle?) {
    val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
    val text = matches?.firstOrNull().orEmpty()
    _uiState.update { it.copy(partialTranscript = text) }
  }

  override fun onEvent(eventType: Int, params: Bundle?) {}

  // endregion

  /** Sends a typed/tapped starter as if the user had spoken it. */
  fun sendStarter(text: String, model: Model) {
    submitUserInput(text, model)
  }

  /**
   * Switches the active conversation (one per character). Saves the current conversation, stops any
   * in-flight listening/speaking, and loads the target conversation's history (empty if new), so the
   * chat never shows another character's messages.
   */
  fun setConversation(conversationId: String) {
    if (conversationId == activeConversationId) {
      return
    }
    // Don't let the previous character keep listening/talking after the switch.
    stopListening()
    stopSpeaking()
    // Persist the conversation we're leaving (finalize any in-progress streaming message).
    if (activeConversationId.isNotEmpty()) {
      val finalized =
        _uiState.value.messages.map { if (it.isStreaming) it.copy(isStreaming = false) else it }
      messagesByConversation[activeConversationId] = finalized
      persist(activeConversationId, finalized)
    }
    activeConversationId = conversationId
    val cached = messagesByConversation[conversationId]
    if (cached != null) {
      _uiState.update {
        it.copy(messages = cached, isThinking = false, partialTranscript = "", error = "")
      }
    } else {
      // Show empty immediately, then load this character's saved history from disk.
      _uiState.update {
        it.copy(messages = emptyList(), isThinking = false, partialTranscript = "", error = "")
      }
      viewModelScope.launch {
        val loaded = withContext(Dispatchers.IO) { chatHistoryStore.load(conversationId) }
        messagesByConversation[conversationId] = loaded
        if (activeConversationId == conversationId && loaded.isNotEmpty()) {
          _uiState.update { it.copy(messages = loaded) }
        }
      }
    }
  }

  /** Mirrors the live messages back into the active conversation's in-memory history. */
  private fun syncActiveMessages() {
    if (activeConversationId.isNotEmpty()) {
      messagesByConversation[activeConversationId] = _uiState.value.messages
    }
  }

  /**
   * Deletes every message before [index] (keeping the message at [index] and everything after), then
   * persists the trimmed history. Used by the chat bubble's "delete earlier messages" action.
   */
  fun deleteMessagesBefore(index: Int) {
    val current = _uiState.value.messages
    if (index <= 0 || index >= current.size) {
      return
    }
    val trimmed = current.subList(index, current.size).toList()
    _uiState.update { it.copy(messages = trimmed) }
    syncActiveMessages()
    persistActive()
  }

  /**
   * Regenerates the assistant reply at [assistantIndex]: drops that reply (and anything after it) and
   * re-runs inference on the user message that prompted it.
   */
  fun regenerate(assistantIndex: Int) {
    if (_uiState.value.isThinking) {
      return
    }
    val model = pendingModel ?: return
    val messages = _uiState.value.messages
    if (assistantIndex !in messages.indices) {
      return
    }
    if (messages[assistantIndex].role != ChatMessage.Role.ASSISTANT) {
      return
    }
    val userIndex =
      (assistantIndex - 1 downTo 0).firstOrNull {
        messages[it].role == ChatMessage.Role.USER
      } ?: return
    val userText = messages[userIndex].text
    if (userText.isBlank()) {
      return
    }
    stopSpeaking()
    // Keep up to and including the prompting user message; replace the reply with a fresh one.
    val kept = messages.subList(0, userIndex + 1).toList()
    _uiState.update {
      it.copy(
        messages =
          kept + ChatMessage(role = ChatMessage.Role.ASSISTANT, text = "", isStreaming = true),
        isThinking = true,
        error = "",
      )
    }
    syncActiveMessages()
    runLlm(model, userText)
  }

  /**
   * Has the character greet first (used when entering the chat from "start chat"). No-op if a reply
   * is already in progress or the conversation isn't empty. The greeting is generated by the LLM in
   * the character's persona and spoken; the prompt below is sent to the model but not shown as a
   * user message.
   */
  fun greet(model: Model) {
    if (_uiState.value.isThinking || _uiState.value.messages.isNotEmpty()) {
      return
    }
    _uiState.update {
      it.copy(
        messages =
          listOf(ChatMessage(role = ChatMessage.Role.ASSISTANT, text = "", isStreaming = true)),
        isThinking = true,
        error = "",
      )
    }
    syncActiveMessages()
    runLlm(model, GREETING_PROMPT)
  }

  /**
   * Lets the character keep talking on its own (used by the background double-tap). Sends a hidden
   * "continue" instruction to the model but adds NO user message — only the assistant's reply shows.
   * No-op while a reply is already in progress.
   */
  fun continueTalking(model: Model) {
    if (_uiState.value.isThinking) {
      return
    }
    // Interrupt any current speech so the new line doesn't overlap.
    stopSpeaking()
    _uiState.update {
      it.copy(
        messages =
          it.messages + ChatMessage(role = ChatMessage.Role.ASSISTANT, text = "", isStreaming = true),
        isThinking = true,
        error = "",
      )
    }
    syncActiveMessages()
    runLlm(model, CONTINUE_PROMPT)
  }

  /** Clears the whole active conversation and starts fresh. */
  fun clearConversation() {
    stopListening()
    stopSpeaking()
    _uiState.update {
      it.copy(messages = emptyList(), isThinking = false, partialTranscript = "", error = "")
    }
    syncActiveMessages()
    persistActive()
  }

  /** Persists [messages] for [conversationId] to disk off the main thread. */
  private fun persist(conversationId: String, messages: List<ChatMessage>) {
    viewModelScope.launch(Dispatchers.IO) { chatHistoryStore.save(conversationId, messages) }
  }

  /** Persists the active conversation's current messages to disk. */
  private fun persistActive() {
    if (activeConversationId.isNotEmpty()) {
      persist(activeConversationId, _uiState.value.messages)
    }
  }

  private var pendingModel: Model? = null

  /** Lets the screen provide the currently selected (initialized) model. */
  fun setActiveModel(model: Model) {
    pendingModel = model
  }

  private var koreanTtsModel: Model? = null
  private var preparing = false

  /**
   * Feeds the latest download state of the Korean neural voice from the screen, and drives the
   * preparation pipeline (download → unpack/init → ready) while exposing it via [uiState].
   *
   * @param model the Korean TTS model (or null if it isn't registered).
   * @param downloadStatus the model's current download status from the model manager (or null).
   */
  fun onKoreanTtsStatus(model: Model?, downloadStatus: ModelDownloadStatus?) {
    koreanTtsModel = model
    if (model == null) {
      updateNeuralStage(NeuralVoiceState(stage = NeuralVoiceStage.NOT_INSTALLED))
      return
    }
    // Already loaded → nothing to do.
    if (neuralTts != null) {
      return
    }

    when (downloadStatus?.status) {
      ModelDownloadStatusType.IN_PROGRESS,
      ModelDownloadStatusType.PARTIALLY_DOWNLOADED,
      ModelDownloadStatusType.UNZIPPING -> {
        val total = downloadStatus.totalBytes
        val received = downloadStatus.receivedBytes
        val pct = if (total > 0L) (received * 100 / total).toInt() else -1
        updateNeuralStage(
          NeuralVoiceState(
            stage = NeuralVoiceStage.DOWNLOADING,
            downloadPercent = pct,
            downloadedBytes = received,
            totalBytes = total,
            bytesPerSecond = downloadStatus.bytesPerSecond,
            remainingMs = downloadStatus.remainingMs,
          )
        )
      }
      ModelDownloadStatusType.SUCCEEDED -> {
        // Download done → unpack + initialize the engine (unless we're already on it).
        prepareNeuralEngine(model)
      }
      ModelDownloadStatusType.FAILED -> {
        updateNeuralStage(
          NeuralVoiceState(
            stage = NeuralVoiceStage.ERROR,
            error = downloadStatus.errorMessage.ifEmpty { "다운로드에 실패했습니다." },
          )
        )
      }
      else -> {
        // NOT_DOWNLOADED or unknown: only reset to NOT_INSTALLED if we're not mid-preparation.
        if (!preparing && _uiState.value.neuralVoice.stage != NeuralVoiceStage.PREPARING) {
          updateNeuralStage(NeuralVoiceState(stage = NeuralVoiceStage.NOT_INSTALLED))
        }
      }
    }
  }

  /** Unpacks the downloaded archive and initializes the sherpa-onnx engine, updating UI stages. */
  private fun prepareNeuralEngine(model: Model) {
    if (preparing || neuralTts != null) {
      return
    }
    preparing = true
    updateNeuralStage(NeuralVoiceState(stage = NeuralVoiceStage.PREPARING, unpackPercent = -1))
    viewModelScope.launch {
      val result =
        withContext(Dispatchers.IO) {
          KoreanNeuralTts.load(
            context = context,
            model = model,
            onUnpackProgress = { pct ->
              // Reflect unpack progress on the UI (only meaningful when an extraction runs).
              updateNeuralStage(
                NeuralVoiceState(stage = NeuralVoiceStage.PREPARING, unpackPercent = pct)
              )
            },
          )
        }
      when (result) {
        is KoreanTtsLoadResult.Success -> {
          neuralTts = result.tts
          updateNeuralStage(NeuralVoiceState(stage = NeuralVoiceStage.READY))
          if (
            _uiState.value.selectedVoiceId.isEmpty() ||
              _uiState.value.selectedVoiceId.startsWith("system:")
          ) {
            _uiState.update { it.copy(selectedVoiceId = neuralVoiceId) }
          }
          rebuildVoiceOptions()
          Log.d(TAG, "Korean neural TTS ready.")
        }
        is KoreanTtsLoadResult.NotDownloaded -> {
          updateNeuralStage(NeuralVoiceState(stage = NeuralVoiceStage.NOT_INSTALLED))
        }
        is KoreanTtsLoadResult.Failure -> {
          updateNeuralStage(
            NeuralVoiceState(stage = NeuralVoiceStage.ERROR, error = result.message)
          )
        }
      }
      preparing = false
    }
  }

  /** Retries preparing the neural voice after a failure (re-extract; the archive is reused). */
  fun retryNeuralPreparation() {
    val model = koreanTtsModel ?: return
    // Clear any partial extraction so we start clean, then re-run preparation.
    viewModelScope.launch {
      withContext(Dispatchers.IO) { KoreanNeuralTts.clearExtracted(context, model) }
      prepareNeuralEngine(model)
    }
  }

  private fun updateNeuralStage(state: NeuralVoiceState) {
    _uiState.update { it.copy(neuralVoice = state) }
  }

  // region MeloTTS Korean voice (optional, downloadable) — mirrors the KSS neural-voice pipeline.

  private var meloTtsModel: Model? = null
  private var preparingMelo = false

  /**
   * Feeds the latest download state of the MeloTTS Korean voice from the screen and drives its
   * preparation (download → unpack/init → ready), exposed via [uiState] like the KSS voice.
   */
  fun onMeloTtsStatus(model: Model?, downloadStatus: ModelDownloadStatus?) {
    meloTtsModel = model
    if (model == null) {
      updateMeloStage(NeuralVoiceState(stage = NeuralVoiceStage.NOT_INSTALLED))
      return
    }
    if (meloTts != null) {
      return
    }
    when (downloadStatus?.status) {
      ModelDownloadStatusType.IN_PROGRESS,
      ModelDownloadStatusType.PARTIALLY_DOWNLOADED,
      ModelDownloadStatusType.UNZIPPING -> {
        val total = downloadStatus.totalBytes
        val received = downloadStatus.receivedBytes
        val pct = if (total > 0L) (received * 100 / total).toInt() else -1
        updateMeloStage(
          NeuralVoiceState(
            stage = NeuralVoiceStage.DOWNLOADING,
            downloadPercent = pct,
            downloadedBytes = received,
            totalBytes = total,
            bytesPerSecond = downloadStatus.bytesPerSecond,
            remainingMs = downloadStatus.remainingMs,
          )
        )
      }
      ModelDownloadStatusType.SUCCEEDED -> prepareMeloEngine(model)
      ModelDownloadStatusType.FAILED ->
        updateMeloStage(
          NeuralVoiceState(
            stage = NeuralVoiceStage.ERROR,
            error = downloadStatus.errorMessage.ifEmpty { "다운로드에 실패했습니다." },
          )
        )
      else ->
        if (!preparingMelo && _uiState.value.meloVoice.stage != NeuralVoiceStage.PREPARING) {
          updateMeloStage(NeuralVoiceState(stage = NeuralVoiceStage.NOT_INSTALLED))
        }
    }
  }

  /** Unpacks the downloaded MeloTTS archive and initializes the sherpa-onnx engine. */
  private fun prepareMeloEngine(model: Model) {
    if (preparingMelo || meloTts != null) {
      return
    }
    preparingMelo = true
    updateMeloStage(NeuralVoiceState(stage = NeuralVoiceStage.PREPARING, unpackPercent = -1))
    viewModelScope.launch {
      val result =
        withContext(Dispatchers.IO) {
          MeloNeuralTts.load(
            context = context,
            model = model,
            onUnpackProgress = { pct ->
              updateMeloStage(
                NeuralVoiceState(stage = NeuralVoiceStage.PREPARING, unpackPercent = pct)
              )
            },
          )
        }
      when (result) {
        is MeloTtsLoadResult.Success -> {
          meloTts = result.tts
          updateMeloStage(NeuralVoiceState(stage = NeuralVoiceStage.READY))
          rebuildVoiceOptions()
          Log.d(TAG, "MeloTTS Korean voice ready.")
        }
        is MeloTtsLoadResult.NotDownloaded ->
          updateMeloStage(NeuralVoiceState(stage = NeuralVoiceStage.NOT_INSTALLED))
        is MeloTtsLoadResult.Failure ->
          updateMeloStage(NeuralVoiceState(stage = NeuralVoiceStage.ERROR, error = result.message))
      }
      preparingMelo = false
    }
  }

  /** Retries preparing the MeloTTS voice after a failure (re-extract; the archive is reused). */
  fun retryMeloPreparation() {
    val model = meloTtsModel ?: return
    viewModelScope.launch {
      withContext(Dispatchers.IO) { MeloNeuralTts.clearExtracted(context, model) }
      prepareMeloEngine(model)
    }
  }

  private fun updateMeloStage(state: NeuralVoiceState) {
    _uiState.update { it.copy(meloVoice = state) }
  }

  // endregion

  // region Neural STT (optional, downloadable)
  //
  // Two neural recognizers are offered — SenseVoice and Whisper (small, multilingual). Each is an
  // independent download whose *availability* is tracked separately (uiState.neuralStt /
  // uiState.whisperStt). To bound memory, only ONE recognizer is held in [neuralStt] at a time: it
  // is loaded lazily when the user selects that engine and released when switching away.

  /** Feeds the latest download state of the SenseVoice recognizer from the screen. */
  fun onNeuralSttStatus(model: Model?, downloadStatus: ModelDownloadStatus?) {
    sttModel = model
    updateSttAvailability(SttEngine.NEURAL, model, downloadStatus)
  }

  /** Feeds the latest download state of the Whisper recognizer from the screen. */
  fun onWhisperSttStatus(model: Model?, downloadStatus: ModelDownloadStatus?) {
    whisperSttModel = model
    updateSttAvailability(SttEngine.WHISPER, model, downloadStatus)
  }

  /** Maps a model's download status to the per-engine availability state (no engine is loaded here). */
  private fun updateSttAvailability(
    engine: SttEngine,
    model: Model?,
    downloadStatus: ModelDownloadStatus?,
  ) {
    if (model == null) {
      setSttEngineState(engine, NeuralSttState(stage = NeuralVoiceStage.NOT_INSTALLED))
      return
    }
    when (downloadStatus?.status) {
      ModelDownloadStatusType.IN_PROGRESS,
      ModelDownloadStatusType.PARTIALLY_DOWNLOADED,
      ModelDownloadStatusType.UNZIPPING -> {
        val total = downloadStatus.totalBytes
        val received = downloadStatus.receivedBytes
        val pct = if (total > 0L) (received * 100 / total).toInt() else -1
        setSttEngineState(
          engine,
          NeuralSttState(
            stage = NeuralVoiceStage.DOWNLOADING,
            downloadPercent = pct,
            bytesPerSecond = downloadStatus.bytesPerSecond,
            remainingMs = downloadStatus.remainingMs,
          ),
        )
      }
      ModelDownloadStatusType.SUCCEEDED -> {
        setSttEngineState(engine, NeuralSttState(stage = NeuralVoiceStage.READY))
        // If the user already selected this engine while it was still downloading, load it now.
        if (_uiState.value.sttEngine == engine) {
          ensureActiveRecognizer(engine)
        }
      }
      ModelDownloadStatusType.FAILED ->
        setSttEngineState(
          engine,
          NeuralSttState(
            stage = NeuralVoiceStage.ERROR,
            error = downloadStatus.errorMessage.ifEmpty { "다운로드에 실패했습니다." },
          ),
        )
      else ->
        // Don't clobber an already-available engine (e.g. files present from a previous session).
        if (sttEngineState(engine).stage != NeuralVoiceStage.READY) {
          setSttEngineState(engine, NeuralSttState(stage = NeuralVoiceStage.NOT_INSTALLED))
        }
    }
  }

  /**
   * Ensures [neuralStt] holds the recognizer for [engine] (loading it and releasing any other), or
   * does nothing for SYSTEM / when the model isn't downloaded yet. Loads off the main thread; on
   * failure it surfaces an error on that engine and falls back to the system recognizer.
   */
  private fun ensureActiveRecognizer(engine: SttEngine) {
    if (engine == SttEngine.SYSTEM) {
      releaseActiveRecognizer()
      return
    }
    if (loadedSttEngine == engine && neuralStt != null) {
      return
    }
    if (loadingStt) {
      return
    }
    val model =
      when (engine) {
        SttEngine.NEURAL -> sttModel
        SttEngine.WHISPER -> whisperSttModel
        else -> null
      } ?: return // Not downloaded yet; the download banner handles fetching it.
    loadingStt = true
    viewModelScope.launch {
      releaseActiveRecognizer()
      val langHint = if (speechLocale.language == "ko") "ko" else "auto"
      val result =
        withContext(Dispatchers.IO) {
          when (engine) {
            SttEngine.WHISPER ->
              WhisperNeuralStt.load(
                context = context,
                model = model,
                language = if (langHint == "auto") "" else langHint,
              )
            else -> KoreanNeuralStt.load(context = context, model = model, languageHint = langHint)
          }
        }
      when (result) {
        is NeuralSttLoadResult.Success -> {
          neuralStt = result.recognizer
          loadedSttEngine = engine
          setSttEngineState(engine, NeuralSttState(stage = NeuralVoiceStage.READY))
          Log.d(TAG, "Neural STT ready: $engine")
        }
        is NeuralSttLoadResult.NotDownloaded -> {
          setSttEngineState(engine, NeuralSttState(stage = NeuralVoiceStage.NOT_INSTALLED))
          fallBackToSystemIfSelected(engine)
        }
        is NeuralSttLoadResult.Failure -> {
          setSttEngineState(engine, NeuralSttState(stage = NeuralVoiceStage.ERROR, error = result.message))
          fallBackToSystemIfSelected(engine)
        }
      }
      loadingStt = false
    }
  }

  private fun releaseActiveRecognizer() {
    try {
      neuralStt?.release()
    } catch (e: Throwable) {
      Log.w(TAG, "Failed to release neural recognizer", e)
    }
    neuralStt = null
    loadedSttEngine = null
  }

  private fun fallBackToSystemIfSelected(engine: SttEngine) {
    if (_uiState.value.sttEngine == engine) {
      _uiState.update { it.copy(sttEngine = SttEngine.SYSTEM) }
    }
  }

  /** Retries loading the SenseVoice recognizer after a failure (reuses the downloaded files). */
  fun retryNeuralSttPreparation() {
    ensureActiveRecognizer(SttEngine.NEURAL)
  }

  /** Retries loading the Whisper recognizer after a failure (reuses the downloaded files). */
  fun retryWhisperSttPreparation() {
    ensureActiveRecognizer(SttEngine.WHISPER)
  }

  /** Selects which engine recognizes the user's speech, loading/releasing recognizers as needed. */
  fun selectSttEngine(engine: SttEngine) {
    if (engine == _uiState.value.sttEngine) {
      return
    }
    // Don't switch while actively listening.
    if (uiState.value.isListening) {
      stopListening()
    }
    _uiState.update { it.copy(sttEngine = engine) }
    ensureActiveRecognizer(engine)
  }

  private fun setSttEngineState(engine: SttEngine, state: NeuralSttState) {
    when (engine) {
      SttEngine.WHISPER -> _uiState.update { it.copy(whisperStt = state) }
      else -> _uiState.update { it.copy(neuralStt = state) }
    }
  }

  private fun sttEngineState(engine: SttEngine): NeuralSttState =
    if (engine == SttEngine.WHISPER) _uiState.value.whisperStt else _uiState.value.neuralStt

  // endregion

  // region Tools / MCP

  /**
   * Attaches the shared [AgentTools] (already wired with skill/MCP managers by the screen) and
   * starts consuming its action channel so MCP tool-call permission prompts and progress are
   * surfaced. Safe to call repeatedly; only the first call starts the collector.
   */
  fun attachAgentTools(tools: AgentTools) {
    if (agentTools === tools) {
      return
    }
    agentTools = tools
    viewModelScope.launch {
      for (action in tools.actionChannel) {
        handleAgentAction(action)
      }
    }
  }

  private fun handleAgentAction(action: AgentAction) {
    when (action) {
      is AskMcpToolCallPermissionAction -> {
        // Surface a permission dialog; the screen completes action.result via [resolveMcpPermission].
        _mcpPermissionRequest.value = action
      }
      is SkillProgressAgentAction -> {
        // Reflect tool activity as a short status line; clear it when the step finishes.
        _uiState.update {
          it.copy(toolActivity = if (action.inProgress) action.label else "")
        }
      }
      // The following actions need a UI surface the voice flow doesn't provide (web view, free-text
      // input, runtime Android permission). Their `runMcpTool`/skill callers await a result, so we
      // MUST complete the deferred immediately to avoid hanging the inference; we resolve them as
      // "unsupported"/denied so the model can move on and tell the user.
      is CallJsAgentAction -> {
        action.result.complete(
          "{\"error\":\"JS skills are not supported in the Voice Assistant\",\"status\":\"failed\"}"
        )
      }
      is AskInfoAgentAction -> action.result.complete("")
      is RequestPermissionAgentAction -> action.result.complete(false)
      else -> {
        // Nothing else is emitted by the tools we expose.
      }
    }
  }

  /** Completes a pending MCP tool-call permission request with the user's choice. */
  fun resolveMcpPermission(result: PermissionResult) {
    val pending = _mcpPermissionRequest.value ?: return
    pending.result.complete(result)
    _mcpPermissionRequest.value = null
  }

  /** Updates the count of available MCP tools (drives the "tools available" UI). */
  fun setMcpToolCount(count: Int) {
    if (count != _uiState.value.mcpToolCount) {
      _uiState.update { it.copy(mcpToolCount = count) }
    }
  }

  /** Updates the count of selected skills (drives the "skills available" UI). */
  fun setSkillCount(count: Int) {
    if (count != _uiState.value.skillCount) {
      _uiState.update { it.copy(skillCount = count) }
    }
  }

  // endregion

  private fun submitUserInput(text: String, model: Model? = null) {
    val activeModel = model ?: pendingModel
    if (activeModel == null) {
      _uiState.update { it.copy(error = "모델이 아직 준비되지 않았습니다.") }
      return
    }
    // Append the user message and an empty streaming assistant message.
    _uiState.update {
      it.copy(
        messages =
          it.messages +
            ChatMessage(role = ChatMessage.Role.USER, text = text) +
            ChatMessage(role = ChatMessage.Role.ASSISTANT, text = "", isStreaming = true),
        isThinking = true,
        error = "",
      )
    }
    syncActiveMessages()
    runLlm(activeModel, text)
  }

  // Guards a single in-flight generation. Bumped on every new generation (and when the watchdog gives
  // up on a stalled one) so late callbacks from an abandoned run can't resurrect the UI.
  @Volatile private var generationSeq = 0L
  private var watchdogJob: Job? = null

  /** Marks the current generation finished: cancels the stall watchdog and clears the thinking flag. */
  private fun finishGeneration() {
    watchdogJob?.cancel()
    watchdogJob = null
  }

  private fun runLlm(model: Model, input: String) {
    val builder = StringBuilder()
    // The conversation this generation belongs to. If the user switches characters mid-generation,
    // stale results must not leak into the new conversation.
    val convId = activeConversationId
    val genId = ++generationSeq
    // In STREAMING mode we speak each finished sentence as it arrives; in AFTER_COMPLETE we speak
    // the whole reply once generation finishes (the original behavior).
    val streamingSpeech = _uiState.value.speakMode == TtsSpeakMode.STREAMING
    if (streamingSpeech) {
      beginStreamingSpeech()
    }

    // Stall watchdog: while output keeps arriving (even slowly) we leave generation alone; if it goes
    // completely silent for GENERATION_STALL_TIMEOUT_MS we recover so "생각 중" can't hang forever.
    val lastOutputAt = java.util.concurrent.atomic.AtomicLong(android.os.SystemClock.elapsedRealtime())
    watchdogJob?.cancel()
    watchdogJob =
      viewModelScope.launch {
        while (generationSeq == genId && _uiState.value.isThinking) {
          val idleMs = android.os.SystemClock.elapsedRealtime() - lastOutputAt.get()
          if (idleMs >= GENERATION_STALL_TIMEOUT_MS) {
            Log.w(TAG, "Generation stalled (${idleMs}ms with no output); recovering from '생각 중'")
            generationSeq++ // invalidate any late callbacks from this stalled run
            if (streamingSpeech) cancelStreamingSpeech()
            _uiState.update { state ->
              val messages = state.messages.toMutableList()
              val last = messages.indexOfLast { it.role == ChatMessage.Role.ASSISTANT }
              if (last >= 0) messages[last] = messages[last].copy(isStreaming = false)
              state.copy(
                messages = messages,
                isThinking = false,
                error = "응답이 너무 지연돼 멈췄어요. 다시 시도해 주세요.",
              )
            }
            break
          }
          delay(2_000)
        }
      }

    try {
      model.runtimeHelper.runInference(
        model = model,
        input = input,
        resultListener = { partialResult, done, thought ->
          // DIAGNOSTIC: shows exactly what the model streams (content vs control/thought tokens) so
          // we can tell whether it is emitting a tool call or just chatting. Remove once resolved.
          Log.i(
            TAG,
            "stream partial=${partialResult.take(80).replace("\n", "\\n")} done=$done " +
              "thought=${thought?.take(40)?.replace("\n", "\\n")}",
          )
          if (activeConversationId == convId && generationSeq == genId) {
            // Any output (content or thought) counts as progress — keep the watchdog from firing.
            lastOutputAt.set(android.os.SystemClock.elapsedRealtime())
            if (!partialResult.startsWith("<ctrl")) {
              builder.append(partialResult)
              updateStreamingAssistant(builder.toString(), streaming = !done)
              if (streamingSpeech) {
                // Speak from a code-free view so code blocks are never read aloud (the on-screen
                // text above keeps the code).
                enqueueReadySentences(speakableStreamingView(builder.toString()))
              }
            }
            if (done) {
              finishGeneration()
              val full = builder.toString().trim()
              _uiState.update { it.copy(isThinking = false) }
              if (streamingSpeech) {
                finishStreamingSpeech(speakableStreamingView(builder.toString()))
              } else if (full.isNotEmpty()) {
                speak(full)
              }
              // Play a visual emotion effect for any emoji in the reply (they're not spoken).
              val emojis = extractEmojis(builder.toString())
              if (emojis.isNotEmpty()) {
                _emotionCues.tryEmit(EmotionCue(emojis = emojis.distinct(), id = emotionCueSeq++))
              }
              // Persist the completed turn so it survives character switches and app restarts.
              persistActive()
            }
          }
        },
        cleanUpListener = {},
        onError = { message ->
          Log.e(TAG, "Inference error: $message")
          if (streamingSpeech) {
            cancelStreamingSpeech()
          }
          if (activeConversationId == convId && generationSeq == genId) {
            finishGeneration()
            _uiState.update {
              it.copy(isThinking = false, error = message.ifEmpty { "문제가 발생했습니다." })
            }
            updateStreamingAssistant(builder.toString(), streaming = false)
          }
        },
        coroutineScope = viewModelScope,
      )
    } catch (e: Exception) {
      Log.e(TAG, "Failed to run inference", e)
      finishGeneration()
      if (streamingSpeech) {
        cancelStreamingSpeech()
      }
      _uiState.update { it.copy(isThinking = false, error = e.message ?: "추론에 실패했습니다.") }
      updateStreamingAssistant(builder.toString(), streaming = false)
    }
  }

  /** Replaces the trailing assistant message content as it streams in. */
  private fun updateStreamingAssistant(content: String, streaming: Boolean) {
    _uiState.update { state ->
      val messages = state.messages.toMutableList()
      val lastIndex = messages.indexOfLast { it.role == ChatMessage.Role.ASSISTANT }
      if (lastIndex >= 0) {
        messages[lastIndex] = messages[lastIndex].copy(text = content, isStreaming = streaming)
      }
      state.copy(messages = messages)
    }
    syncActiveMessages()
  }

  // region Text to speech (TTS)

  // Resolves the selected voice id to a neural engine + speaker id (sid), or null engine for the
  // system voice. Voice ids may carry a speaker suffix, e.g. "neural:melo#3".
  private fun resolveNeuralVoice(selectedId: String): Pair<OfflineTts?, Int> {
    val base = selectedId.substringBefore('#')
    val sid = selectedId.substringAfter('#', "").toIntOrNull() ?: 0
    val melo = meloTts
    val kss = neuralTts
    return when {
      melo != null && base == meloVoiceId -> melo to sid
      kss != null && (base == neuralVoiceId || selectedId.isEmpty()) -> kss to sid
      else -> null to 0
    }
  }

  private fun speak(text: String) {
    // Strip emoji/symbols so they aren't read aloud; skip if nothing speakable remains.
    val spoken = sanitizeForSpeech(text)
    if (spoken.isBlank()) {
      return
    }
    val selectedId = _uiState.value.selectedVoiceId
    // Cloud (commercial API) voice.
    if (cloudTtsService.isCloudVoice(selectedId)) {
      speakCloud(selectedId, spoken)
      return
    }
    // Use whichever voice the user selected. A neural voice is used only when it is both selected
    // and loaded; otherwise we speak with the system engine (which already has the chosen system
    // voice applied via selectVoice/rebuildVoiceOptions).
    val (engine, sid) = resolveNeuralVoice(selectedId)
    if (engine != null) {
      speakNeural(engine, spoken, sid)
    } else {
      val system = tts ?: return
      system.speak(spoken, TextToSpeech.QUEUE_FLUSH, null, ASSISTANT_UTTERANCE_ID)
    }
  }

  /** Synthesizes [text] via the configured cloud TTS API and plays it through [audioPlayer]. */
  private fun speakCloud(voiceId: String, text: String) {
    viewModelScope.launch {
      _uiState.update { it.copy(isSpeaking = true) }
      try {
        val audio = withContext(Dispatchers.IO) { cloudTtsService.synthesize(voiceId, text) }
        if (audio != null) {
          audioPlayer.play(samples = audio.samples, sampleRate = audio.sampleRate)
        } else {
          _uiState.update { it.copy(error = "음성 API 호출에 실패했어요. 설정의 인증 정보를 확인해주세요.") }
        }
      } catch (e: Throwable) {
        Log.w(TAG, "Cloud TTS playback failed", e)
      } finally {
        _uiState.update { it.copy(isSpeaking = false) }
      }
    }
  }

  private fun speakNeural(engine: OfflineTts, text: String, sid: Int) {
    val safeSid = sid.coerceIn(0, (engine.numSpeakers() - 1).coerceAtLeast(0))
    viewModelScope.launch {
      _uiState.update { it.copy(isSpeaking = true) }
      try {
        val audio =
          withContext(Dispatchers.Default) { engine.generate(text = text, sid = safeSid, speed = 1.0f) }
        audioPlayer.play(samples = audio.samples, sampleRate = audio.sampleRate)
      } catch (e: Throwable) {
        Log.w(TAG, "Neural TTS synthesis failed", e)
      } finally {
        _uiState.update { it.copy(isSpeaking = false) }
      }
    }
  }

  // --- Streaming TTS: speak each finished sentence as the reply is generated ---

  /** Starts a fresh streaming-speech turn: clears prior speech and launches the sentence consumer. */
  private fun beginStreamingSpeech() {
    cancelStreamingSpeech()
    spokenChars = 0
    streamingTurnActive = true
    val channel = Channel<String>(Channel.UNLIMITED)
    speakChannel = channel
    speakConsumerJob =
      viewModelScope.launch {
        try {
          var first = true
          // Receives sentences until the channel is closed (turn finished) or cancelled (barge-in).
          for (segment in channel) {
            if (first) {
              _uiState.update { it.copy(isSpeaking = true) }
            }
            speakSegmentToCompletion(segment, flush = first)
            first = false
          }
        } catch (e: Throwable) {
          if (e !is kotlinx.coroutines.CancellationException) {
            Log.w(TAG, "Streaming speech consumer failed", e)
          }
        } finally {
          streamingTurnActive = false
          _uiState.update { it.copy(isSpeaking = false) }
        }
      }
  }

  /** Extracts any newly-completed sentences from [full] and queues them for speech. */
  private fun enqueueReadySentences(full: String) {
    val channel = speakChannel ?: return
    for (segment in extractReadySegments(full)) {
      channel.trySend(segment)
    }
  }

  /** Queues the trailing (unspoken) text and signals end-of-turn so the consumer can finish. */
  private fun finishStreamingSpeech(full: String) {
    val channel = speakChannel ?: return
    val tail = full.substring(spokenChars.coerceIn(0, full.length)).trim()
    if (tail.isNotEmpty()) {
      channel.trySend(tail)
    }
    spokenChars = full.length
    // Closing lets the consumer drain remaining sentences, then flip isSpeaking off in its finally.
    channel.close()
  }

  /** Cancels any in-flight streaming speech (barge-in / new turn) and releases its resources. */
  private fun cancelStreamingSpeech() {
    speakChannel?.close()
    speakChannel = null
    speakConsumerJob?.cancel()
    speakConsumerJob = null
    utteranceCompletions.values.forEach { it.complete(Unit) }
    utteranceCompletions.clear()
    streamingTurnActive = false
  }

  /**
   * Returns the run of [full] that has become "ready to speak" since the last call — everything up
   * to and including the last sentence terminator — advancing [spokenChars] past it. Terminators are
   * kept (they shape TTS prosody). A trailing partial sentence is left for later, unless the pending
   * text has grown past [STREAMING_SOFT_FLUSH_CHARS] (then it's flushed at the last word boundary).
   */
  private fun extractReadySegments(full: String): List<String> {
    if (spokenChars >= full.length) {
      return emptyList()
    }
    val pending = full.substring(spokenChars)
    var cut = pending.lastIndexOfAny(SENTENCE_TERMINATORS)
    if (cut < 0 && pending.length >= STREAMING_SOFT_FLUSH_CHARS) {
      // No sentence end yet, but it's getting long — flush up to the last word boundary.
      cut = pending.lastIndexOf(' ')
    }
    if (cut < 0) {
      return emptyList()
    }
    spokenChars += cut + 1
    val ready = pending.substring(0, cut + 1).trim()
    return if (ready.isEmpty()) emptyList() else listOf(ready)
  }

  /** Speaks one [text] segment and suspends until it has finished playing. */
  private suspend fun speakSegmentToCompletion(text: String, flush: Boolean) {
    // Strip emoji/symbols so they aren't read aloud; skip a segment that becomes empty.
    val spoken = sanitizeForSpeech(text)
    if (spoken.isBlank()) {
      return
    }
    val selectedId = _uiState.value.selectedVoiceId
    // Cloud (commercial API) voice: synthesize the segment, then play it to completion.
    if (cloudTtsService.isCloudVoice(selectedId)) {
      try {
        val audio = withContext(Dispatchers.IO) { cloudTtsService.synthesize(selectedId, spoken) }
        if (audio != null) {
          audioPlayer.playToCompletion(samples = audio.samples, sampleRate = audio.sampleRate)
        }
      } catch (e: Throwable) {
        if (e !is kotlinx.coroutines.CancellationException) {
          Log.w(TAG, "Streaming cloud synthesis failed", e)
        } else {
          throw e
        }
      }
      return
    }
    val (engine, sid) = resolveNeuralVoice(selectedId)
    if (engine != null) {
      val safeSid = sid.coerceIn(0, (engine.numSpeakers() - 1).coerceAtLeast(0))
      try {
        val audio =
          withContext(Dispatchers.Default) {
            engine.generate(text = spoken, sid = safeSid, speed = 1.0f)
          }
        audioPlayer.playToCompletion(samples = audio.samples, sampleRate = audio.sampleRate)
      } catch (e: Throwable) {
        if (e !is kotlinx.coroutines.CancellationException) {
          Log.w(TAG, "Streaming neural synthesis failed", e)
        } else {
          throw e
        }
      }
    } else {
      val system = tts ?: return
      val id = "$ASSISTANT_UTTERANCE_ID-${utteranceSeq++}"
      val done = CompletableDeferred<Unit>()
      utteranceCompletions[id] = done
      system.speak(
        spoken,
        if (flush) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD,
        null,
        id,
      )
      try {
        done.await()
      } finally {
        utteranceCompletions.remove(id)
      }
    }
  }

  fun stopSpeaking() {
    cancelStreamingSpeech()
    try {
      tts?.stop()
    } catch (e: Exception) {
      Log.w(TAG, "Failed to stop TTS", e)
    }
    audioPlayer.stop()
    _uiState.update { it.copy(isSpeaking = false) }
  }

  // endregion

  /** Stops all activity (listening + speaking). */
  fun stopAll() {
    stopListening()
    stopSpeaking()
  }

  fun clearError() {
    _uiState.update { it.copy(error = "") }
  }

  override fun onCleared() {
    super.onCleared()
    // Best-effort final save of the active conversation (viewModelScope is cancelled here, so save
    // synchronously).
    if (activeConversationId.isNotEmpty()) {
      try {
        chatHistoryStore.save(activeConversationId, _uiState.value.messages)
      } catch (e: Exception) {
        Log.w(TAG, "Failed to persist chat history on clear", e)
      }
    }
    // onCleared is invoked on the main thread, so it's safe to tear down these engines directly.
    try {
      speechRecognizer?.destroy()
    } catch (e: Exception) {
      Log.w(TAG, "Failed to destroy recognizer", e)
    }
    try {
      tts?.stop()
      tts?.shutdown()
    } catch (e: Exception) {
      Log.w(TAG, "Failed to shutdown TTS", e)
    }
    try {
      audioPlayer.stop()
      neuralTts?.release()
      meloTts?.release()
    } catch (e: Exception) {
      Log.w(TAG, "Failed to release neural TTS", e)
    }
    try {
      if (audioRecorder.isRecording()) {
        audioRecorder.stop()
      }
      neuralStt?.release()
    } catch (e: Exception) {
      Log.w(TAG, "Failed to release neural STT", e)
    }
  }
}
