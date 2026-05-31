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

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.google.ai.edge.gallery.data.Task
import com.google.ai.edge.gallery.ui.modelmanager.ModelManagerViewModel

/**
 * TEMPLATE: a minimal chat UI for the example agent.
 *
 * It gates on the model being initialized, renders the streamed conversation, and sends the user's
 * text to the [ExampleAgentViewModel]. Tool calls happen transparently inside inference, so there is
 * nothing tool-specific to do here — the assistant's reply already reflects any tool results.
 */
@Composable
fun ExampleAgentScreen(
  task: Task,
  modelManagerViewModel: ModelManagerViewModel,
  viewModel: ExampleAgentViewModel = hiltViewModel(),
) {
  val modelManagerUiState by modelManagerViewModel.uiState.collectAsState()
  val model = modelManagerUiState.selectedModel
  val uiState by viewModel.uiState.collectAsState()
  var input by remember { mutableStateOf("") }

  if (!modelManagerUiState.isModelInitialized(model = model)) {
    Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
      CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 3.dp)
    }
    return
  }

  Column(modifier = Modifier.fillMaxSize().padding(12.dp)) {
    LazyColumn(
      modifier = Modifier.fillMaxWidth().weight(1f),
      verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
      items(uiState.messages) { message -> MessageBubble(message) }
    }

    if (uiState.error.isNotEmpty()) {
      Text(uiState.error, color = MaterialTheme.colorScheme.error)
    }

    Spacer(modifier = Modifier.size(8.dp))
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
      OutlinedTextField(
        value = input,
        onValueChange = { input = it },
        modifier = Modifier.weight(1f),
        placeholder = { Text("Ask for the time, a calculation, …") },
      )
      Spacer(modifier = Modifier.width(8.dp))
      IconButton(
        onClick = {
          val text = input.trim()
          if (text.isNotEmpty()) {
            viewModel.send(model = model, input = text)
            input = ""
          }
        },
        enabled = !uiState.generating,
      ) {
        Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send")
      }
    }
  }
}

@Composable
private fun MessageBubble(message: ExampleMessage) {
  val isUser = message.fromUser
  Row(
    modifier = Modifier.fillMaxWidth(),
    horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
  ) {
    Surface(
      shape = RoundedCornerShape(14.dp),
      color =
        if (isUser) MaterialTheme.colorScheme.primary
        else MaterialTheme.colorScheme.surfaceVariant,
      modifier = Modifier.fillMaxWidth(0.85f),
    ) {
      Text(
        text = message.text.ifEmpty { if (message.streaming) "…" else "" },
        color =
          if (isUser) MaterialTheme.colorScheme.onPrimary
          else MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
      )
    }
  }
}
