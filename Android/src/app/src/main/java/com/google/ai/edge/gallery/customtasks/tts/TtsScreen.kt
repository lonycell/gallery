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

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material.icons.outlined.VolumeUp
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.google.ai.edge.gallery.ui.modelmanager.ModelManagerViewModel

/** The main screen for the Text to Speech custom task. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TtsScreen(
  modelManagerViewModel: ModelManagerViewModel,
  viewModel: TtsViewModel = hiltViewModel(),
) {
  val modelManagerUiState by modelManagerViewModel.uiState.collectAsState()
  val model = modelManagerUiState.selectedModel
  val uiState by viewModel.uiState.collectAsState()

  if (!modelManagerUiState.isModelInitialized(model = model)) {
    Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
      CircularProgressIndicator(
        modifier = Modifier.size(24.dp),
        trackColor = MaterialTheme.colorScheme.surfaceVariant,
        strokeWidth = 3.dp,
      )
    }
    return
  }

  val instance = model.instance as TtsModelInstance
  // Multi-speaker models (e.g. a multi-speaker Korean voice) expose more than one voice; the user
  // picks one by name/index and it's passed as the synthesis `sid`. Single-speaker models hide this.
  val numSpeakers = instance.tts.numSpeakers()
  // Reset the selection when the model changes; clamp keeps it valid for the current model.
  var sid by rememberSaveable(model.name) { mutableIntStateOf(0) }
  if (sid >= numSpeakers) {
    sid = 0
  }
  val speakerLabel: (Int) -> String = { i ->
    instance.speakerNames.getOrNull(i) ?: "음성 ${i + 1}"
  }
  var text by rememberSaveable { mutableStateOf("Hello! This is on-device text to speech.") }
  // Re-read the speed whenever a config value changes (e.g. via the app bar's config dialog).
  val speed by
    remember(modelManagerUiState.configValuesUpdateTrigger) {
      mutableFloatStateOf(model.getFloatConfigValue(TTS_CONFIG_KEY_SPEED, defaultValue = 1.0f))
    }

  Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
    OutlinedTextField(
      value = text,
      onValueChange = { text = it },
      label = { Text("Text to speak") },
      modifier = Modifier.fillMaxWidth().weight(1f),
      keyboardOptions = KeyboardOptions(imeAction = ImeAction.Default),
    )

    // Voice (speaker) picker — only shown when the model actually has more than one voice.
    if (numSpeakers > 1) {
      Spacer(modifier = Modifier.height(8.dp))
      var expanded by remember { mutableStateOf(false) }
      ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
          value = speakerLabel(sid),
          onValueChange = {},
          readOnly = true,
          label = { Text("음성 (${numSpeakers}개 중 선택)") },
          trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
          modifier = Modifier.menuAnchor().fillMaxWidth(),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
          for (i in 0 until numSpeakers) {
            DropdownMenuItem(
              text = { Text(speakerLabel(i)) },
              onClick = {
                sid = i
                expanded = false
              },
            )
          }
        }
      }
    }

    Spacer(modifier = Modifier.height(8.dp))
    Text(
      "Speed: ${"%.1f".format(speed)}x  (change in the config menu above)",
      style = MaterialTheme.typography.bodySmall,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
    )

    if (uiState.error.isNotEmpty()) {
      Spacer(modifier = Modifier.height(8.dp))
      Text(uiState.error, color = MaterialTheme.colorScheme.error)
    }

    Spacer(modifier = Modifier.height(12.dp))
    Row(
      horizontalArrangement = Arrangement.spacedBy(12.dp),
      verticalAlignment = Alignment.CenterVertically,
      modifier = Modifier.fillMaxWidth(),
    ) {
      Button(
        onClick = { viewModel.speak(instance = instance, text = text, speed = speed, sid = sid) },
        enabled = !uiState.isSynthesizing && text.isNotBlank(),
        modifier = Modifier.weight(1f),
      ) {
        if (uiState.isSynthesizing) {
          CircularProgressIndicator(
            modifier = Modifier.size(18.dp),
            strokeWidth = 2.dp,
            color = MaterialTheme.colorScheme.onPrimary,
          )
        } else {
          Icon(Icons.Outlined.VolumeUp, contentDescription = null)
        }
        Spacer(modifier = Modifier.width(8.dp))
        Text(if (uiState.isSynthesizing) "Synthesizing…" else "Speak")
      }

      OutlinedButton(onClick = { viewModel.stop() }) {
        Icon(Icons.Outlined.Stop, contentDescription = null)
        Spacer(modifier = Modifier.width(8.dp))
        Text("Stop")
      }
    }
  }
}
