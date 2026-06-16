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

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.outlined.CheckCircle as CheckCircleOutlined
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.WorkspacePremium
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.google.ai.edge.gallery.customtasks.agentchat.McpManagerBottomSheet
import com.google.ai.edge.gallery.customtasks.agentchat.McpManagerViewModel
import com.google.ai.edge.gallery.character.CharacterViewModel
import com.google.ai.edge.gallery.customtasks.agentchat.SkillManagerBottomSheet
import com.google.ai.edge.gallery.customtasks.agentchat.SkillManagerViewModel
import com.google.ai.edge.gallery.customtasks.speech.KOREAN_TTS_MODEL_NAME
import com.google.ai.edge.gallery.customtasks.speech.MELO_TTS_MODEL_NAME
import com.google.ai.edge.gallery.customtasks.speech.NEURAL_STT_MODEL_NAME
import com.google.ai.edge.gallery.customtasks.speech.WHISPER_KO_STT_MODEL_NAME
import com.google.ai.edge.gallery.customtasks.voiceassistant.NeuralSttState
import com.google.ai.edge.gallery.customtasks.voiceassistant.NeuralVoiceStage
import com.google.ai.edge.gallery.customtasks.voiceassistant.NeuralVoiceState
import com.google.ai.edge.gallery.customtasks.voiceassistant.SttEngine
import com.google.ai.edge.gallery.customtasks.voiceassistant.TtsSpeakMode
import com.google.ai.edge.gallery.customtasks.voiceassistant.TOOL_MODEL_AUTO
import com.google.ai.edge.gallery.customtasks.voiceassistant.VOICE_ASSISTANT_TASK_ID
import com.google.ai.edge.gallery.customtasks.voiceassistant.VoiceAssistantTask
import com.google.ai.edge.gallery.customtasks.voiceassistant.modelSupportsFunctionCalling
import com.google.ai.edge.gallery.customtasks.voiceassistant.VoiceAssistantViewModel
import com.google.ai.edge.gallery.data.Model
import com.google.ai.edge.gallery.data.ModelDownloadStatus
import com.google.ai.edge.gallery.data.ModelDownloadStatusType
import android.widget.Toast
import androidx.compose.ui.platform.LocalContext
import com.google.ai.edge.gallery.ui.common.humanReadableSize
import com.google.ai.edge.gallery.ui.modelmanager.ModelManagerViewModel

/**
 * The unified settings screen for the Voice Chat experience, reached from the gear on [MainPage].
 *
 * Everything that would otherwise clutter the chat lives here: choosing/downloading the LLM, the
 * speech-recognition (STT) engine and the spoken voice (TTS), managing tools / skills / MCP servers,
 * and opening the Pro subscription screen. It shares the same [VoiceAssistantViewModel] as the chat
 * (scoped to the parent nav graph), so selections take effect immediately.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoiceChatSettingsScreen(
  modelManagerViewModel: ModelManagerViewModel,
  viewModel: VoiceAssistantViewModel,
  skillManagerViewModel: SkillManagerViewModel,
  mcpManagerViewModel: McpManagerViewModel,
  characterViewModel: CharacterViewModel,
  onOpenSubscription: () -> Unit,
  onOpenHome: () -> Unit,
  onOpenDashChat: () -> Unit,
  navigateUp: () -> Unit,
) {
  val context = LocalContext.current
  val modelManagerUiState by modelManagerViewModel.uiState.collectAsState()
  val uiState by viewModel.uiState.collectAsState()
  val charState by characterViewModel.state.collectAsState()

  val voiceTask = modelManagerViewModel.getTaskById(VOICE_ASSISTANT_TASK_ID)
  val voiceCustomTask =
    modelManagerViewModel.getCustomTaskByTaskId(VOICE_ASSISTANT_TASK_ID) as? VoiceAssistantTask

  // Keep the shared engines/counts wired while on this screen too (idempotent).
  if (voiceTask != null && voiceCustomTask != null) {
    VoiceChatPlumbing(
      task = voiceTask,
      modelManagerViewModel = modelManagerViewModel,
      viewModel = viewModel,
      skillManagerViewModel = skillManagerViewModel,
      mcpManagerViewModel = mcpManagerViewModel,
      agentTools = voiceCustomTask.agentTools,
    )
  }

  var showSkillSheet by remember { mutableStateOf(false) }
  var showMcpSheet by remember { mutableStateOf(false) }

  if (showSkillSheet && voiceCustomTask != null) {
    SkillManagerBottomSheet(
      agentTools = voiceCustomTask.agentTools,
      skillManagerViewModel = skillManagerViewModel,
      onDismiss = { showSkillSheet = false },
    )
  }
  if (showMcpSheet) {
    McpManagerBottomSheet(
      mcpManagerViewModel = mcpManagerViewModel,
      onDismiss = { showMcpSheet = false },
    )
  }

  val koreanTtsModel = remember { modelManagerViewModel.getModelByName(KOREAN_TTS_MODEL_NAME) }
  val meloTtsModel = remember { modelManagerViewModel.getModelByName(MELO_TTS_MODEL_NAME) }
  val neuralSttModel = remember { modelManagerViewModel.getModelByName(NEURAL_STT_MODEL_NAME) }
  val whisperSttModel = remember { modelManagerViewModel.getModelByName(WHISPER_KO_STT_MODEL_NAME) }

  Scaffold(
    topBar = {
      TopAppBar(
        title = { Text("설정") },
        navigationIcon = {
          IconButton(onClick = navigateUp) {
            Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "뒤로")
          }
        },
      )
    }
  ) { innerPadding ->
    Column(
      modifier =
        Modifier.padding(innerPadding)
          .verticalScroll(rememberScrollState())
          .padding(horizontal = 16.dp, vertical = 8.dp),
      verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
      // --- LLM ---
      SettingsSection(title = "AI 모델 (LLM)", subtitle = "대화에 사용할 온디바이스 모델") {
        val llmModels = voiceTask?.models.orEmpty()
        if (llmModels.isEmpty()) {
          Text(
            "사용 가능한 모델이 없습니다.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        } else {
          llmModels.forEach { model ->
            LlmModelRow(
              model = model,
              selected = modelManagerUiState.selectedModel.name == model.name,
              downloadStatus = modelManagerUiState.modelDownloadStatus[model.name],
              onSelect = { modelManagerViewModel.selectModel(model) },
              onDownload = { modelManagerViewModel.downloadModel(task = voiceTask, model = model) },
            )
          }
        }
      }

      // --- Tool model (2-model design) ---
      // Only consulted when the chat model can't do function calling itself; lets a downloaded
      // tool-capable model (e.g. a small Gemma) provide tools. "없음" = no second model (run the chat
      // model standalone); "자동" picks the smallest one. Default is "없음" so two models aren't
      // loaded (which can OOM/crash on some devices) unless the user opts in.
      SettingsSection(
        title = "도구 담당 모델",
        subtitle = "대화 모델이 도구 호출(웹검색 등)을 직접 못 할 때 대신할 보조 모델. '없음'이면 보조 모델을 띄우지 않아요(메모리 절약).",
      ) {
        val toolCandidates =
          (voiceTask?.models.orEmpty()).filter { m ->
            modelManagerUiState.modelDownloadStatus[m.name]?.status ==
              ModelDownloadStatusType.SUCCEEDED && modelSupportsFunctionCalling(m.name)
          }
        Row(
          modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
          horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
          ChoiceChip("없음", charState.toolModelName.isEmpty()) {
            characterViewModel.setToolModel("")
          }
          ChoiceChip("자동", charState.toolModelName == TOOL_MODEL_AUTO) {
            characterViewModel.setToolModel(TOOL_MODEL_AUTO)
          }
          toolCandidates.forEach { m ->
            ChoiceChip(m.name, charState.toolModelName == m.name) {
              characterViewModel.setToolModel(m.name)
            }
          }
        }
        if (toolCandidates.isEmpty()) {
          Spacer(modifier = Modifier.height(6.dp))
          Text(
            "툴콜을 지원하는 모델(예: Gemma)을 먼저 다운로드하면 여기서 고를 수 있어요.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
      }

      // --- STT ---
      SettingsSection(title = "음성 인식 (STT)", subtitle = "내 말을 텍스트로 바꾸는 엔진") {
        val senseReady = uiState.neuralStt.stage == NeuralVoiceStage.READY
        val whisperReady = uiState.whisperStt.stage == NeuralVoiceStage.READY
        Row(
          modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
          horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
          ChoiceChip("시스템", uiState.sttEngine == SttEngine.SYSTEM) {
            viewModel.selectSttEngine(SttEngine.SYSTEM)
          }
          if (senseReady) {
            ChoiceChip("SenseVoice", uiState.sttEngine == SttEngine.NEURAL) {
              viewModel.selectSttEngine(SttEngine.NEURAL)
            }
          }
          if (whisperReady) {
            ChoiceChip("Whisper", uiState.sttEngine == SttEngine.WHISPER) {
              viewModel.selectSttEngine(SttEngine.WHISPER)
            }
          }
        }

        if (neuralSttModel != null && !senseReady) {
          Spacer(modifier = Modifier.height(10.dp))
          NeuralSttDownloadRow(
            title = "SenseVoice (오프라인 인식)",
            descNotInstalled = "인터넷 없이 기기에서 음성 인식 (약 239MB)",
            state = uiState.neuralStt,
            onDownload = {
              modelManagerViewModel.downloadModel(task = null, model = neuralSttModel)
            },
            onRetry = { viewModel.retryNeuralSttPreparation() },
          )
        }
        if (whisperSttModel != null && !whisperReady) {
          Spacer(modifier = Modifier.height(10.dp))
          NeuralSttDownloadRow(
            title = "Whisper 한국어 인식",
            descNotInstalled = "더 정확한 한국어 인식 (약 374MB)",
            state = uiState.whisperStt,
            onDownload = {
              modelManagerViewModel.downloadModel(task = null, model = whisperSttModel)
            },
            onRetry = { viewModel.retryWhisperSttPreparation() },
          )
        }
      }

      // --- TTS ---
      SettingsSection(title = "음성 합성 (TTS)", subtitle = "AI의 답변을 읽어주는 목소리") {
        Text(
          "기본 목소리예요. 캐릭터 상세에서 따로 지정하지 않은 캐릭터는 이 목소리로 말해요.",
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (uiState.voices.isNotEmpty()) {
          Spacer(modifier = Modifier.height(8.dp))
          Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
          ) {
            uiState.voices.forEach { voice ->
              ChoiceChip(
                label = voice.label,
                selected = voice.id == charState.defaultVoiceId,
                neural = voice.isNeural || voice.isCloud,
              ) {
                characterViewModel.setDefaultVoice(voice.id)
              }
            }
          }
        }

        if (uiState.ttsReady) {
          Spacer(modifier = Modifier.height(10.dp))
          Text(
            "발화 방식",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
          Spacer(modifier = Modifier.height(6.dp))
          Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ChoiceChip("전체 발화", uiState.speakMode == TtsSpeakMode.AFTER_COMPLETE) {
              viewModel.setSpeakMode(TtsSpeakMode.AFTER_COMPLETE)
            }
            ChoiceChip("실시간 발화", uiState.speakMode == TtsSpeakMode.STREAMING) {
              viewModel.setSpeakMode(TtsSpeakMode.STREAMING)
            }
          }
        }

        if (koreanTtsModel != null && uiState.neuralVoice.stage != NeuralVoiceStage.READY) {
          Spacer(modifier = Modifier.height(10.dp))
          NeuralVoiceDownloadRow(
            title = "고품질 한국어 음성 (KSS)",
            descNotInstalled = "더 자연스러운 음성 (약 64MB)",
            state = uiState.neuralVoice,
            onDownload = {
              modelManagerViewModel.downloadModel(task = null, model = koreanTtsModel)
            },
            onRetry = { viewModel.retryNeuralPreparation() },
          )
        }
        if (
          meloTtsModel != null &&
            meloTtsModel.url.isNotEmpty() &&
            uiState.meloVoice.stage != NeuralVoiceStage.READY
        ) {
          Spacer(modifier = Modifier.height(10.dp))
          NeuralVoiceDownloadRow(
            title = "MeloTTS 한국어 음성",
            descNotInstalled = "MeloTTS의 자연스러운 한국어 음성",
            state = uiState.meloVoice,
            onDownload = { modelManagerViewModel.downloadModel(task = null, model = meloTtsModel) },
            onRetry = { viewModel.retryMeloPreparation() },
          )
        }
      }

      // --- Tools / Skills / Agents ---
      SettingsSection(title = "도구 · 스킬 · 에이전트", subtitle = "AI가 할 수 있는 일을 확장하세요") {
        Text(
          "스킬 ${uiState.skillCount}개 · 도구 ${uiState.mcpToolCount}개 사용 가능",
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          Button(onClick = { showSkillSheet = true }) { Text("스킬 관리") }
          Button(onClick = { showMcpSheet = true }) { Text("MCP 도구") }
        }
      }

      // --- Subscription ---
      SettingsSection(title = "구독", subtitle = "더 많은 기능을 잠금 해제") {
        Surface(
          onClick = onOpenSubscription,
          shape = RoundedCornerShape(14.dp),
          color = MaterialTheme.colorScheme.primaryContainer,
          modifier = Modifier.fillMaxWidth(),
        ) {
          Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
          ) {
            Icon(
              Icons.Rounded.WorkspacePremium,
              contentDescription = null,
              tint = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
              Text(
                "Pro 구독",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
              )
              Text(
                "모든 기능과 캐릭터를 잠금 해제",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f),
              )
            }
          }
        }
      }

      // --- Back to the original Gallery home ---
      SettingsSection(title = "홈", subtitle = "원래 Gallery 홈 화면으로 이동") {
        Surface(
          onClick = onOpenHome,
          shape = RoundedCornerShape(14.dp),
          color = MaterialTheme.colorScheme.surfaceVariant,
          modifier = Modifier.fillMaxWidth(),
        ) {
          Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
          ) {
            Icon(
              Icons.Rounded.Home,
              contentDescription = null,
              tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
              Text(
                "홈 화면으로",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
              )
              Text(
                "원래 Gallery 홈으로 이동",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
              )
            }
          }
        }
      }

      // --- Dash Chat: re-download the web site cleanly (clears site + zip + WebView cache) ---
      SettingsSection(title = "대쉬 챗", subtitle = "웹 사이트를 지우고 최신 버전으로 새로 받기") {
        Button(
          onClick = {
            // Wipe the extracted site, the cached zip, and the WebView cache / storage so the same
            // URL fetches a fresh version next time. Then open Dash Chat, which re-downloads it.
            com.google.ai.edge.gallery.customtasks.dashchat.DashChatSite.clearAll(context)
            com.google.ai.edge.gallery.customtasks.dashchat.clearDashChatWebCache(context)
            Toast.makeText(context, "대쉬 챗 사이트를 지웠어요. 새로 받습니다.", Toast.LENGTH_SHORT).show()
            onOpenDashChat()
          },
          modifier = Modifier.fillMaxWidth(),
        ) {
          Text("사이트 지우고 새로 받기")
        }
      }

      Spacer(modifier = Modifier.height(8.dp))
    }
  }
}

@Composable
private fun SettingsSection(
  title: String,
  subtitle: String,
  content: @Composable () -> Unit,
) {
  Column(modifier = Modifier.fillMaxWidth()) {
    Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    Text(
      subtitle,
      style = MaterialTheme.typography.bodySmall,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(modifier = Modifier.height(10.dp))
    Surface(
      shape = RoundedCornerShape(16.dp),
      color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
      modifier = Modifier.fillMaxWidth(),
    ) {
      Column(modifier = Modifier.padding(14.dp)) { content() }
    }
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChoiceChip(
  label: String,
  selected: Boolean,
  neural: Boolean = false,
  onClick: () -> Unit,
) {
  val container =
    if (selected) MaterialTheme.colorScheme.primary
    else MaterialTheme.colorScheme.surface.copy(alpha = 0.8f)
  val content =
    if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
  Surface(onClick = onClick, shape = RoundedCornerShape(20.dp), color = container) {
    Row(
      verticalAlignment = Alignment.CenterVertically,
      modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
    ) {
      if (neural) {
        Icon(Icons.Rounded.AutoAwesome, null, tint = content, modifier = Modifier.size(15.dp))
        Spacer(modifier = Modifier.width(6.dp))
      }
      Text(label, style = MaterialTheme.typography.labelLarge, color = content)
    }
  }
}

@Composable
private fun LlmModelRow(
  model: Model,
  selected: Boolean,
  downloadStatus: ModelDownloadStatus?,
  onSelect: () -> Unit,
  onDownload: () -> Unit,
) {
  val statusType = downloadStatus?.status
  val downloaded = statusType == ModelDownloadStatusType.SUCCEEDED
  val unzipping = statusType == ModelDownloadStatusType.UNZIPPING
  val downloading =
    statusType == ModelDownloadStatusType.IN_PROGRESS ||
      statusType == ModelDownloadStatusType.PARTIALLY_DOWNLOADED ||
      unzipping
  // Download progress (determinate when the total size is known).
  val total = downloadStatus?.totalBytes ?: 0L
  val received = downloadStatus?.receivedBytes ?: 0L
  val percent = if (total > 0L) ((received * 100) / total).toInt().coerceIn(0, 100) else -1
  val showDeterminate = downloading && !unzipping && percent in 0..100
  // Human-readable download size from the allowlist (model file + any extra data files). Prefer the
  // precomputed total, then the raw model size, then the in-progress total once reported.
  val sizeBytes =
    when {
      model.totalBytes > 0L -> model.totalBytes
      model.sizeInBytes > 0L -> model.sizeInBytes
      else -> total
    }
  val sizeLabel = if (sizeBytes > 0L) sizeBytes.humanReadableSize() else ""

  Column(
    modifier =
      Modifier.fillMaxWidth()
        .let { if (downloaded) it.clickable { onSelect() } else it }
        .padding(vertical = 8.dp)
  ) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      Column(modifier = Modifier.weight(1f)) {
        Text(
          text = model.displayName.ifEmpty { model.name },
          style = MaterialTheme.typography.bodyMedium,
          fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
          color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
          text =
            when {
              selected -> if (sizeLabel.isNotEmpty()) "사용 중 · $sizeLabel" else "사용 중"
              downloaded -> if (sizeLabel.isNotEmpty()) "탭하여 선택 · $sizeLabel" else "탭하여 선택"
              unzipping -> "압축 해제 중…"
              downloading ->
                if (percent in 0..100)
                  "다운로드 중 $percent% · ${received.humanReadableSize()} / ${total.humanReadableSize()}"
                else "다운로드 중…"
              sizeLabel.isNotEmpty() -> "다운로드 필요 · $sizeLabel"
              else -> "다운로드 필요"
            },
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
      Spacer(modifier = Modifier.width(8.dp))
      // Fixed-width trailing slot so the check / download icons line up vertically across all rows
      // (a bare Icon is 24dp while an IconButton is 48dp — centering both in the same box aligns them).
      Box(modifier = Modifier.size(48.dp), contentAlignment = Alignment.Center) {
        when {
          selected ->
            Icon(
              Icons.Rounded.CheckCircle,
              contentDescription = "선택됨",
              tint = MaterialTheme.colorScheme.primary,
            )
          downloading -> {} // progress bar is shown below the row
          downloaded ->
            // Downloaded but not the active model: a dimmed, unfilled check makes it clear the row is
            // selectable (tap to select), vs the filled CheckCircle for the active one.
            Icon(
              Icons.Outlined.CheckCircleOutlined,
              contentDescription = "탭하여 선택",
              tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
            )
          else ->
            IconButton(onClick = onDownload) {
              Icon(Icons.Rounded.Download, contentDescription = "받기")
            }
        }
      }
    }

    // Progress bar, mirroring the STT/TTS download rows.
    if (downloading) {
      Spacer(modifier = Modifier.height(8.dp))
      if (showDeterminate) {
        LinearProgressIndicator(
          progress = { percent / 100f },
          modifier = Modifier.fillMaxWidth(),
        )
      } else {
        LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
      }
    }
  }
}

/** Compact download/preparation row for an optional neural voice (KSS / MeloTTS). */
@Composable
private fun NeuralVoiceDownloadRow(
  title: String,
  descNotInstalled: String,
  state: NeuralVoiceState,
  onDownload: () -> Unit,
  onRetry: () -> Unit,
) {
  val subtitle =
    when (state.stage) {
      NeuralVoiceStage.NOT_INSTALLED -> descNotInstalled
      NeuralVoiceStage.DOWNLOADING ->
        if (state.downloadPercent in 0..100) "다운로드 중 ${state.downloadPercent}%" else "다운로드 중…"
      NeuralVoiceStage.PREPARING ->
        if (state.unpackPercent in 0..100) "준비 중 ${state.unpackPercent}%" else "준비 중…"
      NeuralVoiceStage.ERROR -> state.error.ifEmpty { "오류가 발생했습니다." }
      NeuralVoiceStage.READY -> "사용 준비 완료"
    }
  val determinate =
    if (state.stage == NeuralVoiceStage.DOWNLOADING) state.downloadPercent
    else if (state.stage == NeuralVoiceStage.PREPARING) state.unpackPercent else -1
  DownloadRowScaffold(
    title = title,
    subtitle = subtitle,
    isError = state.stage == NeuralVoiceStage.ERROR,
    showDownload = state.stage == NeuralVoiceStage.NOT_INSTALLED,
    showSpinner =
      state.stage == NeuralVoiceStage.DOWNLOADING || state.stage == NeuralVoiceStage.PREPARING,
    showRetry = state.stage == NeuralVoiceStage.ERROR,
    progressPercent = determinate,
    showProgressBar =
      state.stage == NeuralVoiceStage.DOWNLOADING || state.stage == NeuralVoiceStage.PREPARING,
    onDownload = onDownload,
    onRetry = onRetry,
  )
}

/** Compact download/preparation row for an optional neural recognizer (SenseVoice / Whisper). */
@Composable
private fun NeuralSttDownloadRow(
  title: String,
  descNotInstalled: String,
  state: NeuralSttState,
  onDownload: () -> Unit,
  onRetry: () -> Unit,
) {
  val subtitle =
    when (state.stage) {
      NeuralVoiceStage.NOT_INSTALLED -> descNotInstalled
      NeuralVoiceStage.DOWNLOADING ->
        if (state.downloadPercent in 0..100) "다운로드 중 ${state.downloadPercent}%" else "다운로드 중…"
      NeuralVoiceStage.PREPARING -> "준비 중…"
      NeuralVoiceStage.ERROR -> state.error.ifEmpty { "오류가 발생했습니다." }
      NeuralVoiceStage.READY -> "사용 준비 완료"
    }
  DownloadRowScaffold(
    title = title,
    subtitle = subtitle,
    isError = state.stage == NeuralVoiceStage.ERROR,
    showDownload = state.stage == NeuralVoiceStage.NOT_INSTALLED,
    showSpinner =
      state.stage == NeuralVoiceStage.DOWNLOADING || state.stage == NeuralVoiceStage.PREPARING,
    showRetry = state.stage == NeuralVoiceStage.ERROR,
    progressPercent = if (state.stage == NeuralVoiceStage.DOWNLOADING) state.downloadPercent else -1,
    showProgressBar =
      state.stage == NeuralVoiceStage.DOWNLOADING || state.stage == NeuralVoiceStage.PREPARING,
    onDownload = onDownload,
    onRetry = onRetry,
  )
}

@Composable
private fun DownloadRowScaffold(
  title: String,
  subtitle: String,
  isError: Boolean,
  showDownload: Boolean,
  showSpinner: Boolean,
  showRetry: Boolean,
  progressPercent: Int,
  showProgressBar: Boolean,
  onDownload: () -> Unit,
  onRetry: () -> Unit,
) {
  Surface(
    shape = RoundedCornerShape(12.dp),
    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.7f),
    modifier = Modifier.fillMaxWidth(),
  ) {
    Column(modifier = Modifier.padding(12.dp)) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
          Icons.Rounded.AutoAwesome,
          contentDescription = null,
          tint = MaterialTheme.colorScheme.primary,
          modifier = Modifier.size(18.dp),
        )
        Spacer(modifier = Modifier.width(8.dp))
        Column(modifier = Modifier.weight(1f)) {
          Text(
            title,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
          )
          Text(
            subtitle,
            style = MaterialTheme.typography.bodySmall,
            color =
              if (isError) MaterialTheme.colorScheme.error
              else MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
        Spacer(modifier = Modifier.width(10.dp))
        when {
          showDownload -> Button(onClick = onDownload) { Text("받기") }
          showSpinner ->
            CircularProgressIndicator(modifier = Modifier.size(22.dp), strokeWidth = 2.dp)
          showRetry -> TextButton(onClick = onRetry) { Text("재시도") }
        }
      }
      if (showProgressBar) {
        Spacer(modifier = Modifier.height(8.dp))
        if (progressPercent in 0..100) {
          LinearProgressIndicator(
            progress = { progressPercent / 100f },
            modifier = Modifier.fillMaxWidth(),
          )
        } else {
          LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
      }
    }
  }
}
