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
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.Construction
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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
import com.google.ai.edge.gallery.customtasks.agentchat.AgentTools
import com.google.ai.edge.gallery.customtasks.agentchat.AgentToolsActionHost
import com.google.ai.edge.gallery.customtasks.agentchat.McpManagerBottomSheet
import com.google.ai.edge.gallery.customtasks.agentchat.McpManagerViewModel
import com.google.ai.edge.gallery.customtasks.agentchat.SkillManagerBottomSheet
import com.google.ai.edge.gallery.customtasks.agentchat.SkillManagerViewModel
import com.google.ai.edge.gallery.customtasks.speech.KOREAN_TTS_MODEL_NAME
import com.google.ai.edge.gallery.customtasks.speech.MELO_TTS_MODEL_NAME
import com.google.ai.edge.gallery.customtasks.speech.NEURAL_STT_MODEL_NAME
import com.google.ai.edge.gallery.customtasks.speech.WHISPER_KO_STT_MODEL_NAME
import com.google.ai.edge.gallery.data.Task
import com.google.ai.edge.gallery.ui.modelmanager.ModelManagerViewModel

/** The main screen for the Voice Assistant custom task. */
@Composable
fun VoiceAssistantScreen(
  task: Task,
  modelManagerViewModel: ModelManagerViewModel,
  agentTools: AgentTools,
  viewModel: VoiceAssistantViewModel = hiltViewModel(),
  skillManagerViewModel: SkillManagerViewModel = hiltViewModel(),
  mcpManagerViewModel: McpManagerViewModel = hiltViewModel(),
) {
  val modelManagerUiState by modelManagerViewModel.uiState.collectAsState()
  val model = modelManagerUiState.selectedModel
  val uiState by viewModel.uiState.collectAsState()
  val context = LocalContext.current

  // Wire the shared tool surface (skills + MCP) before the model initializes, mirroring AgentChat.
  agentTools.context = context
  agentTools.skillManagerViewModel = skillManagerViewModel
  agentTools.mcpManagerViewModel = mcpManagerViewModel
  agentTools.taskId = task.id
  LaunchedEffect(agentTools) { viewModel.setAgentTools(agentTools) }

  // Track how many MCP tools are connected/enabled so the UI can offer connecting them and so we can
  // re-initialize the model (to enable function calling) once tools become available.
  val mcpUiState by mcpManagerViewModel.uiState.collectAsState()
  val mcpToolCount =
    mcpUiState.mcpServers
      .filter { it.mcpServer.enabled }
      .sumOf { server -> server.mcpServer.toolsList.count { it.enabled } }
  LaunchedEffect(mcpToolCount) { viewModel.setMcpToolCount(mcpToolCount) }

  // Track how many skills are selected (skills + MCP tools both enable function calling).
  val skillUiState by skillManagerViewModel.uiState.collectAsState()
  val skillCount = skillUiState.skills.count { it.skill.selected }
  LaunchedEffect(skillCount) { viewModel.setSkillCount(skillCount) }

  AgentToolsActionHost(
    agentTools = agentTools,
    taskId = task.id,
    skillManagerViewModel = skillManagerViewModel,
    mcpManagerViewModel = mcpManagerViewModel,
    onSkillProgress = { action -> viewModel.onSkillProgressAction(action) },
    onLogMessage = { log -> viewModel.addLogToToolProgressPanel(log) },
    modifier = Modifier.size(0.dp),
  )

  // Keep the ViewModel pointed at the active, initialized model.
  LaunchedEffect(model.name) { viewModel.setActiveModel(model) }

  // The downloadable Korean neural voice (shared with the Text to Speech task) gives higher-quality,
  // device-independent Korean speech than the system engine. Track its download status and feed it
  // to the ViewModel, which drives the whole download → unpack/init → ready pipeline (incl. errors).
  val koreanTtsModel = remember { modelManagerViewModel.getModelByName(KOREAN_TTS_MODEL_NAME) }
  val koreanTtsStatus = koreanTtsModel?.let { modelManagerUiState.modelDownloadStatus[it.name] }

  LaunchedEffect(koreanTtsModel, koreanTtsStatus?.status, koreanTtsStatus?.receivedBytes) {
    viewModel.onKoreanTtsStatus(koreanTtsModel, koreanTtsStatus)
  }

  // The downloadable MeloTTS Korean voice (also shared with the Text to Speech task) offers a very
  // natural Korean voice. Same download → unpack/init → ready pipeline as the KSS voice above.
  val meloTtsModel = remember { modelManagerViewModel.getModelByName(MELO_TTS_MODEL_NAME) }
  val meloTtsStatus = meloTtsModel?.let { modelManagerUiState.modelDownloadStatus[it.name] }

  LaunchedEffect(meloTtsModel, meloTtsStatus?.status, meloTtsStatus?.receivedBytes) {
    viewModel.onMeloTtsStatus(meloTtsModel, meloTtsStatus)
  }

  // The downloadable neural recognizer (SenseVoice, shared with the Speech to Text task) enables
  // fully on-device speech input instead of the system SpeechRecognizer. Same pipeline as TTS.
  val neuralSttModel = remember { modelManagerViewModel.getModelByName(NEURAL_STT_MODEL_NAME) }
  val neuralSttStatus = neuralSttModel?.let { modelManagerUiState.modelDownloadStatus[it.name] }

  LaunchedEffect(neuralSttModel, neuralSttStatus?.status, neuralSttStatus?.receivedBytes) {
    viewModel.onNeuralSttStatus(neuralSttModel, neuralSttStatus)
  }

  // The downloadable Whisper recognizer (small, multilingual; shared with the Speech to Text task)
  // gives high-quality Korean recognition. Same download → ready pipeline as SenseVoice; only one
  // neural recognizer is held in memory at a time (loaded on selection).
  val whisperSttModel = remember { modelManagerViewModel.getModelByName(WHISPER_KO_STT_MODEL_NAME) }
  val whisperSttStatus = whisperSttModel?.let { modelManagerUiState.modelDownloadStatus[it.name] }

  LaunchedEffect(whisperSttModel, whisperSttStatus?.status, whisperSttStatus?.receivedBytes) {
    viewModel.onWhisperSttStatus(whisperSttModel, whisperSttStatus)
  }

  val micPermissionLauncher =
    rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
      if (granted) {
        viewModel.startListening()
      }
    }

  var showMcpSheet by remember { mutableStateOf(false) }
  var showSkillSheet by remember { mutableStateOf(false) }

  // When the set of selected skills / connected MCP tools *changes* (not on first composition),
  // reinitialize the selected model so the system prompt + function-calling tools reflect them.
  var lastCapabilityKey by remember { mutableStateOf(mcpToolCount to skillCount) }
  LaunchedEffect(mcpToolCount, skillCount, model.name) {
    val key = mcpToolCount to skillCount
    if (
      key != lastCapabilityKey &&
        model.name.isNotEmpty() &&
        modelManagerUiState.isModelInitialized(model)
    ) {
      lastCapabilityKey = key
      modelManagerViewModel.initializeModel(
        context = context,
        task = task,
        model = model,
        force = true,
      )
    } else {
      lastCapabilityKey = key
    }
  }

  if (showMcpSheet) {
    McpManagerBottomSheet(
      mcpManagerViewModel = mcpManagerViewModel,
      onDismiss = { showMcpSheet = false },
    )
  }

  if (showSkillSheet) {
    SkillManagerBottomSheet(
      agentTools = agentTools,
      skillManagerViewModel = skillManagerViewModel,
      onDismiss = { showSkillSheet = false },
    )
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

      // Korean neural voice status: download → unpack/init → ready, with progress and error recovery.
      if (koreanTtsModel != null && uiState.neuralVoice.stage != NeuralVoiceStage.READY) {
        Spacer(modifier = Modifier.height(10.dp))
        KoreanVoiceBanner(
          state = uiState.neuralVoice,
          onDownload = { modelManagerViewModel.downloadModel(task = null, model = koreanTtsModel) },
          onRetryPrepare = { viewModel.retryNeuralPreparation() },
        )
      }

      // MeloTTS Korean voice status (same lifecycle). Only shown once the model is actually
      // downloadable — the Korean MeloTTS archive URL is a TODO (see TtsTask), so until it is set
      // the model has an empty URL and we hide the banner to avoid a dead "받기" button.
      if (
        meloTtsModel != null &&
          meloTtsModel.url.isNotEmpty() &&
          uiState.meloVoice.stage != NeuralVoiceStage.READY
      ) {
        Spacer(modifier = Modifier.height(10.dp))
        MeloVoiceBanner(
          state = uiState.meloVoice,
          onDownload = { modelManagerViewModel.downloadModel(task = null, model = meloTtsModel) },
          onRetryPrepare = { viewModel.retryMeloPreparation() },
        )
      }

      Spacer(modifier = Modifier.height(12.dp))

      // The reactive voice orb.
      VoiceOrb(
        isListening = uiState.isListening,
        isThinking = uiState.isThinking,
        isSpeaking = uiState.isSpeaking,
      )

      // Voice picker (shown when more than one voice is available).
      if (uiState.voices.size > 1) {
        Spacer(modifier = Modifier.height(8.dp))
        VoicePickerRow(
          voices = uiState.voices,
          selectedId = uiState.selectedVoiceId,
          onSelect = { viewModel.selectVoice(it) },
        )
      }

      // Speak-mode picker: speak after the full reply (default) vs. stream sentence-by-sentence.
      if (uiState.ttsReady) {
        Spacer(modifier = Modifier.height(8.dp))
        SpeakModePickerRow(
          selected = uiState.speakMode,
          onSelect = { viewModel.setSpeakMode(it) },
        )
      }

      // STT engine picker — shown once at least one neural recognizer is available. Lists the
      // system engine plus whichever neural recognizers have been downloaded.
      val senseVoiceReady = uiState.neuralStt.stage == NeuralVoiceStage.READY
      val whisperReady = uiState.whisperStt.stage == NeuralVoiceStage.READY
      if (senseVoiceReady || whisperReady) {
        Spacer(modifier = Modifier.height(8.dp))
        SttEnginePickerRow(
          selected = uiState.sttEngine,
          senseVoiceReady = senseVoiceReady,
          whisperReady = whisperReady,
          onSelect = { viewModel.selectSttEngine(it) },
        )
      }

      // SenseVoice recognizer status: download → ready, with progress and error recovery.
      if (neuralSttModel != null && !senseVoiceReady) {
        Spacer(modifier = Modifier.height(10.dp))
        NeuralSttBanner(
          state = uiState.neuralStt,
          onDownload = { modelManagerViewModel.downloadModel(task = null, model = neuralSttModel) },
          onRetryPrepare = { viewModel.retryNeuralSttPreparation() },
        )
      }

      // Whisper (Korean) recognizer status: same lifecycle.
      if (whisperSttModel != null && !whisperReady) {
        Spacer(modifier = Modifier.height(10.dp))
        WhisperSttBanner(
          state = uiState.whisperStt,
          onDownload = { modelManagerViewModel.downloadModel(task = null, model = whisperSttModel) },
          onRetryPrepare = { viewModel.retryWhisperSttPreparation() },
        )
      }

      // Skills / Tools / MCP: show how many skills + tools are available and let the user manage
      // them. Changing them reinitializes the model so function calling reflects the new capabilities.
      Spacer(modifier = Modifier.height(8.dp))
      ToolsBanner(
        toolCount = uiState.mcpToolCount,
        skillCount = uiState.skillCount,
        toolActivity = uiState.toolActivity,
        onManageTools = { showMcpSheet = true },
        onManageSkills = { showSkillSheet = true },
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

/** A horizontally scrollable row of selectable voice chips. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun VoicePickerRow(
  voices: List<VoiceOption>,
  selectedId: String,
  onSelect: (String) -> Unit,
) {
  Row(
    modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
    horizontalArrangement = Arrangement.spacedBy(8.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    voices.forEach { voice ->
      val selected = voice.id == selectedId
      val container =
        if (selected) MaterialTheme.colorScheme.primary
        else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f)
      val content =
        if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
      Surface(
        onClick = { onSelect(voice.id) },
        shape = RoundedCornerShape(20.dp),
        color = container,
      ) {
        Row(
          verticalAlignment = Alignment.CenterVertically,
          modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
        ) {
          if (voice.isNeural) {
            Icon(
              imageVector = Icons.Filled.AutoAwesome,
              contentDescription = null,
              tint = content,
              modifier = Modifier.size(16.dp),
            )
            Spacer(modifier = Modifier.width(6.dp))
          }
          Text(text = voice.label, style = MaterialTheme.typography.labelLarge, color = content)
        }
      }
    }
  }
}

/**
 * A chip row for choosing when the assistant speaks: after the full reply (default) or streamed
 * sentence-by-sentence as it is generated (lower latency to first audio).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SpeakModePickerRow(selected: TtsSpeakMode, onSelect: (TtsSpeakMode) -> Unit) {
  Row(
    modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
    horizontalArrangement = Arrangement.spacedBy(8.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(
      text = "발화:",
      style = MaterialTheme.typography.labelMedium,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    SttEngineChip("전체 발화", selected == TtsSpeakMode.AFTER_COMPLETE) {
      onSelect(TtsSpeakMode.AFTER_COMPLETE)
    }
    SttEngineChip("실시간 발화", selected == TtsSpeakMode.STREAMING) {
      onSelect(TtsSpeakMode.STREAMING)
    }
  }
}

/**
 * A chip row for choosing the speech-recognition (input) engine. Always offers the system engine,
 * and adds a chip for each downloaded neural recognizer (SenseVoice / Whisper).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SttEnginePickerRow(
  selected: SttEngine,
  senseVoiceReady: Boolean,
  whisperReady: Boolean,
  onSelect: (SttEngine) -> Unit,
) {
  Row(
    modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
    horizontalArrangement = Arrangement.spacedBy(8.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(
      text = "인식:",
      style = MaterialTheme.typography.labelMedium,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    SttEngineChip("시스템", selected == SttEngine.SYSTEM) { onSelect(SttEngine.SYSTEM) }
    if (senseVoiceReady) {
      SttEngineChip("SenseVoice", selected == SttEngine.NEURAL) { onSelect(SttEngine.NEURAL) }
    }
    if (whisperReady) {
      SttEngineChip("Whisper", selected == SttEngine.WHISPER) { onSelect(SttEngine.WHISPER) }
    }
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SttEngineChip(label: String, selected: Boolean, onClick: () -> Unit) {
  val container =
    if (selected) MaterialTheme.colorScheme.primary
    else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f)
  val content =
    if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
  Surface(onClick = onClick, shape = RoundedCornerShape(20.dp), color = container) {
    Text(
      text = label,
      style = MaterialTheme.typography.labelLarge,
      color = content,
      modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
    )
  }
}

/** Download/preparation banner for the neural recognizer (mirrors [KoreanVoiceBanner]). */
@Composable
private fun NeuralSttBanner(
  state: NeuralSttState,
  onDownload: () -> Unit,
  onRetryPrepare: () -> Unit,
) {
  Surface(
    shape = RoundedCornerShape(14.dp),
    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
    modifier = Modifier.fillMaxWidth(),
  ) {
    Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
          imageVector = Icons.Filled.AutoAwesome,
          contentDescription = null,
          tint = MaterialTheme.colorScheme.primary,
          modifier = Modifier.size(18.dp),
        )
        Spacer(modifier = Modifier.width(8.dp))
        Column(modifier = Modifier.weight(1f)) {
          Text(
            text = "오프라인 음성 인식",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
          )
          Text(
            text = neuralSttSubtitle(state),
            style = MaterialTheme.typography.bodySmall,
            color =
              if (state.stage == NeuralVoiceStage.ERROR) MaterialTheme.colorScheme.error
              else MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
        Spacer(modifier = Modifier.width(12.dp))
        when (state.stage) {
          NeuralVoiceStage.NOT_INSTALLED -> Button(onClick = onDownload) { Text("받기") }
          NeuralVoiceStage.DOWNLOADING,
          NeuralVoiceStage.PREPARING ->
            CircularProgressIndicator(
              modifier = Modifier.size(22.dp),
              strokeWidth = 2.dp,
              color = MaterialTheme.colorScheme.primary,
            )
          NeuralVoiceStage.ERROR -> Button(onClick = onRetryPrepare) { Text("재시도") }
          NeuralVoiceStage.READY -> {}
        }
      }
      if (state.stage == NeuralVoiceStage.DOWNLOADING) {
        Spacer(modifier = Modifier.height(8.dp))
        if (state.downloadPercent in 0..100) {
          LinearProgressIndicator(
            progress = { state.downloadPercent / 100f },
            modifier = Modifier.fillMaxWidth(),
          )
        } else {
          LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
      } else if (state.stage == NeuralVoiceStage.PREPARING) {
        Spacer(modifier = Modifier.height(8.dp))
        LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
      }
    }
  }
}

private fun neuralSttSubtitle(state: NeuralSttState): String =
  when (state.stage) {
    NeuralVoiceStage.NOT_INSTALLED -> "인터넷 없이 기기에서 음성을 인식합니다 (약 239MB)."
    NeuralVoiceStage.DOWNLOADING -> {
      val pct = if (state.downloadPercent in 0..100) "${state.downloadPercent}%" else ""
      val speed = if (state.bytesPerSecond > 0) " · ${formatSpeed(state.bytesPerSecond)}" else ""
      val eta = if (state.remainingMs > 0) " · ${formatEta(state.remainingMs)} 남음" else ""
      "다운로드 중 $pct$speed$eta".trim()
    }
    NeuralVoiceStage.PREPARING -> "음성 인식 모델 초기화 중…"
    NeuralVoiceStage.ERROR -> state.error.ifEmpty { "오류가 발생했습니다." }
    NeuralVoiceStage.READY -> "사용 준비 완료"
  }

/** Download/preparation banner for the Whisper Korean recognizer (mirrors [NeuralSttBanner]). */
@Composable
private fun WhisperSttBanner(
  state: NeuralSttState,
  onDownload: () -> Unit,
  onRetryPrepare: () -> Unit,
) {
  Surface(
    shape = RoundedCornerShape(14.dp),
    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
    modifier = Modifier.fillMaxWidth(),
  ) {
    Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
          imageVector = Icons.Filled.AutoAwesome,
          contentDescription = null,
          tint = MaterialTheme.colorScheme.primary,
          modifier = Modifier.size(18.dp),
        )
        Spacer(modifier = Modifier.width(8.dp))
        Column(modifier = Modifier.weight(1f)) {
          Text(
            text = "Whisper 한국어 음성 인식",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
          )
          Text(
            text = whisperSttSubtitle(state),
            style = MaterialTheme.typography.bodySmall,
            color =
              if (state.stage == NeuralVoiceStage.ERROR) MaterialTheme.colorScheme.error
              else MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
        Spacer(modifier = Modifier.width(12.dp))
        when (state.stage) {
          NeuralVoiceStage.NOT_INSTALLED -> Button(onClick = onDownload) { Text("받기") }
          NeuralVoiceStage.DOWNLOADING,
          NeuralVoiceStage.PREPARING ->
            CircularProgressIndicator(
              modifier = Modifier.size(22.dp),
              strokeWidth = 2.dp,
              color = MaterialTheme.colorScheme.primary,
            )
          NeuralVoiceStage.ERROR -> Button(onClick = onRetryPrepare) { Text("재시도") }
          NeuralVoiceStage.READY -> {}
        }
      }
      if (state.stage == NeuralVoiceStage.DOWNLOADING) {
        Spacer(modifier = Modifier.height(8.dp))
        if (state.downloadPercent in 0..100) {
          LinearProgressIndicator(
            progress = { state.downloadPercent / 100f },
            modifier = Modifier.fillMaxWidth(),
          )
        } else {
          LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
      } else if (state.stage == NeuralVoiceStage.PREPARING) {
        Spacer(modifier = Modifier.height(8.dp))
        LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
      }
    }
  }
}

private fun whisperSttSubtitle(state: NeuralSttState): String =
  when (state.stage) {
    NeuralVoiceStage.NOT_INSTALLED -> "더 정확한 한국어 인식을 위한 Whisper 모델 (약 374MB)."
    NeuralVoiceStage.DOWNLOADING -> {
      val pct = if (state.downloadPercent in 0..100) "${state.downloadPercent}%" else ""
      val speed = if (state.bytesPerSecond > 0) " · ${formatSpeed(state.bytesPerSecond)}" else ""
      val eta = if (state.remainingMs > 0) " · ${formatEta(state.remainingMs)} 남음" else ""
      "다운로드 중 $pct$speed$eta".trim()
    }
    NeuralVoiceStage.PREPARING -> "음성 인식 모델 초기화 중…"
    NeuralVoiceStage.ERROR -> state.error.ifEmpty { "오류가 발생했습니다." }
    NeuralVoiceStage.READY -> "사용 준비 완료"
  }

/**
 * Banner advertising skill + tool/MCP availability. Shows how many skills and MCP tools are
 * available (or invites the user to add them), reflects any in-progress tool/skill call, and offers
 * two manage actions (skills, MCP).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ToolsBanner(
  toolCount: Int,
  skillCount: Int,
  toolActivity: String,
  onManageTools: () -> Unit,
  onManageSkills: () -> Unit,
) {
  Surface(
    shape = RoundedCornerShape(14.dp),
    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
    modifier = Modifier.fillMaxWidth(),
  ) {
    Row(
      verticalAlignment = Alignment.CenterVertically,
      modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
      Icon(
        imageVector = Icons.Outlined.Construction,
        contentDescription = null,
        tint = MaterialTheme.colorScheme.primary,
        modifier = Modifier.size(18.dp),
      )
      Spacer(modifier = Modifier.width(8.dp))
      Column(modifier = Modifier.weight(1f)) {
        Text(
          text = "스킬 · 도구",
          style = MaterialTheme.typography.bodyMedium,
          fontWeight = FontWeight.SemiBold,
          color = MaterialTheme.colorScheme.onSurface,
        )
        val subtitle =
          when {
            toolActivity.isNotEmpty() -> toolActivity
            skillCount > 0 || toolCount > 0 -> "스킬 ${skillCount}개 · 도구 ${toolCount}개 사용 가능"
            else -> "스킬을 켜거나 MCP 서버를 연결해 기능을 추가하세요"
          }
        Text(
          text = subtitle,
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
      Spacer(modifier = Modifier.width(8.dp))
      if (toolActivity.isNotEmpty()) {
        CircularProgressIndicator(
          modifier = Modifier.size(20.dp),
          strokeWidth = 2.dp,
          color = MaterialTheme.colorScheme.primary,
        )
      } else {
        TextButton(onClick = onManageSkills) { Text("스킬") }
        TextButton(onClick = onManageTools) { Text("MCP") }
      }
    }
  }
}

/**
 * A banner that surfaces the full lifecycle of the high-quality Korean neural voice:
 * download (with a real progress bar, speed and ETA), unpack/initialize (spinner), and errors with
 * a recovery action. Hidden by the caller once the voice is READY.
 */
@Composable
private fun KoreanVoiceBanner(
  state: NeuralVoiceState,
  onDownload: () -> Unit,
  onRetryPrepare: () -> Unit,
) {
  Surface(
    shape = RoundedCornerShape(14.dp),
    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
    modifier = Modifier.fillMaxWidth(),
  ) {
    Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
          imageVector = Icons.Filled.AutoAwesome,
          contentDescription = null,
          tint = MaterialTheme.colorScheme.primary,
          modifier = Modifier.size(18.dp),
        )
        Spacer(modifier = Modifier.width(8.dp))
        Column(modifier = Modifier.weight(1f)) {
          Text(
            text = "고품질 한국어 음성",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
          )
          Text(
            text = neuralVoiceSubtitle(state),
            style = MaterialTheme.typography.bodySmall,
            color =
              if (state.stage == NeuralVoiceStage.ERROR) MaterialTheme.colorScheme.error
              else MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
        Spacer(modifier = Modifier.width(12.dp))
        when (state.stage) {
          NeuralVoiceStage.NOT_INSTALLED -> Button(onClick = onDownload) { Text("받기") }
          NeuralVoiceStage.DOWNLOADING ->
            CircularProgressIndicator(
              modifier = Modifier.size(22.dp),
              strokeWidth = 2.dp,
              color = MaterialTheme.colorScheme.primary,
            )
          NeuralVoiceStage.PREPARING ->
            CircularProgressIndicator(
              modifier = Modifier.size(22.dp),
              strokeWidth = 2.dp,
              color = MaterialTheme.colorScheme.primary,
            )
          NeuralVoiceStage.ERROR -> Button(onClick = onRetryPrepare) { Text("재시도") }
          NeuralVoiceStage.READY -> {}
        }
      }

      // A determinate progress bar while downloading (falls back to indeterminate if size unknown).
      if (state.stage == NeuralVoiceStage.DOWNLOADING) {
        Spacer(modifier = Modifier.height(8.dp))
        if (state.downloadPercent in 0..100) {
          LinearProgressIndicator(
            progress = { state.downloadPercent / 100f },
            modifier = Modifier.fillMaxWidth(),
          )
        } else {
          LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
      } else if (state.stage == NeuralVoiceStage.PREPARING) {
        Spacer(modifier = Modifier.height(8.dp))
        if (state.unpackPercent in 0..100) {
          LinearProgressIndicator(
            progress = { state.unpackPercent / 100f },
            modifier = Modifier.fillMaxWidth(),
          )
        } else {
          LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
      }
    }
  }
}

/**
 * Download/preparation banner for the MeloTTS Korean voice. Mirrors [KoreanVoiceBanner] but with
 * MeloTTS-specific copy. Hidden by the caller once the voice is READY.
 */
@Composable
private fun MeloVoiceBanner(
  state: NeuralVoiceState,
  onDownload: () -> Unit,
  onRetryPrepare: () -> Unit,
) {
  Surface(
    shape = RoundedCornerShape(14.dp),
    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
    modifier = Modifier.fillMaxWidth(),
  ) {
    Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
          imageVector = Icons.Filled.AutoAwesome,
          contentDescription = null,
          tint = MaterialTheme.colorScheme.primary,
          modifier = Modifier.size(18.dp),
        )
        Spacer(modifier = Modifier.width(8.dp))
        Column(modifier = Modifier.weight(1f)) {
          Text(
            text = "MeloTTS 한국어 음성",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
          )
          Text(
            text = meloVoiceSubtitle(state),
            style = MaterialTheme.typography.bodySmall,
            color =
              if (state.stage == NeuralVoiceStage.ERROR) MaterialTheme.colorScheme.error
              else MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
        Spacer(modifier = Modifier.width(12.dp))
        when (state.stage) {
          NeuralVoiceStage.NOT_INSTALLED -> Button(onClick = onDownload) { Text("받기") }
          NeuralVoiceStage.DOWNLOADING,
          NeuralVoiceStage.PREPARING ->
            CircularProgressIndicator(
              modifier = Modifier.size(22.dp),
              strokeWidth = 2.dp,
              color = MaterialTheme.colorScheme.primary,
            )
          NeuralVoiceStage.ERROR -> Button(onClick = onRetryPrepare) { Text("재시도") }
          NeuralVoiceStage.READY -> {}
        }
      }

      if (state.stage == NeuralVoiceStage.DOWNLOADING) {
        Spacer(modifier = Modifier.height(8.dp))
        if (state.downloadPercent in 0..100) {
          LinearProgressIndicator(
            progress = { state.downloadPercent / 100f },
            modifier = Modifier.fillMaxWidth(),
          )
        } else {
          LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
      } else if (state.stage == NeuralVoiceStage.PREPARING) {
        Spacer(modifier = Modifier.height(8.dp))
        if (state.unpackPercent in 0..100) {
          LinearProgressIndicator(
            progress = { state.unpackPercent / 100f },
            modifier = Modifier.fillMaxWidth(),
          )
        } else {
          LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
      }
    }
  }
}

/** Builds the subtitle describing the current MeloTTS voice stage. */
private fun meloVoiceSubtitle(state: NeuralVoiceState): String =
  when (state.stage) {
    NeuralVoiceStage.NOT_INSTALLED -> "MeloTTS의 자연스러운 한국어 음성을 받아보세요."
    NeuralVoiceStage.DOWNLOADING -> {
      val pct = if (state.downloadPercent in 0..100) "${state.downloadPercent}%" else ""
      val speed = if (state.bytesPerSecond > 0) " · ${formatSpeed(state.bytesPerSecond)}" else ""
      val eta = if (state.remainingMs > 0) " · ${formatEta(state.remainingMs)} 남음" else ""
      "다운로드 중 $pct$speed$eta".trim()
    }
    NeuralVoiceStage.PREPARING -> {
      if (state.unpackPercent in 0..100) "압축 해제 중… ${state.unpackPercent}%"
      else "음성 데이터 준비 중… (압축 해제 및 초기화)"
    }
    NeuralVoiceStage.ERROR -> state.error.ifEmpty { "오류가 발생했습니다." }
    NeuralVoiceStage.READY -> "사용 준비 완료"
  }

/** Builds the human-readable subtitle describing the current neural-voice stage. */
private fun neuralVoiceSubtitle(state: NeuralVoiceState): String =
  when (state.stage) {
    NeuralVoiceStage.NOT_INSTALLED -> "더 자연스러운 음성으로 들으려면 받아보세요 (약 64MB)."
    NeuralVoiceStage.DOWNLOADING -> {
      val pct = if (state.downloadPercent in 0..100) "${state.downloadPercent}%" else ""
      val speed = if (state.bytesPerSecond > 0) " · ${formatSpeed(state.bytesPerSecond)}" else ""
      val eta = if (state.remainingMs > 0) " · ${formatEta(state.remainingMs)} 남음" else ""
      "다운로드 중 $pct$speed$eta".trim()
    }
    NeuralVoiceStage.PREPARING -> {
      if (state.unpackPercent in 0..100) "압축 해제 중… ${state.unpackPercent}%"
      else "음성 데이터 준비 중… (압축 해제 및 초기화)"
    }
    NeuralVoiceStage.ERROR -> state.error.ifEmpty { "오류가 발생했습니다." }
    NeuralVoiceStage.READY -> "사용 준비 완료"
  }

private fun formatSpeed(bytesPerSecond: Long): String {
  val mb = bytesPerSecond / 1_000_000.0
  if (mb >= 1.0) return String.format("%.1f MB/s", mb)
  val kb = bytesPerSecond / 1_000.0
  return String.format("%.0f KB/s", kb)
}

private fun formatEta(remainingMs: Long): String {
  val totalSec = (remainingMs / 1000).toInt()
  val min = totalSec / 60
  val sec = totalSec % 60
  return if (min > 0) "${min}분 ${sec}초" else "${sec}초"
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
