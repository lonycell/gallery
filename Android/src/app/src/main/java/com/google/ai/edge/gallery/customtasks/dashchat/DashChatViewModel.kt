/*
 * Copyright 2026 Google LLC
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

package com.google.ai.edge.gallery.customtasks.dashchat

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.ai.edge.gallery.common.LOCAL_URL_BASE
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Lifecycle stage of preparing the Dash Chat site. */
enum class DashChatStage {
  /** Resolving whether a site is already installed. */
  LOADING,
  /** Downloading + extracting the site zip. */
  DOWNLOADING,
  /** A site is ready to browse ([DashChatUiState.url] points at it). */
  READY,
  /** Download/extraction failed; the user can retry or fall back to the bundled sample. */
  ERROR,
}

data class DashChatUiState(
  val stage: DashChatStage = DashChatStage.LOADING,
  /** 0..100 while downloading, or -1 when unknown. */
  val percent: Int = -1,
  val error: String = "",
  /** The url the WebView should load once [stage] is [DashChatStage.READY]. */
  val url: String = "",
)

/**
 * Owns the Dash Chat site download/extract lifecycle (model-like): on first open it downloads the
 * hosted web build and, until then (or on failure), the bundled sample under `assets/dashchat/` is
 * used so the page always works.
 */
@HiltViewModel
class DashChatViewModel
@Inject
constructor(@ApplicationContext private val context: Context) : ViewModel() {

  private val _uiState = MutableStateFlow(DashChatUiState())
  val uiState = _uiState.asStateFlow()

  private val bundledUrl = "$LOCAL_URL_BASE/assets/dashchat/index.html"

  /** Resolves the initial state: load an installed site, or download it on first visit. */
  fun prepare() {
    if (_uiState.value.stage == DashChatStage.DOWNLOADING) return
    if (DashChatSite.isInstalled(context)) {
      _uiState.update {
        it.copy(stage = DashChatStage.READY, url = DashChatSite.indexUrl(context), error = "")
      }
    } else {
      startDownload()
    }
  }

  /** Downloads + extracts the hosted site, then points the WebView at it. */
  fun startDownload() {
    _uiState.update { it.copy(stage = DashChatStage.DOWNLOADING, percent = -1, error = "") }
    viewModelScope.launch {
      val error =
        withContext(Dispatchers.IO) {
          DashChatSite.downloadAndInstall(context) { pct ->
            _uiState.update { it.copy(percent = pct) }
          }
        }
      if (error == null) {
        _uiState.update {
          it.copy(stage = DashChatStage.READY, url = DashChatSite.indexUrl(context), error = "")
        }
      } else {
        _uiState.update { it.copy(stage = DashChatStage.ERROR, error = error) }
      }
    }
  }

  /** Falls back to the bundled sample site (works offline, no download). */
  fun useBundled() {
    _uiState.update { it.copy(stage = DashChatStage.READY, url = bundledUrl, error = "") }
  }
}
