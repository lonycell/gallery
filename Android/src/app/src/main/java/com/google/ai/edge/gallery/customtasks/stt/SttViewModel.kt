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

package com.google.ai.edge.gallery.customtasks.stt

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.ai.edge.gallery.customtasks.speech.AudioRecorder
import com.google.ai.edge.gallery.customtasks.speech.SPEECH_SAMPLE_RATE
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * UI state for [SttScreen].
 *
 * @param isRecording Whether the microphone is currently capturing audio.
 * @param isTranscribing Whether captured audio is being decoded.
 * @param transcript The latest transcription result.
 * @param error The latest error message, or empty if none.
 */
data class SttUiState(
  val isRecording: Boolean = false,
  val isTranscribing: Boolean = false,
  val transcript: String = "",
  val error: String = "",
)

@HiltViewModel
class SttViewModel @Inject constructor() : ViewModel() {
  private val _uiState = MutableStateFlow(SttUiState())
  val uiState = _uiState.asStateFlow()

  private val recorder = AudioRecorder(sampleRate = SPEECH_SAMPLE_RATE)

  fun startRecording() {
    try {
      recorder.start()
      _uiState.update { it.copy(isRecording = true, error = "") }
    } catch (e: Throwable) {
      _uiState.update { it.copy(isRecording = false, error = e.message ?: "Failed to start recording") }
    }
  }

  fun stopAndTranscribe(instance: SttModelInstance) {
    if (!uiState.value.isRecording) {
      return
    }
    val samples = recorder.stop()
    _uiState.update { it.copy(isRecording = false, isTranscribing = true) }

    viewModelScope.launch {
      try {
        if (samples.isEmpty()) {
          _uiState.update { it.copy(isTranscribing = false, error = "No audio was recorded") }
          return@launch
        }
        val text =
          withContext(Dispatchers.Default) {
            val stream = instance.recognizer.createStream()
            try {
              stream.acceptWaveform(samples = samples, sampleRate = SPEECH_SAMPLE_RATE)
              instance.recognizer.decode(stream)
              instance.recognizer.getResult(stream).text
            } finally {
              stream.release()
            }
          }
        _uiState.update { it.copy(isTranscribing = false, transcript = text) }
      } catch (e: Throwable) {
        _uiState.update {
          it.copy(isTranscribing = false, error = e.message ?: "Failed to transcribe audio")
        }
      }
    }
  }

  fun cancelRecording() {
    if (uiState.value.isRecording) {
      recorder.stop()
      _uiState.update { it.copy(isRecording = false) }
    }
  }

  override fun onCleared() {
    cancelRecording()
  }
}
