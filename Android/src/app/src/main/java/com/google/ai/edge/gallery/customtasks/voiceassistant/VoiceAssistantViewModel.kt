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
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.ai.edge.gallery.customtasks.speech.AudioPlayer
import com.google.ai.edge.gallery.customtasks.speech.KoreanNeuralTts
import com.google.ai.edge.gallery.customtasks.voiceassistant.prompts.TopicPrompt
import com.google.ai.edge.gallery.customtasks.voiceassistant.prompts.VoiceAssistantPromptSource
import com.google.ai.edge.gallery.data.Model
import com.google.ai.edge.gallery.runtime.runtimeHelper
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

  // Optional higher-quality Korean neural voice (sherpa-onnx). When loaded, it takes precedence
  // over the system TextToSpeech engine. Played back through [AudioPlayer].
  private var neuralTts: OfflineTts? = null
  private val audioPlayer = AudioPlayer()

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
          }
          _uiState.update { it.copy(ttsReady = true) }
        } else {
          Log.w(TAG, "TextToSpeech init failed with status $status")
        }
      }
  }

  // region Speech recognition (STT)

  /** Starts listening to the microphone. The caller must already hold RECORD_AUDIO permission. */
  fun startListening() {
    val recognizer = speechRecognizer
    if (recognizer == null) {
      _uiState.update { it.copy(error = "이 기기에서는 음성 인식을 사용할 수 없습니다.") }
      return
    }
    if (uiState.value.isListening) {
      return
    }
    // Stop any ongoing speech so the assistant doesn't hear itself.
    stopSpeaking()

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

  /** Stops listening; final results arrive via [onResults]. */
  fun stopListening() {
    if (!uiState.value.isListening) {
      return
    }
    try {
      speechRecognizer?.stopListening()
    } catch (e: Exception) {
      Log.w(TAG, "Failed to stop listening", e)
    }
    _uiState.update { it.copy(isListening = false) }
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
  private var neuralTtsRequested = false

  /** Lets the screen provide the currently selected (initialized) model. */
  fun setActiveModel(model: Model) {
    pendingModel = model
  }

  /**
   * Asks the assistant to use the downloadable Korean neural voice for speech output, if available.
   *
   * The screen passes the Korean TTS [Model] (looked up from the model manager). If its files have
   * been downloaded, we load the sherpa-onnx engine and speak with it; otherwise we silently keep
   * using the system TextToSpeech engine. Loading happens once.
   */
  fun enableNeuralTtsIfAvailable(koreanTtsModel: Model?) {
    if (neuralTtsRequested || koreanTtsModel == null) {
      return
    }
    neuralTtsRequested = true
    viewModelScope.launch {
      val engine = withContext(Dispatchers.IO) { KoreanNeuralTts.tryLoad(context, koreanTtsModel) }
      if (engine != null) {
        neuralTts = engine
        Log.d(TAG, "Korean neural TTS loaded; using it for speech output.")
      } else {
        Log.d(TAG, "Korean neural TTS not available; falling back to system TTS.")
      }
    }
  }

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
    // Prefer the downloadable Korean neural voice when it has been loaded.
    val engine = neuralTts
    if (engine != null) {
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
  }
}
