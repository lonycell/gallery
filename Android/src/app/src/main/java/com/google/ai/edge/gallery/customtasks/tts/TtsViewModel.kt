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

package com.google.ai.edge.gallery.customtasks.tts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.ai.edge.gallery.customtasks.speech.AudioPlayer
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * UI state for [TtsScreen].
 *
 * @param isSynthesizing Whether the model is currently generating audio.
 * @param error The latest error message, or empty if none.
 */
data class TtsUiState(val isSynthesizing: Boolean = false, val error: String = "")

@HiltViewModel
class TtsViewModel @Inject constructor() : ViewModel() {
  private val _uiState = MutableStateFlow(TtsUiState())
  val uiState = _uiState.asStateFlow()

  private val player = AudioPlayer()

  fun speak(instance: TtsModelInstance, text: String, speed: Float) {
    if (text.isBlank()) {
      return
    }
    viewModelScope.launch {
      _uiState.update { it.copy(isSynthesizing = true, error = "") }
      try {
        val audio =
          withContext(Dispatchers.Default) {
            instance.tts.generate(text = text, sid = 0, speed = speed)
          }
        player.play(samples = audio.samples, sampleRate = audio.sampleRate)
      } catch (e: Throwable) {
        _uiState.update { it.copy(error = e.message ?: "Failed to synthesize speech") }
      } finally {
        _uiState.update { it.copy(isSynthesizing = false) }
      }
    }
  }

  fun stop() {
    player.stop()
  }

  override fun onCleared() {
    player.stop()
  }
}
