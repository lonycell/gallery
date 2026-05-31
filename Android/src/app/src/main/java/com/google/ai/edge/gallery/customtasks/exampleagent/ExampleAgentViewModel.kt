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
package com.google.ai.edge.gallery.customtasks.exampleagent

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.ai.edge.gallery.data.Model
import com.google.ai.edge.gallery.runtime.runtimeHelper
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

private const val TAG = "AGExampleAgent"

/** A single chat turn. */
data class ExampleMessage(val fromUser: Boolean, val text: String, val streaming: Boolean = false)

/** UI state for the example agent screen. */
data class ExampleAgentUiState(
  val messages: List<ExampleMessage> = listOf(),
  val generating: Boolean = false,
  val error: String = "",
)

/**
 * TEMPLATE: a minimal ViewModel that runs LLM inference (with tools) and streams the reply.
 *
 * The important part is [send]: it calls `model.runtimeHelper.runInference(...)`. Because the model
 * was initialized with a tool set (see [ExampleAgentTask]), the runtime will automatically invoke
 * your `@Tool` functions when the model asks for them and continue generating — you don't call the
 * tools yourself here. The streamed text deltas arrive in the `resultListener`.
 */
@HiltViewModel
class ExampleAgentViewModel @Inject constructor() : ViewModel() {
  private val _uiState = MutableStateFlow(ExampleAgentUiState())
  val uiState = _uiState.asStateFlow()

  fun send(model: Model, input: String) {
    if (input.isBlank() || _uiState.value.generating) {
      return
    }
    // Append the user message + an empty assistant message we'll stream into.
    _uiState.update {
      it.copy(
        messages =
          it.messages +
            ExampleMessage(fromUser = true, text = input) +
            ExampleMessage(fromUser = false, text = "", streaming = true),
        generating = true,
        error = "",
      )
    }

    val builder = StringBuilder()
    try {
      model.runtimeHelper.runInference(
        model = model,
        input = input,
        // partialResult arrives as incremental text deltas; accumulate them.
        resultListener = { partialResult, done, _ ->
          if (!partialResult.startsWith("<ctrl")) {
            builder.append(partialResult)
            updateAssistant(builder.toString(), streaming = !done)
          }
          if (done) {
            _uiState.update { it.copy(generating = false) }
          }
        },
        cleanUpListener = {},
        onError = { message ->
          Log.e(TAG, "Inference error: $message")
          _uiState.update { it.copy(generating = false, error = message.ifEmpty { "Error" }) }
          updateAssistant(builder.toString(), streaming = false)
        },
        coroutineScope = viewModelScope,
      )
    } catch (e: Exception) {
      Log.e(TAG, "Failed to run inference", e)
      _uiState.update { it.copy(generating = false, error = e.message ?: "Error") }
      updateAssistant(builder.toString(), streaming = false)
    }
  }

  private fun updateAssistant(text: String, streaming: Boolean) {
    _uiState.update { state ->
      val messages = state.messages.toMutableList()
      val idx = messages.indexOfLast { !it.fromUser }
      if (idx >= 0) {
        messages[idx] = messages[idx].copy(text = text, streaming = streaming)
      }
      state.copy(messages = messages)
    }
  }
}
