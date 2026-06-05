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

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.google.ai.edge.gallery.customtasks.agentchat.AgentTools
import com.google.ai.edge.gallery.customtasks.agentchat.McpManagerViewModel
import com.google.ai.edge.gallery.customtasks.agentchat.SkillManagerViewModel
import com.google.ai.edge.gallery.customtasks.speech.KOREAN_TTS_MODEL_NAME
import com.google.ai.edge.gallery.customtasks.speech.MELO_TTS_MODEL_NAME
import com.google.ai.edge.gallery.customtasks.speech.NEURAL_STT_MODEL_NAME
import com.google.ai.edge.gallery.customtasks.speech.WHISPER_KO_STT_MODEL_NAME
import com.google.ai.edge.gallery.customtasks.voiceassistant.VoiceAssistantViewModel
import com.google.ai.edge.gallery.data.Task
import com.google.ai.edge.gallery.ui.modelmanager.ModelManagerViewModel

/**
 * Shared, headless wiring for the Voice Chat experience.
 *
 * Both the main chat screen ([MainPage]) and the settings screen ([VoiceChatSettingsScreen]) call
 * this so the shared [VoiceAssistantViewModel] keeps working regardless of which one is on screen:
 * it attaches the tool/skill/MCP surface, keeps the active model + tool/skill counts in sync, and
 * feeds the download/preparation status of the optional neural STT/TTS models so they get loaded
 * into memory once downloaded. All of the underlying ViewModel calls are idempotent, so it is safe
 * to run this from both screens at once.
 *
 * This intentionally renders no UI — model/voice selection and download controls live in
 * [VoiceChatSettingsScreen], keeping the chat screen clean.
 */
@Composable
fun VoiceChatPlumbing(
  task: Task,
  modelManagerViewModel: ModelManagerViewModel,
  viewModel: VoiceAssistantViewModel,
  skillManagerViewModel: SkillManagerViewModel,
  mcpManagerViewModel: McpManagerViewModel,
  agentTools: AgentTools,
) {
  val context = LocalContext.current
  val modelManagerUiState by modelManagerViewModel.uiState.collectAsState()

  // Wire the shared tool surface (skills + MCP) and start consuming its action channel.
  agentTools.context = context
  agentTools.skillManagerViewModel = skillManagerViewModel
  agentTools.mcpManagerViewModel = mcpManagerViewModel
  agentTools.taskId = task.id
  LaunchedEffect(agentTools) { viewModel.setAgentTools(agentTools) }

  // Keep the count of connected MCP tools / selected skills in sync (both enable function calling).
  val mcpUiState by mcpManagerViewModel.uiState.collectAsState()
  val mcpToolCount =
    mcpUiState.mcpServers
      .filter { it.mcpServer.enabled }
      .sumOf { server -> server.mcpServer.toolsList.count { it.enabled } }
  LaunchedEffect(mcpToolCount) { viewModel.setMcpToolCount(mcpToolCount) }

  val skillUiState by skillManagerViewModel.uiState.collectAsState()
  val skillCount = skillUiState.skills.count { it.skill.selected }
  LaunchedEffect(skillCount) { viewModel.setSkillCount(skillCount) }

  // Point the ViewModel at the active (selected) model. Selection + initialization itself is driven
  // by the main chat screen so it only happens while the chat is visible.
  val model = modelManagerUiState.selectedModel
  LaunchedEffect(model.name) { viewModel.setActiveModel(model) }

  // Feed the download/preparation status of the optional neural voices/recognizers so the ViewModel
  // can unpack + initialize them once their model files are present (used automatically when ready).
  val koreanTtsModel = remember { modelManagerViewModel.getModelByName(KOREAN_TTS_MODEL_NAME) }
  val koreanTtsStatus = koreanTtsModel?.let { modelManagerUiState.modelDownloadStatus[it.name] }
  LaunchedEffect(koreanTtsModel, koreanTtsStatus?.status, koreanTtsStatus?.receivedBytes) {
    viewModel.onKoreanTtsStatus(koreanTtsModel, koreanTtsStatus)
  }

  val meloTtsModel = remember { modelManagerViewModel.getModelByName(MELO_TTS_MODEL_NAME) }
  val meloTtsStatus = meloTtsModel?.let { modelManagerUiState.modelDownloadStatus[it.name] }
  LaunchedEffect(meloTtsModel, meloTtsStatus?.status, meloTtsStatus?.receivedBytes) {
    viewModel.onMeloTtsStatus(meloTtsModel, meloTtsStatus)
  }

  val neuralSttModel = remember { modelManagerViewModel.getModelByName(NEURAL_STT_MODEL_NAME) }
  val neuralSttStatus = neuralSttModel?.let { modelManagerUiState.modelDownloadStatus[it.name] }
  LaunchedEffect(neuralSttModel, neuralSttStatus?.status, neuralSttStatus?.receivedBytes) {
    viewModel.onNeuralSttStatus(neuralSttModel, neuralSttStatus)
  }

  val whisperSttModel = remember { modelManagerViewModel.getModelByName(WHISPER_KO_STT_MODEL_NAME) }
  val whisperSttStatus = whisperSttModel?.let { modelManagerUiState.modelDownloadStatus[it.name] }
  LaunchedEffect(whisperSttModel, whisperSttStatus?.status, whisperSttStatus?.receivedBytes) {
    viewModel.onWhisperSttStatus(whisperSttModel, whisperSttStatus)
  }
}
