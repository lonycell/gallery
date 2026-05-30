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

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import com.google.ai.edge.gallery.data.Task
import com.google.ai.edge.gallery.ui.modelmanager.ModelManagerViewModel

/** The main screen for the Voice Assistant custom task. */
@Composable
fun VoiceAssistantScreen(
  task: Task,
  modelManagerViewModel: ModelManagerViewModel,
  viewModel: VoiceAssistantViewModel = hiltViewModel(),
) {
  val modelManagerUiState by modelManagerViewModel.uiState.collectAsState()
  val model = modelManagerUiState.selectedModel
  val uiState by viewModel.uiState.collectAsState()
  val context = LocalContext.current

  // Keep the ViewModel pointed at the active, initialized model.
  LaunchedEffect(model.name) { viewModel.setActiveModel(model) }

  val micPermissionLauncher =
    rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
      if (granted) {
        viewModel.startListening()
      }
    }

  // Cosmic gradient backdrop for a futuristic feel.
  val isDark = isSystemInDarkTheme()
  val backgroundBrush =
    Brush.verticalGradient(
      colors =
        if (isDark) {
          listOf(Color(0xFF05060E), Color(0xFF0B1026), Color(0xFF030308))
        } else {
          listOf(Color(0xFFEAF0FF), Color(0xFFF6F2FF), Color(0xFFFFFFFF))
        }
    )

  Box(modifier = Modifier.fillMaxSize().background(backgroundBrush)) {
    if (!modelManagerUiState.isModelInitialized(model = model)) {
      Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
        CircularProgressIndicator(
          modifier = Modifier.size(28.dp),
          color = MaterialTheme.colorScheme.primary,
          strokeWidth = 3.dp,
        )
      }
      return@Box
    }

    Column(
      modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp),
      horizontalAlignment = Alignment.CenterHorizontally,
    ) {
      Spacer(modifier = Modifier.height(16.dp))

      // Topic title.
      Text(
        text = uiState.topicTitle.ifEmpty { task.label },
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurface,
        textAlign = TextAlign.Center,
      )
      Text(
        text = statusLabel(uiState),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )

      Spacer(modifier = Modifier.height(12.dp))

      // The reactive voice orb.
      VoiceOrb(
        isListening = uiState.isListening,
        isThinking = uiState.isThinking,
        isSpeaking = uiState.isSpeaking,
      )

      Spacer(modifier = Modifier.height(8.dp))

      // Conversation area.
      Box(modifier = Modifier.fillMaxWidth().weight(1f)) {
        if (uiState.messages.isEmpty()) {
          EmptyState(
            starters = uiState.starters,
            partialTranscript = uiState.partialTranscript,
            onStarter = { viewModel.sendStarter(it, model) },
          )
        } else {
          LazyColumn(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            contentPadding = PaddingValues(vertical = 8.dp),
          ) {
            items(uiState.messages) { message -> ChatBubble(message) }
          }
        }
      }

      // Live partial transcript while listening.
      if (uiState.isListening && uiState.partialTranscript.isNotEmpty()) {
        Text(
          text = uiState.partialTranscript,
          style = MaterialTheme.typography.bodyMedium,
          color = MaterialTheme.colorScheme.primary,
          textAlign = TextAlign.Center,
          modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        )
      }

      if (uiState.error.isNotEmpty()) {
        Text(
          text = uiState.error,
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.error,
          textAlign = TextAlign.Center,
          modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        )
      }

      Spacer(modifier = Modifier.height(12.dp))

      // Big mic / stop control.
      MicButton(
        isListening = uiState.isListening,
        onClick = {
          if (uiState.isListening) {
            viewModel.stopListening()
          } else {
            val granted =
              ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
            if (granted) {
              viewModel.startListening()
            } else {
              micPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
            }
          }
        },
      )

      Spacer(modifier = Modifier.height(20.dp))
    }
  }
}

private fun statusLabel(state: VoiceAssistantUiState): String =
  when {
    state.isListening -> "듣고 있어요…"
    state.isThinking -> "생각 중…"
    state.isSpeaking -> "말하는 중…"
    else -> "마이크를 누르고 말해보세요"
  }

@Composable
private fun VoiceOrb(isListening: Boolean, isThinking: Boolean, isSpeaking: Boolean) {
  val transition = rememberInfiniteTransition(label = "orb")

  // Base pulsing scale; faster + larger when active.
  val active = isListening || isSpeaking || isThinking
  val pulse by
    transition.animateFloat(
      initialValue = 0.92f,
      targetValue = if (active) 1.12f else 1.0f,
      animationSpec =
        infiniteRepeatable(
          animation = tween(durationMillis = if (isListening) 600 else 1400, easing = LinearEasing),
          repeatMode = RepeatMode.Reverse,
        ),
      label = "pulse",
    )

  // Slow rotating glow.
  val angle by
    transition.animateFloat(
      initialValue = 0f,
      targetValue = 360f,
      animationSpec =
        infiniteRepeatable(
          animation = tween(durationMillis = 8000, easing = LinearEasing),
          repeatMode = RepeatMode.Restart,
        ),
      label = "angle",
    )

  val coreColor =
    when {
      isListening -> Color(0xFF34E1C4)
      isThinking -> Color(0xFF9B7BFF)
      isSpeaking -> Color(0xFF4D8DFF)
      else -> Color(0xFF5C6BC0)
    }

  Box(contentAlignment = Alignment.Center, modifier = Modifier.size(200.dp)) {
    // Outer halo.
    Box(
      modifier =
        Modifier.size(200.dp)
          .graphicsLayer {
            scaleX = pulse
            scaleY = pulse
            rotationZ = angle
            alpha = 0.35f
          }
          .clip(CircleShape)
          .background(
            Brush.sweepGradient(
              listOf(
                coreColor.copy(alpha = 0.0f),
                coreColor.copy(alpha = 0.8f),
                coreColor.copy(alpha = 0.0f),
              )
            )
          )
    )
    // Glowing core.
    Box(
      modifier =
        Modifier.size(120.dp)
          .scale(pulse)
          .clip(CircleShape)
          .background(
            Brush.radialGradient(
              colors = listOf(coreColor.copy(alpha = 0.95f), coreColor.copy(alpha = 0.25f)),
            )
          )
    )
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MicButton(isListening: Boolean, onClick: () -> Unit) {
  val container =
    if (isListening) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
  Surface(
    onClick = onClick,
    shape = CircleShape,
    color = container,
    modifier = Modifier.size(72.dp),
  ) {
    Box(contentAlignment = Alignment.Center) {
      Icon(
        imageVector = if (isListening) Icons.Filled.Stop else Icons.Filled.Mic,
        contentDescription = if (isListening) "듣기 중지" else "듣기 시작",
        tint = MaterialTheme.colorScheme.onPrimary,
        modifier = Modifier.size(32.dp),
      )
    }
  }
}

@Composable
private fun EmptyState(
  starters: List<String>,
  partialTranscript: String,
  onStarter: (String) -> Unit,
) {
  Column(
    modifier = Modifier.fillMaxSize().padding(top = 8.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.Top,
  ) {
    Text(
      text = "이렇게 말해보세요…",
      style = MaterialTheme.typography.labelLarge,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(modifier = Modifier.height(10.dp))
    starters.forEach { starter ->
      StarterChip(text = starter, onClick = { onStarter(starter) })
      Spacer(modifier = Modifier.height(8.dp))
    }
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StarterChip(text: String, onClick: () -> Unit) {
  Surface(
    onClick = onClick,
    shape = RoundedCornerShape(20.dp),
    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
    modifier = Modifier.fillMaxWidth(),
  ) {
    Text(
      text = text,
      style = MaterialTheme.typography.bodyMedium,
      color = MaterialTheme.colorScheme.onSurface,
      modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
    )
  }
}

@Composable
private fun ChatBubble(message: ChatMessage) {
  val isUser = message.role == ChatMessage.Role.USER
  val bubbleColor =
    if (isUser) {
      MaterialTheme.colorScheme.primary
    } else {
      MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.85f)
    }
  val textColor =
    if (isUser) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface

  Row(
    modifier = Modifier.fillMaxWidth(),
    horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
  ) {
    Surface(
      shape =
        RoundedCornerShape(
          topStart = 18.dp,
          topEnd = 18.dp,
          bottomStart = if (isUser) 18.dp else 4.dp,
          bottomEnd = if (isUser) 4.dp else 18.dp,
        ),
      color = bubbleColor,
      modifier = Modifier.fillMaxWidth(0.85f).wrapContentWidth(if (isUser) Alignment.End else Alignment.Start),
    ) {
      Text(
        text = message.text.ifEmpty { if (message.isStreaming) "…" else "" },
        style = MaterialTheme.typography.bodyMedium,
        color = textColor,
        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
      )
    }
  }
}
