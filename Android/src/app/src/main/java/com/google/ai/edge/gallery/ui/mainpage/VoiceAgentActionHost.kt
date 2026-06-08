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

package com.google.ai.edge.gallery.ui.mainpage

import android.webkit.ConsoleMessage
import android.webkit.WebView
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.google.ai.edge.gallery.common.AskInfoAgentAction
import com.google.ai.edge.gallery.common.AskMcpToolCallPermissionAction
import com.google.ai.edge.gallery.common.CallJsAgentAction
import com.google.ai.edge.gallery.common.RequestPermissionAgentAction
import com.google.ai.edge.gallery.common.SkillProgressAgentAction
import com.google.ai.edge.gallery.customtasks.agentchat.AgentTools
import com.google.ai.edge.gallery.customtasks.agentchat.ChatWebViewClient
import com.google.ai.edge.gallery.customtasks.agentchat.ChatWebViewJavascriptInterface
import com.google.ai.edge.gallery.customtasks.agentchat.SecretEditorDialog
import com.google.ai.edge.gallery.customtasks.voiceassistant.VoiceAssistantViewModel
import com.google.ai.edge.gallery.ui.common.GalleryWebView
import com.google.ai.edge.gallery.ui.common.chat.LogMessage
import com.google.ai.edge.gallery.ui.common.chat.LogMessageLevel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import org.json.JSONObject

/**
 * Headless host that gives the main voice chat the SAME agent capabilities as the Agent Chat screen:
 * it drains the shared [AgentTools] action channel and drives everything that needs a Compose /
 * Activity surface — JS-skill execution (via an offscreen [GalleryWebView]), the secret/ask-info
 * dialog, runtime permission requests and the MCP tool-call permission prompt. Progress steps and
 * console logs are forwarded to the [VoiceAssistantViewModel], which attaches them to the current
 * reply so they render in the chat's progress panel.
 *
 * This renders an invisible 1.dp WebView (only used to run skill JavaScript) plus the ask-info
 * dialog; the MCP permission dialog and the on-screen image/webview results live in the chat UI.
 */
@Composable
fun VoiceAgentActionHost(
  agentTools: AgentTools,
  viewModel: VoiceAssistantViewModel,
) {
  val context = LocalContext.current
  val scope = rememberCoroutineScope()

  var webViewRef: WebView? by remember { mutableStateOf(null) }
  val jsInterface = remember { ChatWebViewJavascriptInterface() }
  val webViewClient = remember { ChatWebViewClient(context = context) }

  // Ask-info (secret / free-text) dialog state.
  var askInfoAction by remember { mutableStateOf<AskInfoAgentAction?>(null) }
  var askInfoValue by remember { mutableStateOf("") }

  // Runtime Android permission request flow (e.g. read calendar for a skill/intent).
  var pendingPermission by remember { mutableStateOf<RequestPermissionAgentAction?>(null) }
  val permissionLauncher =
    rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
      pendingPermission?.result?.complete(granted)
      pendingPermission = null
    }

  LaunchedEffect(agentTools.actionChannel) {
    for (action in agentTools.actionChannel) {
      when (action) {
        is SkillProgressAgentAction ->
          viewModel.appendToolStep(
            title = action.label,
            inProgress = action.inProgress,
            addItemTitle = action.addItemTitle,
            addItemDescription = action.addItemDescription,
          )
        is AskMcpToolCallPermissionAction -> viewModel.requestMcpPermission(action)
        is AskInfoAgentAction -> {
          askInfoValue = ""
          askInfoAction = action
        }
        is RequestPermissionAgentAction -> {
          pendingPermission = action
          permissionLauncher.launch(action.permission)
        }
        is CallJsAgentAction ->
          runJsSkill(action = action, webView = webViewRef, jsInterface = jsInterface,
            webViewClient = webViewClient, scope = scope)
        else -> {}
      }
    }
  }

  // Offscreen WebView used only to execute skill JavaScript (results come back via the JS interface).
  Box(modifier = Modifier.size(1.dp)) {
    GalleryWebView(
      modifier = Modifier.size(1.dp),
      onWebViewCreated = { webView ->
        webViewRef = webView
        webView.addJavascriptInterface(jsInterface, "AiEdgeGallery")
      },
      customWebViewClient = webViewClient,
      onConsoleMessage = { consoleMessage ->
        consoleMessage?.let { cm ->
          viewModel.appendToolLog(
            LogMessage(
              level =
                when (cm.messageLevel()) {
                  ConsoleMessage.MessageLevel.ERROR -> LogMessageLevel.Error
                  ConsoleMessage.MessageLevel.WARNING -> LogMessageLevel.Warning
                  else -> LogMessageLevel.Info
                },
              source = cm.sourceId() ?: "",
              lineNumber = cm.lineNumber(),
              message = cm.message() ?: "",
            )
          )
        }
      },
    )
  }

  askInfoAction?.let { action ->
    SecretEditorDialog(
      title = action.dialogTitle,
      fieldLabel = action.fieldLabel,
      value = askInfoValue,
      onValueChange = { askInfoValue = it },
      onDone = {
        action.result.complete(askInfoValue)
        askInfoAction = null
      },
      onDismiss = {
        action.result.complete("")
        askInfoAction = null
      },
    )
  }
}

/**
 * Runs a JS skill in [webView]: loads its url, waits for the page, then evaluates the skill entry
 * point. The result is delivered asynchronously via the JS interface's `onResultReady`. A 60s
 * watchdog completes the deferred with an error so inference never hangs. Mirrors the Agent Chat
 * screen's JS execution.
 */
private fun runJsSkill(
  action: CallJsAgentAction,
  webView: WebView?,
  jsInterface: ChatWebViewJavascriptInterface,
  webViewClient: ChatWebViewClient,
  scope: CoroutineScope,
) {
  if (webView == null) {
    action.result.complete("{\"error\":\"WebView not ready\",\"status\":\"failed\"}")
    return
  }
  scope.launch {
    // Watchdog so a stuck skill never hangs the chat / tool call.
    launch {
      delay(60_000L)
      if (!action.result.isCompleted) {
        action.result.complete(
          "{\"error\": \"Skill execution timed out. Please check network connection.\"}"
        )
      }
    }
    try {
      // Wait for the skill page to finish loading.
      suspendCancellableCoroutine<Unit> { continuation ->
        webViewClient.setPageLoadListener {
          webViewClient.setPageLoadListener(null)
          if (continuation.isActive) continuation.resume(Unit)
        }
        webView.loadUrl(action.url)
      }
      // Deliver the JS result back to the awaiting tool call.
      jsInterface.onResultListener = { result -> action.result.complete(result) }
      val safeData = JSONObject.quote(action.data)
      val safeSecret = JSONObject.quote(action.secret)
      val script =
        """
        (async function() {
            var startTs = Date.now();
            while(true) {
              if (typeof ai_edge_gallery_get_result === 'function') {
                break;
              }
              await new Promise(resolve=>{ setTimeout(resolve, 100) });
              if (Date.now() - startTs > 10000) { break; }
            }
            var result = await ai_edge_gallery_get_result($safeData, $safeSecret);
            AiEdgeGallery.onResultReady(result);
        })()
        """
          .trimIndent()
      webView.evaluateJavascript(script, null)
    } catch (e: Exception) {
      if (!action.result.isCompleted) {
        action.result.completeExceptionally(e)
      }
    }
  }
}
