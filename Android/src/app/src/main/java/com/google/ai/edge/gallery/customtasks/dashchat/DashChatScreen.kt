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

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.webkit.WebResourceRequest
import android.webkit.WebView
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.google.ai.edge.gallery.common.LOCAL_URL_BASE
import com.google.ai.edge.gallery.ui.common.BaseGalleryWebViewClient
import com.google.ai.edge.gallery.ui.common.GalleryWebView
import com.google.ai.edge.gallery.ui.modelmanager.ModelManagerViewModel

/** Matches the bundled site background so the status-bar area blends into a standalone full screen. */
private val DashChatBackground = Color(0xFF140A2B)

/**
 * "대쉬 챗(Dash Chat)" — browses a downloaded web build locally and lets that page talk to the app's
 * on-device LLM (shared conversation context) through [DashChatLlmBridge]. Until the hosted site is
 * downloaded, a bundled sample under `assets/dashchat/` is shown.
 */
/**
 * The app's registered deep-link scheme (see AndroidManifest.xml). The hosted site issues links like
 * `com.google.ai.edge.gallery://characters` / `://mainpage` (see web `src/lib/host.ts`) which we
 * resolve against the nav graph's registered deep links instead of loading in the WebView.
 */
private const val DEEPLINK_SCHEME = "com.google.ai.edge.gallery"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashChatScreen(
  modelManagerViewModel: ModelManagerViewModel,
  navigateUp: () -> Unit,
  /** Resolves an in-app deep link the page requested (e.g. `…://characters`, `…://mainpage`). */
  onDeepLink: (Uri) -> Unit = {},
  viewModel: DashChatViewModel = hiltViewModel(),
) {
  val context = LocalContext.current
  val uiState by viewModel.uiState.collectAsState()
  val scope = rememberCoroutineScope()

  var webViewRef: WebView? by remember { mutableStateOf(null) }

  // The bridge runs inference on the app's currently selected, initialized model (shared context).
  val bridge =
    remember {
      DashChatLlmBridge(
        activeModel = {
          modelManagerViewModel.uiState.value.selectedModel.takeIf { it.name.isNotEmpty() }
        },
        isModelReady = { model -> modelManagerViewModel.uiState.value.isModelInitialized(model) },
        scope = scope,
        webViewProvider = { webViewRef },
      )
    }

  // Speech bridges so the hosted chat can dictate / speak through the same system engines the native
  // chat uses (window.AiEdgeStt / window.AiEdgeTts).
  val sttBridge = remember { DashChatSttBridge(context, scope, webViewProvider = { webViewRef }) }
  val ttsBridge = remember { DashChatTtsBridge(context, webViewProvider = { webViewRef }) }

  // Only browse locally-served content (bundled or extracted site); block external navigation, but
  // honor the page's app deep links by routing them into the app's navigation.
  val webViewClient = remember { DashChatWebViewClient(context, onDeepLink) }

  // The chat page's mic uses the native SpeechRecognizer, which needs RECORD_AUDIO. Ask up front so
  // tapping the mic just works.
  val micPermissionLauncher =
    rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
  LaunchedEffect(Unit) {
    if (
      ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) !=
        PackageManager.PERMISSION_GRANTED
    ) {
      micPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
    }
  }

  LaunchedEffect(Unit) { viewModel.prepare() }
  DisposableEffect(Unit) {
    onDispose {
      bridge.stop()
      sttBridge.stop()
      ttsBridge.shutdown()
    }
  }

  // While a site is shown, Back navigates the web history first (cards → chat), then leaves.
  BackHandler {
    val wv = webViewRef
    if (wv != null && wv.canGoBack()) wv.goBack() else navigateUp()
  }

  // Standalone, full-screen experience (like the main chat window): no app bar / back chrome — the
  // web content fills the screen and the system Back gesture (handled above) leaves it. The dark
  // background matches the site so the status-bar area blends in.
  Box(modifier = Modifier.fillMaxSize().background(DashChatBackground)) {
    Box(
      modifier = Modifier.fillMaxSize().systemBarsPadding(),
      contentAlignment = Alignment.Center,
    ) {
      when (uiState.stage) {
        DashChatStage.LOADING ->
          CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)

        DashChatStage.DOWNLOADING ->
          Column(
            modifier = Modifier.fillMaxWidth().padding(36.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
          ) {
            Text("대쉬 챗 사이트를 받는 중이에요…", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(16.dp))
            if (uiState.percent in 0..100) {
              LinearProgressIndicator(
                progress = { uiState.percent / 100f },
                modifier = Modifier.fillMaxWidth(),
              )
              Spacer(modifier = Modifier.height(6.dp))
              Text("${uiState.percent}%", style = MaterialTheme.typography.bodySmall)
            } else {
              LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            }
            Spacer(modifier = Modifier.height(12.dp))
            TextButton(onClick = { viewModel.useBundled() }) { Text("샘플로 먼저 둘러보기") }
          }

        DashChatStage.ERROR ->
          Column(
            modifier = Modifier.fillMaxWidth().padding(36.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
          ) {
            Text(
              "사이트를 받지 못했어요.",
              style = MaterialTheme.typography.titleMedium,
              textAlign = TextAlign.Center,
            )
            if (uiState.error.isNotEmpty()) {
              Spacer(modifier = Modifier.height(6.dp))
              Text(
                uiState.error,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
              )
            }
            Spacer(modifier = Modifier.height(16.dp))
            Button(onClick = { viewModel.startDownload() }) { Text("다시 시도") }
            Spacer(modifier = Modifier.height(8.dp))
            TextButton(onClick = { viewModel.useBundled() }) { Text("샘플로 둘러보기") }
          }

        DashChatStage.READY ->
          // key on the url so switching bundled → downloaded reloads the WebView.
          key(uiState.url) {
            val url = uiState.url
            GalleryWebView(
              modifier = Modifier.fillMaxSize(),
              customWebViewClient = webViewClient,
              allowRequestPermission = true,
              onWebViewCreated = { webView ->
                webViewRef = webView
                // Register the bridges BEFORE loading so the page's scripts see the engines on
                // window. (GalleryWebView's factory invokes onWebViewCreated after any initialUrl
                // load, so we load here ourselves instead of passing initialUrl.)
                webView.addJavascriptInterface(bridge, "AiEdgeLlm")
                webView.addJavascriptInterface(sttBridge, "AiEdgeStt")
                webView.addJavascriptInterface(ttsBridge, "AiEdgeTts")
                webView.loadUrl(url)
              },
            )
          }
      }
    }
  }
}

/**
 * Restricts the Dash Chat WebView to locally-served content; external links are not followed.
 * Recognizes the app's `com.google.ai.edge.gallery://…` deep links emitted by the page and hands
 * them to [onDeepLink] to resolve against the nav graph, instead of trying to load them.
 */
private class DashChatWebViewClient(
  context: Context,
  private val onDeepLink: (Uri) -> Unit,
) : BaseGalleryWebViewClient(context) {
  override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
    val uri = request?.url ?: return false
    // In-app deep links from the page (see web `src/lib/host.ts`).
    if (uri.scheme == DEEPLINK_SCHEME) {
      onDeepLink(uri)
      return true
    }
    // Allow only our local origin (bundled assets + extracted site). Block everything else.
    return !uri.toString().startsWith(LOCAL_URL_BASE)
  }
}
