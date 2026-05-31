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
import com.google.ai.edge.gallery.customtasks.speech.AudioPlayer
import com.google.ai.edge.gallery.customtasks.speech.AudioRecorder
import com.google.ai.edge.gallery.customtasks.speech.KoreanNeuralStt
import com.google.ai.edge.gallery.customtasks.speech.KoreanNeuralTts
import com.google.ai.edge.gallery.customtasks.speech.KoreanTtsLoadResult
import com.google.ai.edge.gallery.customtasks.speech.NeuralSttLoadResult
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val TAG = "AGVoiceAssistant"
private const val ASSISTANT_UTTERANCE_ID = "va_assistant_utterance"

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
  /** State of the downloadable Korean neural voice (download → unpack/init → ready/error). */
  val neuralVoice: NeuralVoiceState = NeuralVoiceState(),
  /** Which engine is used to recognize the user's speech. */
  val sttEngine: SttEngine = SttEngine.SYSTEM,
  /** State of the downloadable neural speech recognizer (download → init → ready/error). */
  val neuralStt: NeuralSttState = NeuralSttState(),
)

@HiltViewModel
class VoiceAssistantViewModel
@Inject
constructor(
  @ApplicationContext private val context: Context,
  private val promptSource: VoiceAssistantPromptSource,
  private val entryParams: VoiceAssistantEntryParams,
) : ViewModel(), RecognitionListener {

  private val _uiState = MutableStateFlow(VoiceAssistantUiState())
  val uiState = _uiState.asStateFlow()

  private var topicPrompt: TopicPrompt? = null
  // The Voice Assistant defaults to Korean for both speech recognition and synthesis. A topic can
  // override this via its bcp47Language.
  private var speechLocale: Locale = Locale.KOREAN

  private val speechRecognizer: SpeechRecognizer? =
    if (SpeechRecognizer.isRecognitionAvailable(context)) {
      SpeechRecognizer.createSpeechRecognizer(context).apply {
        setRecognitionListener(this@VoiceAssistantViewModel)
      }
    } else {
      null
    }

  private var tts: TextToSpeech? = null

  // Optional higher-quality Korean neural voice (sherpa-onnx). When loaded, it is offered as one of
  // the selectable voices and played back through [AudioPlayer].
  private var neuralTts: OfflineTts? = null
  private val audioPlayer = AudioPlayer()

  // Optional on-device neural speech recognizer (sherpa-onnx SenseVoice). When loaded and selected,
  // it replaces the system SpeechRecognizer for input. Records raw PCM via [AudioRecorder].
  private var neuralStt: OfflineRecognizer? = null
  private val audioRecorder = AudioRecorder(sampleRate = SPEECH_SAMPLE_RATE)
  private var sttModel: Model? = null
  private var preparingStt = false

  // Id used for the neural voice option.
  private val neuralVoiceId = "neural:kss"
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
                  _uiState.update { it.copy(isSpeaking = true) }
                }

                override fun onDone(utteranceId: String?) {
                  _uiState.update { it.copy(isSpeaking = false) }
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                  _uiState.update { it.copy(isSpeaking = false) }
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
    if (neuralTts != null) {
      options.add(
        VoiceOption(
          id = neuralVoiceId,
          label = "신경망 음성 (KSS)",
          subtitle = "고품질·기기 독립",
          isNeural = true,
        )
      )
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

    // Pick a default selection if none is set or the current one disappeared.
    val current = _uiState.value.selectedVoiceId
    val stillValid = options.any { it.id == current }
    val selected =
      when {
        stillValid -> current
        options.any { it.isNeural } -> neuralVoiceId
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

  // region Speech recognition (STT)

  /** Starts listening to the microphone. The caller must already hold RECORD_AUDIO permission. */
  fun startListening() {
    if (uiState.value.isListening) {
      return
    }
    // Stop any ongoing speech so the assistant doesn't hear itself.
    stopSpeaking()

    // Use the neural recognizer only when it's selected AND ready; otherwise system recognizer.
    if (_uiState.value.sttEngine == SttEngine.NEURAL && neuralStt != null) {
      startNeuralListening()
      return
    }

    val recognizer = speechRecognizer
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
        submitUserInput(trimmed)
      }
    }
  }

  override fun onReadyForSpeech(params: Bundle?) {}

  override fun onBeginningOfSpeech() {}

  override fun onRmsChanged(rmsdB: Float) {}

  override fun onBufferReceived(buffer: ByteArray?) {}

  override fun onEndOfSpeech() {
    _uiState.update { it.copy(isListening = false) }
  }

  override fun onError(error: Int) {
    _uiState.update { it.copy(isListening = false) }
    // Ignore "no match" / "speech timeout" which are common and not worth surfacing loudly.
    if (error != SpeechRecognizer.ERROR_NO_MATCH && error != SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
      Log.w(TAG, "SpeechRecognizer error: $error")
    }
  }

  override fun onResults(results: Bundle?) {
    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
    val text = matches?.firstOrNull().orEmpty().trim()
    _uiState.update { it.copy(isListening = false, partialTranscript = "") }
    if (text.isNotEmpty()) {
      submitUserInput(text)
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

  // region Neural STT (optional, downloadable) — mirrors the neural TTS pipeline.

  /**
   * Feeds the latest download state of the neural recognizer (SenseVoice) from the screen and drives
   * its preparation (download → init → ready), exposed via [uiState] like the neural voice.
   */
  fun onNeuralSttStatus(model: Model?, downloadStatus: ModelDownloadStatus?) {
    sttModel = model
    if (model == null) {
      updateSttStage(NeuralSttState(stage = NeuralVoiceStage.NOT_INSTALLED))
      return
    }
    if (neuralStt != null) {
      return
    }
    when (downloadStatus?.status) {
      ModelDownloadStatusType.IN_PROGRESS,
      ModelDownloadStatusType.PARTIALLY_DOWNLOADED,
      ModelDownloadStatusType.UNZIPPING -> {
        val total = downloadStatus.totalBytes
        val received = downloadStatus.receivedBytes
        val pct = if (total > 0L) (received * 100 / total).toInt() else -1
        updateSttStage(
          NeuralSttState(
            stage = NeuralVoiceStage.DOWNLOADING,
            downloadPercent = pct,
            bytesPerSecond = downloadStatus.bytesPerSecond,
            remainingMs = downloadStatus.remainingMs,
          )
        )
      }
      ModelDownloadStatusType.SUCCEEDED -> prepareNeuralStt(model)
      ModelDownloadStatusType.FAILED ->
        updateSttStage(
          NeuralSttState(
            stage = NeuralVoiceStage.ERROR,
            error = downloadStatus.errorMessage.ifEmpty { "다운로드에 실패했습니다." },
          )
        )
      else ->
        if (!preparingStt && _uiState.value.neuralStt.stage != NeuralVoiceStage.PREPARING) {
          updateSttStage(NeuralSttState(stage = NeuralVoiceStage.NOT_INSTALLED))
        }
    }
  }

  private fun prepareNeuralStt(model: Model) {
    if (preparingStt || neuralStt != null) {
      return
    }
    preparingStt = true
    updateSttStage(NeuralSttState(stage = NeuralVoiceStage.PREPARING))
    viewModelScope.launch {
      val langHint = if (speechLocale.language == "ko") "ko" else "auto"
      val result =
        withContext(Dispatchers.IO) {
          KoreanNeuralStt.load(context = context, model = model, languageHint = langHint)
        }
      when (result) {
        is NeuralSttLoadResult.Success -> {
          neuralStt = result.recognizer
          updateSttStage(NeuralSttState(stage = NeuralVoiceStage.READY))
          Log.d(TAG, "Neural STT ready.")
        }
        is NeuralSttLoadResult.NotDownloaded ->
          updateSttStage(NeuralSttState(stage = NeuralVoiceStage.NOT_INSTALLED))
        is NeuralSttLoadResult.Failure ->
          updateSttStage(NeuralSttState(stage = NeuralVoiceStage.ERROR, error = result.message))
      }
      preparingStt = false
    }
  }

  /** Retries preparing the neural recognizer after a failure (reuses the downloaded files). */
  fun retryNeuralSttPreparation() {
    val model = sttModel ?: return
    prepareNeuralStt(model)
  }

  /** Selects which engine recognizes the user's speech. Neural is only honored once it's READY. */
  fun selectSttEngine(engine: SttEngine) {
    if (engine == _uiState.value.sttEngine) {
      return
    }
    // Don't switch while actively listening.
    if (uiState.value.isListening) {
      stopListening()
    }
    _uiState.update { it.copy(sttEngine = engine) }
  }

  private fun updateSttStage(state: NeuralSttState) {
    _uiState.update { it.copy(neuralStt = state) }
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
    runLlm(activeModel, text)
  }

  private fun runLlm(model: Model, input: String) {
    val builder = StringBuilder()
    try {
      model.runtimeHelper.runInference(
        model = model,
        input = input,
        resultListener = { partialResult, done, _ ->
          if (!partialResult.startsWith("<ctrl")) {
            builder.append(partialResult)
            updateStreamingAssistant(builder.toString(), streaming = !done)
          }
          if (done) {
            val full = builder.toString().trim()
            _uiState.update { it.copy(isThinking = false) }
            if (full.isNotEmpty()) {
              speak(full)
            }
          }
        },
        cleanUpListener = {},
        onError = { message ->
          Log.e(TAG, "Inference error: $message")
          _uiState.update {
            it.copy(isThinking = false, error = message.ifEmpty { "문제가 발생했습니다." })
          }
          updateStreamingAssistant(builder.toString(), streaming = false)
        },
        coroutineScope = viewModelScope,
      )
    } catch (e: Exception) {
      Log.e(TAG, "Failed to run inference", e)
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
  }

  // region Text to speech (TTS)

  private fun speak(text: String) {
    // Use whichever voice the user selected. The neural voice is used only when it is both selected
    // and loaded; otherwise we speak with the system engine (which already has the chosen system
    // voice applied via selectVoice/rebuildVoiceOptions).
    val selectedId = _uiState.value.selectedVoiceId
    val engine = neuralTts
    if (engine != null && (selectedId == neuralVoiceId || selectedId.isEmpty())) {
      speakNeural(engine, text)
    } else {
      val system = tts ?: return
      system.speak(text, TextToSpeech.QUEUE_FLUSH, null, ASSISTANT_UTTERANCE_ID)
    }
  }

  private fun speakNeural(engine: OfflineTts, text: String) {
    viewModelScope.launch {
      _uiState.update { it.copy(isSpeaking = true) }
      try {
        val audio = withContext(Dispatchers.Default) { engine.generate(text = text, sid = 0, speed = 1.0f) }
        audioPlayer.play(samples = audio.samples, sampleRate = audio.sampleRate)
      } catch (e: Throwable) {
        Log.w(TAG, "Neural TTS synthesis failed", e)
      } finally {
        _uiState.update { it.copy(isSpeaking = false) }
      }
    }
  }

  fun stopSpeaking() {
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
