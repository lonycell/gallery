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

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import com.google.ai.edge.gallery.ui.modelmanager.ModelManagerViewModel

/** The main screen for the Speech to Text custom task. */
@Composable
fun SttScreen(
  modelManagerViewModel: ModelManagerViewModel,
  viewModel: SttViewModel = hiltViewModel(),
) {
  val modelManagerUiState by modelManagerViewModel.uiState.collectAsState()
  val model = modelManagerUiState.selectedModel
  val uiState by viewModel.uiState.collectAsState()
  val context = LocalContext.current

  val permissionLauncher =
    rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
      if (granted) {
        viewModel.startRecording()
      }
    }

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

  val instance = model.instance as SttModelInstance

  Column(
    modifier = Modifier.fillMaxSize().padding(16.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    // Transcript area.
    Box(modifier = Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState())) {
      if (uiState.transcript.isEmpty()) {
        Text(
          "Your transcription will appear here.",
          style = MaterialTheme.typography.bodyMedium,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
          textAlign = TextAlign.Center,
          modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
        )
      } else {
        Text(uiState.transcript, style = MaterialTheme.typography.bodyLarge)
      }
    }

    if (uiState.error.isNotEmpty()) {
      Spacer(modifier = Modifier.height(8.dp))
      Text(uiState.error, color = MaterialTheme.colorScheme.error)
    }

    Spacer(modifier = Modifier.height(16.dp))

    val statusText =
      when {
        uiState.isRecording -> "Recording… tap Stop to transcribe"
        uiState.isTranscribing -> "Transcribing…"
        else -> "Tap Record and start speaking"
      }
    Text(
      statusText,
      style = MaterialTheme.typography.bodySmall,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
    )

    Spacer(modifier = Modifier.height(8.dp))

    if (uiState.isRecording) {
      Button(
        onClick = { viewModel.stopAndTranscribe(instance = instance) },
        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
        modifier = Modifier.fillMaxWidth(),
      ) {
        Icon(Icons.Outlined.Stop, contentDescription = null)
        Spacer(modifier = Modifier.width(8.dp))
        Text("Stop & Transcribe")
      }
    } else {
      Button(
        onClick = {
          val granted =
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
              PackageManager.PERMISSION_GRANTED
          if (granted) {
            viewModel.startRecording()
          } else {
            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
          }
        },
        enabled = !uiState.isTranscribing,
        modifier = Modifier.fillMaxWidth(),
      ) {
        if (uiState.isTranscribing) {
          CircularProgressIndicator(
            modifier = Modifier.size(18.dp),
            strokeWidth = 2.dp,
            color = MaterialTheme.colorScheme.onPrimary,
          )
        } else {
          Icon(Icons.Outlined.Mic, contentDescription = null)
        }
        Spacer(modifier = Modifier.width(8.dp))
        Text("Record")
      }
    }
  }
}
