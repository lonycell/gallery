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

package com.google.ai.edge.gallery.ui.mainpage

import android.Manifest
import android.content.pm.PackageManager
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.outlined.DeleteSweep
import androidx.compose.material.icons.rounded.CallEnd
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.RestartAlt
import androidx.compose.material.icons.rounded.People
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.google.ai.edge.gallery.R
import com.google.ai.edge.gallery.character.CharacterViewModel
import com.google.ai.edge.gallery.common.PermissionResult
import com.google.ai.edge.gallery.customtasks.agentchat.McpToolCallPermissionDialog
import com.google.ai.edge.gallery.customtasks.agentchat.McpManagerViewModel
import com.google.ai.edge.gallery.customtasks.agentchat.SkillManagerViewModel
import com.google.ai.edge.gallery.customtasks.voiceassistant.ChatInputMode
import com.google.ai.edge.gallery.customtasks.voiceassistant.ChatMessage
import com.google.ai.edge.gallery.customtasks.voiceassistant.EmotionCue
import com.google.ai.edge.gallery.customtasks.voiceassistant.VOICE_ASSISTANT_TASK_ID
import com.google.ai.edge.gallery.customtasks.voiceassistant.VoiceAssistantTask
import com.google.ai.edge.gallery.customtasks.voiceassistant.VoiceAssistantUiState
import com.google.ai.edge.gallery.customtasks.voiceassistant.VoiceAssistantViewModel
import com.google.ai.edge.gallery.data.ModelDownloadStatusType
import com.google.ai.edge.gallery.ui.common.MarkdownText
import kotlinx.coroutines.delay

// Shared palette with the subscription paywall for a consistent, futuristic look.
private val ScrimBase = Color(0xFF140A2B)
private val AccentPurple = Color(0xFF7C4DFF)
private val AccentPink = Color(0xFFE15BD0)
private val ListeningColor = Color(0xFF34E1C4)
private val ThinkingColor = Color(0xFF9B7BFF)
private val SpeakingColor = Color(0xFF4D8DFF)

/**
 * Fades the top edge of a (scrolling) composable to transparent, so content scrolling up appears to
 * dissolve away. Uses an offscreen layer (`alpha < 1`) + a `DstIn` vertical gradient mask.
 */
private fun Modifier.topFade(fadeFraction: Float = 0.16f): Modifier =
  this.graphicsLayer { alpha = 0.99f }
    .drawWithContent {
      drawContent()
      drawRect(
        brush =
          Brush.verticalGradient(
            0f to Color.Transparent,
            1f to Color.Black,
            startY = 0f,
            endY = size.height * fadeFraction,
          ),
        blendMode = BlendMode.DstIn,
      )
    }

/**
 * The app's main screen: a futuristic voice-call style chat with the persona on the hero image.
 *
 * The user talks to (and texts with) the persona. Speech recognition, the on-device LLM and
 * text-to-speech are all reused from the Voice Assistant ([VoiceAssistantViewModel]); this screen
 * only owns the presentation. Choosing/downloading the LLM, STT and TTS models, plus tools, skills
 * and the subscription, all live in [VoiceChatSettingsScreen], reached via the gear in the top-right
 * corner — so this screen stays focused on the conversation and never nags the user to pick a model.
 *
 * The "listening" orb animation and the microphone control from the original Voice Assistant are
 * merged into a single animated mic-orb at the bottom-right of the input bar.
 */
@Composable
fun MainPage(
  modelManagerViewModel: com.google.ai.edge.gallery.ui.modelmanager.ModelManagerViewModel,
  viewModel: VoiceAssistantViewModel,
  skillManagerViewModel: SkillManagerViewModel,
  mcpManagerViewModel: McpManagerViewModel,
  characterViewModel: CharacterViewModel,
  onOpenSettings: () -> Unit,
  onOpenCharacters: () -> Unit,
  modifier: Modifier = Modifier,
) {
  // The selected companion drives the background image, avatar and (via the prompt source) persona.
  val charState by characterViewModel.state.collectAsState()
  val selectedCharacter =
    remember(charState.selectedId) {
      characterViewModel.characterById(charState.selectedId)
        ?: characterViewModel.characters.first()
    }

  // Resolve the Voice Assistant task + its shared tool surface.
  val voiceTask = modelManagerViewModel.getTaskById(VOICE_ASSISTANT_TASK_ID)
  val voiceCustomTask =
    modelManagerViewModel.getCustomTaskByTaskId(VOICE_ASSISTANT_TASK_ID) as? VoiceAssistantTask

  if (voiceTask == null || voiceCustomTask == null) {
    // Tasks not loaded yet — show the character hero (same framing as the chat) while we wait.
    Box(modifier = modifier.fillMaxSize().background(ScrimBase)) {
      Image(
        painter = painterResource(selectedCharacter.imageRes),
        contentDescription = null,
        contentScale = ContentScale.Crop,
        alignment = Alignment.TopCenter,
        modifier = Modifier.fillMaxSize(),
      )
    }
    return
  }

  // Delegate to a child composable so every hook (activity-result launcher, effects) is registered
  // consistently once the task is available — never conditionally after an early return, which broke
  // the microphone permission launcher and led to a recording security error.
  VoiceChatContent(
    voiceTask = voiceTask,
    voiceCustomTask = voiceCustomTask,
    selectedCharacter = selectedCharacter,
    modelManagerViewModel = modelManagerViewModel,
    viewModel = viewModel,
    skillManagerViewModel = skillManagerViewModel,
    mcpManagerViewModel = mcpManagerViewModel,
    characterViewModel = characterViewModel,
    onOpenSettings = onOpenSettings,
    onOpenCharacters = onOpenCharacters,
    modifier = modifier,
  )
}

@Composable
private fun VoiceChatContent(
  voiceTask: com.google.ai.edge.gallery.data.Task,
  voiceCustomTask: VoiceAssistantTask,
  selectedCharacter: com.google.ai.edge.gallery.character.Character,
  modelManagerViewModel: com.google.ai.edge.gallery.ui.modelmanager.ModelManagerViewModel,
  viewModel: VoiceAssistantViewModel,
  skillManagerViewModel: SkillManagerViewModel,
  mcpManagerViewModel: McpManagerViewModel,
  characterViewModel: CharacterViewModel,
  onOpenSettings: () -> Unit,
  onOpenCharacters: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val context = LocalContext.current
  val modelManagerUiState by modelManagerViewModel.uiState.collectAsState()
  val uiState by viewModel.uiState.collectAsState()
  val charState by characterViewModel.state.collectAsState()

  // Keep the shared ViewModel + engines wired regardless of which screen is visible.
  VoiceChatPlumbing(
    task = voiceTask,
    modelManagerViewModel = modelManagerViewModel,
    viewModel = viewModel,
    skillManagerViewModel = skillManagerViewModel,
    mcpManagerViewModel = mcpManagerViewModel,
    agentTools = voiceCustomTask.agentTools,
  )

  // Pick the model to chat with: prefer the currently-selected model if it is one of this task's
  // (downloaded) LLMs, otherwise the first downloaded LLM. Selection + download happens in settings.
  val selectedModel = modelManagerUiState.selectedModel
  val targetModel =
    remember(
      voiceTask.models.map { it.name },
      modelManagerUiState.modelDownloadStatus,
      selectedModel.name,
    ) {
      fun downloaded(name: String) =
        modelManagerUiState.modelDownloadStatus[name]?.status ==
          ModelDownloadStatusType.SUCCEEDED
      when {
        selectedModel.name.isNotEmpty() &&
          voiceTask.models.any { it.name == selectedModel.name } &&
          downloaded(selectedModel.name) -> selectedModel
        else -> voiceTask.models.firstOrNull { downloaded(it.name) }
      }
    }

  // Select + initialize the chosen model while the chat is visible. Re-initialized (force) only when
  // the model or the selected character (persona) actually changed — so it doesn't needlessly
  // reload (slow) on every return from settings when nothing relevant changed.
  LaunchedEffect(targetModel?.name, charState.selectedId) {
    val m = targetModel ?: return@LaunchedEffect
    if (selectedModel.name != m.name) {
      modelManagerViewModel.selectModel(m)
    }
    val signatureChanged = characterViewModel.needsModelInit("${m.name}|${charState.selectedId}")
    if (signatureChanged || !modelManagerUiState.isModelInitialized(m)) {
      modelManagerViewModel.initializeModel(
        context = context,
        task = voiceTask,
        model = m,
        force = true,
      )
    }
  }

  // Show this character's own conversation (per-character chat history); switching characters never
  // leaves the previous character's messages on screen.
  LaunchedEffect(charState.selectedId) { viewModel.setConversation(charState.selectedId) }

  // Apply the selected character's assigned TTS voice (engine + voice) to the shared engine, so the
  // chat speaks in that character's voice. Re-applied when voices become available (e.g. a neural
  // voice finishes downloading).
  val assignedVoice = charState.voiceByCharacter[charState.selectedId] ?: ""
  // Voice priority: the character's own voice → the global default voice → the first available voice
  // (neural-preferred). This way a character without its own voice uses the global default.
  val effectiveVoice = assignedVoice.ifEmpty { charState.defaultVoiceId }
  LaunchedEffect(charState.selectedId, effectiveVoice, uiState.voices.size) {
    val target = effectiveVoice.ifEmpty { uiState.voices.firstOrNull()?.id ?: "" }
    if (target.isNotEmpty()) {
      viewModel.selectVoice(target)
    }
  }

  // Reinitialize when the available skills/MCP tools change so function calling reflects them.
  var lastCapabilityKey by remember { mutableStateOf(uiState.mcpToolCount to uiState.skillCount) }
  LaunchedEffect(uiState.mcpToolCount, uiState.skillCount, selectedModel.name) {
    val key = uiState.mcpToolCount to uiState.skillCount
    if (
      key != lastCapabilityKey &&
        selectedModel.name.isNotEmpty() &&
        modelManagerUiState.isModelInitialized(selectedModel)
    ) {
      lastCapabilityKey = key
      modelManagerViewModel.initializeModel(
        context = context,
        task = voiceTask,
        model = selectedModel,
        force = true,
      )
    } else {
      lastCapabilityKey = key
    }
  }

  val modelReady =
    selectedModel.name.isNotEmpty() && modelManagerUiState.isModelInitialized(selectedModel)
  // A model has already been downloaded and is just being loaded/initialized (this can take a while
  // for an LLM) — distinct from "no model downloaded yet, go to settings".
  val modelDownloaded = targetModel != null

  // When entering the chat from the character's "start chat" button, have the character greet first —
  // but only once the model is ready (no greeting while it still needs downloading/preparing).
  LaunchedEffect(modelReady, charState.selectedId) {
    if (modelReady && characterViewModel.isGreetingPending(charState.selectedId)) {
      delay(250) // let this character's saved history (if any) finish loading first
      characterViewModel.clearGreeting()
      if (uiState.messages.isEmpty()) {
        targetModel?.let { viewModel.greet(it) }
      }
    }
  }

  // Pending MCP tool-call permission dialog (tools run during the chat).
  val mcpPermission by viewModel.mcpPermissionRequest.collectAsState()
  mcpPermission?.let { action ->
    McpToolCallPermissionDialog(
      toolName = action.toolName,
      argument = action.argument,
      onResult = { result ->
        if (result == PermissionResult.ALWAYS_ALLOW) {
          mcpManagerViewModel.uiState.value.mcpServers
            .find { s -> s.mcpServer.toolsList.any { it.name == action.toolName } }
            ?.mcpServer
            ?.url
            ?.let { url ->
              mcpManagerViewModel.setMcpToolAlwaysAllow(
                url = url,
                toolName = action.toolName,
                alwaysAllow = true,
              )
            }
        }
        viewModel.resolveMcpPermission(result)
      },
    )
  }

  // Microphone handling mirrors the original Voice Assistant screen exactly: request the permission
  // only on the first mic tap, then start listening.
  val micPermissionLauncher =
    rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
      if (granted) viewModel.startListening()
    }

  val toggleMic: () -> Unit = {
    if (uiState.isListening) {
      viewModel.stopListening()
    } else {
      val granted =
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
          PackageManager.PERMISSION_GRANTED
      if (granted) viewModel.startListening()
      else micPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
    }
  }

  // Entering hands-free call mode needs the mic permission up front (the mic stays open).
  val callPermissionLauncher =
    rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
      if (granted) viewModel.setInputMode(ChatInputMode.CALL)
    }
  val enterCallMode: () -> Unit = {
    if (modelReady) {
      val granted =
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
          PackageManager.PERMISSION_GRANTED
      if (granted) viewModel.setInputMode(ChatInputMode.CALL)
      else callPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
    }
  }

  // Latest emotion cue (emoji in a reply) to animate as a floating effect.
  var emotionCue by remember { mutableStateOf<EmotionCue?>(null) }
  LaunchedEffect(Unit) { viewModel.emotionCues.collect { emotionCue = it } }

  Box(modifier = modifier.fillMaxSize().background(ScrimBase)) {
    // Hero: the selected character, full-bleed like the subscription page (portrait photos), with a
    // gradient that's light over the face and fades smoothly into the dark chat area below.
    Image(
      painter = painterResource(selectedCharacter.imageRes),
      contentDescription = selectedCharacter.name,
      contentScale = ContentScale.Crop,
      alignment = Alignment.TopCenter,
      modifier = Modifier.fillMaxSize(),
    )
    Box(
      modifier =
        Modifier.fillMaxSize()
          .background(
            Brush.verticalGradient(
              0.0f to ScrimBase.copy(alpha = 0.20f),
              0.42f to ScrimBase.copy(alpha = 0.60f),
              0.70f to ScrimBase.copy(alpha = 0.95f),
              1.0f to ScrimBase,
            )
          )
    )

    Column(modifier = Modifier.fillMaxSize().systemBarsPadding().imePadding()) {
      // Top bar: character name + status, character picker, settings gear.
      Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Column(modifier = Modifier.weight(1f)) {
          Text(
            text = selectedCharacter.name,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = 20.sp,
          )
          Text(
            text = statusLabel(uiState, modelReady, modelDownloaded),
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 12.sp,
          )
        }
        FrostedCircleButton(onClick = onOpenCharacters) {
          Icon(
            Icons.Rounded.People,
            contentDescription = "캐릭터 선택",
            tint = Color.White,
            modifier = Modifier.size(22.dp),
          )
        }
        Spacer(modifier = Modifier.width(10.dp))
        FrostedCircleButton(onClick = onOpenSettings) {
          Icon(
            Icons.Rounded.Settings,
            contentDescription = stringResource(R.string.voice_settings_title),
            tint = Color.White,
            modifier = Modifier.size(22.dp),
          )
        }
      }

      // Keep the upper half clear so the character's face (avatar background) stays visible; the
      // conversation lives in the lower half and is bottom-anchored.
      Spacer(modifier = Modifier.weight(1f))

      // Conversation transcript (lower half).
      Box(modifier = Modifier.fillMaxWidth().weight(1f)) {
        when {
          modelReady && uiState.messages.isEmpty() ->
            GreetingHint(characterName = selectedCharacter.name)
          modelReady ->
            Transcript(
              messages = uiState.messages,
              avatarRes = selectedCharacter.imageRes,
              onDeleteBefore = { index -> viewModel.deleteMessagesBefore(index) },
              onRegenerate = { index -> viewModel.regenerate(index) },
              onNewChat = { viewModel.clearConversation() },
            )
          // Downloaded but still loading — don't nag the user to open settings.
          modelDownloaded -> PreparingHint(characterName = selectedCharacter.name)
          else -> NotReadyHint(onOpenSettings = onOpenSettings)
        }
      }

      // Live partial transcript while listening.
      AnimatedVisibility(
        visible = uiState.isListening && uiState.partialTranscript.isNotEmpty(),
        enter = fadeIn(),
        exit = fadeOut(),
      ) {
        Text(
          text = uiState.partialTranscript,
          color = ListeningColor,
          fontSize = 15.sp,
          textAlign = TextAlign.Center,
          modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 6.dp),
        )
      }

      if (uiState.error.isNotEmpty()) {
        Text(
          text = uiState.error,
          color = MaterialTheme.colorScheme.error,
          fontSize = 12.sp,
          textAlign = TextAlign.Center,
          modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 4.dp),
        )
      }

      // Tool-use status (skills / MCP / web search), animated and separate from the message.
      AnimatedVisibility(
        visible = uiState.toolActivity.isNotEmpty(),
        enter = fadeIn(),
        exit = fadeOut(),
      ) {
        ToolActivityChip(label = uiState.toolActivity)
      }

      // Bottom controls: standard (text + one-shot mic) or hands-free call mode.
      when (uiState.inputMode) {
        ChatInputMode.CALL ->
          CallControls(
            isListening = uiState.isListening,
            isThinking = uiState.isThinking,
            isSpeaking = uiState.isSpeaking,
            onEndCall = { viewModel.setInputMode(ChatInputMode.STANDARD) },
            modifier = Modifier.padding(bottom = 20.dp, top = 6.dp),
          )
        ChatInputMode.STANDARD ->
          InputBar(
            enabled = modelReady,
            disabledPlaceholder =
              if (modelDownloaded) "잠시만요, 준비 중이에요…" else "설정에서 모델 받기",
            isListening = uiState.isListening,
            isThinking = uiState.isThinking,
            isSpeaking = uiState.isSpeaking,
            onSendText = { text -> targetModel?.let { viewModel.sendStarter(text, it) } },
            onMicClick = toggleMic,
            onMicLongClick = enterCallMode,
            modifier = Modifier.padding(horizontal = 12.dp).padding(bottom = 12.dp, top = 4.dp),
          )
      }
    }

    // Floating emoji emotion effect, on top of everything (non-interactive).
    EmotionOverlay(cue = emotionCue)
  }
}

private fun statusLabel(
  state: VoiceAssistantUiState,
  modelReady: Boolean,
  modelDownloaded: Boolean,
): String =
  when {
    !modelReady && modelDownloaded -> "모델을 불러오는 중이에요…"
    !modelReady -> "설정에서 AI 모델을 준비해 주세요"
    state.toolActivity.isNotEmpty() -> state.toolActivity
    state.isListening -> "듣고 있어요…"
    state.isThinking -> "생각 중…"
    state.isSpeaking -> "말하는 중…"
    else -> "마이크를 누르거나 메시지를 입력하세요"
  }

@Composable
private fun FrostedCircleButton(onClick: () -> Unit, content: @Composable () -> Unit) {
  Box(
    modifier =
      Modifier.size(40.dp)
        .clip(CircleShape)
        .background(Color.White.copy(alpha = 0.16f))
        .clickable { onClick() },
    contentAlignment = Alignment.Center,
  ) {
    content()
  }
}

@Composable
private fun NotReadyHint(onOpenSettings: () -> Unit) {
  Column(
    modifier = Modifier.fillMaxSize().padding(horizontal = 36.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.Center,
  ) {
    Text(
      text = "대화를 시작하려면 AI 모델이 필요해요",
      color = Color.White,
      fontWeight = FontWeight.SemiBold,
      fontSize = 17.sp,
      textAlign = TextAlign.Center,
    )
    Spacer(modifier = Modifier.height(10.dp))
    Text(
      text = "설정에서 모델을 한 번만 내려받으면 오프라인으로 대화할 수 있습니다.",
      color = Color.White.copy(alpha = 0.75f),
      fontSize = 13.sp,
      textAlign = TextAlign.Center,
    )
    Spacer(modifier = Modifier.height(18.dp))
    Box(
      modifier =
        Modifier.clip(RoundedCornerShape(24.dp))
          .background(Brush.horizontalGradient(listOf(AccentPurple, AccentPink)))
          .clickable { onOpenSettings() }
          .padding(horizontal = 22.dp, vertical = 12.dp)
    ) {
      Text(text = "설정 열기", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 15.sp)
    }
  }
}

@Composable
private fun PreparingHint(characterName: String) {
  Column(
    modifier = Modifier.fillMaxSize().padding(horizontal = 36.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.Center,
  ) {
    CircularProgressIndicator(color = Color.White, strokeWidth = 3.dp, modifier = Modifier.size(34.dp))
    Spacer(modifier = Modifier.height(18.dp))
    Text(
      text = "${characterName}를 깨우는 중이에요…",
      color = Color.White,
      fontWeight = FontWeight.SemiBold,
      fontSize = 16.sp,
      textAlign = TextAlign.Center,
    )
    Spacer(modifier = Modifier.height(8.dp))
    Text(
      text = "모델을 처음 불러올 때는 시간이 조금 걸려요.",
      color = Color.White.copy(alpha = 0.75f),
      fontSize = 13.sp,
      textAlign = TextAlign.Center,
    )
  }
}

@Composable
private fun GreetingHint(characterName: String) {
  Column(
    modifier = Modifier.fillMaxSize().padding(horizontal = 36.dp, vertical = 24.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.Bottom,
  ) {
    Text(
      text = "안녕! 나는 ${characterName}야. 편하게 말 걸어줘 😊",
      color = Color.White,
      fontWeight = FontWeight.SemiBold,
      fontSize = 16.sp,
      textAlign = TextAlign.Center,
    )
    Spacer(modifier = Modifier.height(8.dp))
    Text(
      text = "마이크를 눌러 음성으로, 또는 아래에 메시지를 입력해 대화를 시작하세요.",
      color = Color.White.copy(alpha = 0.7f),
      fontSize = 13.sp,
      textAlign = TextAlign.Center,
    )
  }
}

@Composable
private fun Transcript(
  messages: List<ChatMessage>,
  avatarRes: Int,
  onDeleteBefore: (Int) -> Unit,
  onRegenerate: (Int) -> Unit,
  onNewChat: () -> Unit,
) {
  val listState = rememberLazyListState()
  // Keep the latest message in view as it streams in.
  LaunchedEffect(messages.size, messages.lastOrNull()?.text) {
    if (messages.isNotEmpty()) {
      listState.animateScrollToItem(messages.size - 1)
    }
  }
  LazyColumn(
    state = listState,
    // Bottom-anchored so few messages sit near the input (the character's face stays visible above),
    // and faded at the top so older messages dissolve upward as they scroll away.
    modifier = Modifier.fillMaxSize().topFade(),
    verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.Bottom),
    contentPadding = PaddingValues(horizontal = 14.dp, vertical = 10.dp),
  ) {
    itemsIndexed(messages) { index, message ->
      VoiceChatBubble(
        message = message,
        avatarRes = avatarRes,
        canDeleteBefore = index > 0,
        onDeleteBefore = { onDeleteBefore(index) },
        onRegenerate = { onRegenerate(index) },
        onNewChat = onNewChat,
      )
    }
  }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun VoiceChatBubble(
  message: ChatMessage,
  avatarRes: Int,
  canDeleteBefore: Boolean,
  onDeleteBefore: () -> Unit,
  onRegenerate: () -> Unit,
  onNewChat: () -> Unit,
) {
  val isUser = message.role == ChatMessage.Role.USER
  // An assistant reply that hasn't produced any text yet: show an animated typing indicator.
  val isTyping = !isUser && message.isStreaming && message.text.isBlank()
  val text = message.text
  if (text.isBlank() && !isTyping) return

  var menuOpen by remember { mutableStateOf(false) }
  val clipboard = LocalClipboardManager.current
  val context = LocalContext.current

  Row(
    modifier = Modifier.fillMaxWidth(),
    horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    verticalAlignment = Alignment.Bottom,
  ) {
    if (!isUser) {
      Image(
        painter = painterResource(avatarRes),
        contentDescription = null,
        contentScale = ContentScale.Crop,
        modifier = Modifier.size(30.dp).clip(CircleShape),
      )
      Spacer(modifier = Modifier.width(8.dp))
    }

    val shape =
      RoundedCornerShape(
        topStart = 20.dp,
        topEnd = 20.dp,
        bottomStart = if (isUser) 20.dp else 6.dp,
        bottomEnd = if (isUser) 6.dp else 20.dp,
      )
    val bubbleModifier =
      if (isUser) {
        Modifier.clip(shape)
          .background(Brush.horizontalGradient(listOf(AccentPurple, AccentPink)))
      } else {
        Modifier.clip(shape).background(Color.White.copy(alpha = 0.14f))
      }
    Box(
      modifier =
        Modifier.widthIn(max = 280.dp)
          .then(bubbleModifier)
          .combinedClickable(onClick = {}, onLongClick = { menuOpen = true })
    ) {
      if (isTyping) {
        TypingDots(modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp))
      } else if (isUser) {
        // User input is plain text — render verbatim (no markdown parsing).
        Text(
          text = text,
          color = Color.White,
          fontSize = 15.sp,
          lineHeight = 21.sp,
          modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
        )
      } else {
        // Assistant replies may contain markdown / code blocks — render them properly (code shows
        // in a monospace block). The same text is read aloud with code stripped out (see TTS).
        MarkdownText(
          text = text,
          smallFontSize = true,
          textColor = Color.White,
          modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
        )
      }
      // Long-press menu. More actions can be added here later.
      DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
        DropdownMenuItem(
          text = { Text("메시지 복사") },
          leadingIcon = { Icon(Icons.Rounded.ContentCopy, contentDescription = null) },
          onClick = {
            menuOpen = false
            clipboard.setText(AnnotatedString(message.text))
            Toast.makeText(context, "복사했어요", Toast.LENGTH_SHORT).show()
          },
        )
        if (!isUser) {
          DropdownMenuItem(
            text = { Text("다시 답하기") },
            leadingIcon = { Icon(Icons.Rounded.Refresh, contentDescription = null) },
            onClick = {
              menuOpen = false
              onRegenerate()
            },
          )
        }
        DropdownMenuItem(
          text = { Text("이전 대화 삭제") },
          enabled = canDeleteBefore,
          leadingIcon = { Icon(Icons.Outlined.DeleteSweep, contentDescription = null) },
          onClick = {
            menuOpen = false
            onDeleteBefore()
          },
        )
        DropdownMenuItem(
          text = { Text("새 대화 시작") },
          leadingIcon = { Icon(Icons.Rounded.RestartAlt, contentDescription = null) },
          onClick = {
            menuOpen = false
            onNewChat()
          },
        )
      }
    }
  }
}

/** Animated three-dot "typing" indicator shown while the assistant is forming its reply. */
@Composable
private fun TypingDots(modifier: Modifier = Modifier) {
  val transition = rememberInfiniteTransition(label = "typing")
  Row(
    modifier = modifier,
    horizontalArrangement = Arrangement.spacedBy(5.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    repeat(3) { i ->
      val alpha by
        transition.animateFloat(
          initialValue = 0.3f,
          targetValue = 1f,
          animationSpec =
            infiniteRepeatable(
              animation = tween(durationMillis = 600, delayMillis = i * 160, easing = LinearEasing),
              repeatMode = RepeatMode.Reverse,
            ),
          label = "dot$i",
        )
      Box(
        modifier =
          Modifier.size(7.dp).clip(CircleShape).background(Color.White.copy(alpha = alpha))
      )
    }
  }
}

/** An animated status chip shown while a tool/skill/search is running (e.g. "인터넷 검색 중…"). */
@Composable
private fun ToolActivityChip(label: String, modifier: Modifier = Modifier) {
  Row(
    modifier = modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 4.dp),
    horizontalArrangement = Arrangement.Center,
  ) {
    Row(
      modifier =
        Modifier.clip(RoundedCornerShape(50))
          .background(Color.White.copy(alpha = 0.16f))
          .padding(horizontal = 14.dp, vertical = 8.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      CircularProgressIndicator(
        modifier = Modifier.size(14.dp),
        strokeWidth = 2.dp,
        color = ListeningColor,
      )
      Spacer(modifier = Modifier.width(8.dp))
      Text(label, color = Color.White.copy(alpha = 0.9f), fontSize = 13.sp)
    }
  }
}

@Composable
private fun InputBar(
  enabled: Boolean,
  disabledPlaceholder: String,
  isListening: Boolean,
  isThinking: Boolean,
  isSpeaking: Boolean,
  onSendText: (String) -> Unit,
  onMicClick: () -> Unit,
  onMicLongClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  var text by remember { mutableStateOf("") }
  val canSend = enabled && text.isNotBlank()

  Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
    // Text field pill.
    Row(
      modifier =
        Modifier.weight(1f)
          .clip(RoundedCornerShape(26.dp))
          .background(Color.White.copy(alpha = 0.14f))
          .padding(start = 18.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Box(modifier = Modifier.weight(1f)) {
        if (text.isEmpty()) {
          Text(
            text = if (enabled) "메시지 입력…" else disabledPlaceholder,
            color = Color.White.copy(alpha = 0.5f),
            fontSize = 15.sp,
          )
        }
        BasicTextField(
          value = text,
          onValueChange = { if (enabled) text = it },
          enabled = enabled,
          textStyle = TextStyle(color = Color.White, fontSize = 15.sp),
          cursorBrush = SolidColor(AccentPink),
          modifier = Modifier.fillMaxWidth(),
        )
      }
      // Send button appears once there's text to send.
      AnimatedVisibility(visible = canSend, enter = fadeIn(), exit = fadeOut()) {
        Box(
          modifier =
            Modifier.size(40.dp)
              .clip(CircleShape)
              .background(Brush.horizontalGradient(listOf(AccentPurple, AccentPink)))
              .clickable {
                if (canSend) {
                  onSendText(text.trim())
                  text = ""
                }
              },
          contentAlignment = Alignment.Center,
        ) {
          Icon(
            Icons.AutoMirrored.Rounded.Send,
            contentDescription = "보내기",
            tint = Color.White,
            modifier = Modifier.size(20.dp),
          )
        }
      }
    }

    Spacer(modifier = Modifier.width(10.dp))

    // The merged listening-orb + microphone control. Long-press to enter hands-free call mode.
    MicOrb(
      enabled = enabled,
      isListening = isListening,
      isThinking = isThinking,
      isSpeaking = isSpeaking,
      onClick = { if (enabled) onMicClick() },
      onLongClick = { if (enabled) onMicLongClick() },
    )
  }
}

/**
 * The microphone control with the assistant's reactive "orb" animation merged in: a pulsing,
 * rotating halo whose colour reflects the current state (listening / thinking / speaking / idle),
 * with a mic (or stop) icon in the centre.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MicOrb(
  enabled: Boolean,
  isListening: Boolean,
  isThinking: Boolean,
  isSpeaking: Boolean,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  onLongClick: () -> Unit = {},
  coreSize: Dp = 60.dp,
) {
  val active = isListening || isThinking || isSpeaking
  val coreColor =
    when {
      isListening -> ListeningColor
      isThinking -> ThinkingColor
      isSpeaking -> SpeakingColor
      else -> AccentPurple
    }
  val haloSize = coreSize * 1.27f
  val iconSize = coreSize * 0.44f

  val transition = rememberInfiniteTransition(label = "micorb")
  val pulse by
    transition.animateFloat(
      initialValue = 0.9f,
      targetValue = if (active) 1.18f else 1.04f,
      animationSpec =
        infiniteRepeatable(
          animation = tween(durationMillis = if (isListening) 550 else 1300, easing = LinearEasing),
          repeatMode = RepeatMode.Reverse,
        ),
      label = "pulse",
    )

  Box(modifier = modifier.size(haloSize), contentAlignment = Alignment.Center) {
    // Soft circular glow halo. A radial gradient that fades to fully transparent before the edge
    // keeps the corners empty, so the glow is always a clean circle (no rotating-square artifact).
    Box(
      modifier =
        Modifier.size(haloSize)
          .graphicsLayer {
            scaleX = pulse
            scaleY = pulse
            alpha = if (enabled) 0.6f else 0.22f
          }
          .blur(coreSize * 0.12f)
          .clip(CircleShape)
          .background(
            Brush.radialGradient(
              listOf(
                coreColor.copy(alpha = 0.95f),
                coreColor.copy(alpha = 0.45f),
                coreColor.copy(alpha = 0f),
              )
            )
          )
    )
    // Solid mic core.
    Box(
      modifier =
        Modifier.size(coreSize)
          .clip(CircleShape)
          .background(
            if (enabled) {
              Brush.radialGradient(listOf(coreColor, coreColor.copy(alpha = 0.65f)))
            } else {
              Brush.radialGradient(
                listOf(Color.White.copy(alpha = 0.25f), Color.White.copy(alpha = 0.12f))
              )
            }
          )
          .combinedClickable(onClick = onClick, onLongClick = onLongClick),
      contentAlignment = Alignment.Center,
    ) {
      Icon(
        imageVector = if (isListening) Icons.Rounded.Stop else Icons.Rounded.Mic,
        contentDescription = if (isListening) "듣기 중지" else "듣기 시작",
        tint = Color.White,
        modifier = Modifier.size(iconSize),
      )
    }
  }
}

/**
 * Hands-free "phone call" control: a single large button that ends the call (returns to standard
 * input) when tapped, wrapped in a state-reactive glow (listening / thinking / speaking). The
 * continuous call loop drives listening automatically, so no separate mic control is needed.
 */
@Composable
private fun CallControls(
  isListening: Boolean,
  isThinking: Boolean,
  isSpeaking: Boolean,
  onEndCall: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Column(
    modifier = modifier.fillMaxWidth(),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    Text(
      text = callStatusLabel(isListening, isThinking, isSpeaking),
      color = Color.White.copy(alpha = 0.85f),
      fontSize = 14.sp,
      fontWeight = FontWeight.Medium,
    )
    CallButton(
      isListening = isListening,
      isThinking = isThinking,
      isSpeaking = isSpeaking,
      onClick = onEndCall,
    )
  }
}

private fun callStatusLabel(
  isListening: Boolean,
  isThinking: Boolean,
  isSpeaking: Boolean,
): String =
  when {
    isListening -> "듣고 있어요…"
    isThinking -> "생각 중…"
    isSpeaking -> "말하는 중…"
    else -> "연결됨 · 말하면 들을게요"
  }

/**
 * The merged call button: a red hang-up core surrounded by a reactive glow whose colour/pulse
 * reflects the listening/thinking/speaking state. Tapping it ends the call (changes mode).
 */
@Composable
private fun CallButton(
  isListening: Boolean,
  isThinking: Boolean,
  isSpeaking: Boolean,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val active = isListening || isThinking || isSpeaking
  val glowColor =
    when {
      isListening -> ListeningColor
      isThinking -> ThinkingColor
      isSpeaking -> SpeakingColor
      else -> AccentPurple
    }
  val haloSize = 132.dp
  val coreSize = 88.dp

  val transition = rememberInfiniteTransition(label = "callbtn")
  val pulse by
    transition.animateFloat(
      initialValue = 0.92f,
      targetValue = if (active) 1.16f else 1.04f,
      animationSpec =
        infiniteRepeatable(
          animation = tween(durationMillis = if (isListening) 600 else 1400, easing = LinearEasing),
          repeatMode = RepeatMode.Reverse,
        ),
      label = "pulse",
    )
  // Expanding ripple ring, emphasised while active (live mic / speaking).
  val ripple by
    transition.animateFloat(
      initialValue = 0f,
      targetValue = 1f,
      animationSpec =
        infiniteRepeatable(
          animation = tween(durationMillis = 1800, easing = LinearEasing),
          repeatMode = RepeatMode.Restart,
        ),
      label = "ripple",
    )

  Box(modifier = modifier.size(haloSize), contentAlignment = Alignment.Center) {
    // Outer expanding ripple.
    Box(
      modifier =
        Modifier.size(haloSize)
          .graphicsLayer {
            val s = 0.6f + 0.5f * ripple
            scaleX = s
            scaleY = s
            alpha = (if (active) 0.5f else 0.25f) * (1f - ripple)
          }
          .clip(CircleShape)
          .background(glowColor.copy(alpha = 0.5f))
    )
    // Soft circular glow halo. A radial gradient that fades to fully transparent before the edge
    // keeps the corners empty, so the glow stays a clean circle (no rotating-square artifact).
    Box(
      modifier =
        Modifier.size(haloSize)
          .graphicsLayer {
            scaleX = pulse
            scaleY = pulse
            alpha = 0.6f
          }
          .blur(12.dp)
          .clip(CircleShape)
          .background(
            Brush.radialGradient(
              listOf(
                glowColor.copy(alpha = 0.9f),
                glowColor.copy(alpha = 0.4f),
                glowColor.copy(alpha = 0f),
              )
            )
          )
    )
    // Red hang-up core (tap to end the call / switch back to standard input).
    Box(
      modifier =
        Modifier.size(coreSize)
          .clip(CircleShape)
          .background(
            Brush.radialGradient(listOf(Color(0xFFF0555A), Color(0xFFD1383D)))
          )
          .clickable { onClick() },
      contentAlignment = Alignment.Center,
    ) {
      Icon(
        Icons.Rounded.CallEnd,
        contentDescription = "통화 종료",
        tint = Color.White,
        modifier = Modifier.size(34.dp),
      )
    }
  }
}
