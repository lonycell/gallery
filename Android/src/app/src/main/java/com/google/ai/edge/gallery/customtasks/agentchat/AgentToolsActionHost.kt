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

package com.google.ai.edge.gallery.customtasks.agentchat

import android.os.Bundle
import android.util.Log
import android.webkit.ConsoleMessage
import android.webkit.WebView
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import com.google.ai.edge.gallery.GalleryEvent
import com.google.ai.edge.gallery.common.AskInfoAgentAction
import com.google.ai.edge.gallery.common.AskMcpToolCallPermissionAction
import com.google.ai.edge.gallery.common.CallJsAgentAction
import com.google.ai.edge.gallery.common.LOCAL_URL_BASE
import com.google.ai.edge.gallery.common.PermissionResult
import com.google.ai.edge.gallery.common.RequestPermissionAgentAction
import com.google.ai.edge.gallery.common.SkillProgressAgentAction
import com.google.ai.edge.gallery.firebaseAnalytics
import com.google.ai.edge.gallery.ui.common.GalleryWebView
import com.google.ai.edge.gallery.ui.common.chat.LogMessage
import com.google.ai.edge.gallery.ui.common.chat.LogMessageLevel
import kotlin.coroutines.resume
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONObject

private const val TAG = "AGAgentToolsActionHost"
private val chatViewJavascriptInterface = ChatWebViewJavascriptInterface()

/**
 * Headless host that wires [AgentTools.actionChannel] to the full Agent-Skills UI surface: JS skill
 * WebView execution, secret prompts, Android runtime permissions, and MCP tool-call permission
 * dialogs. Shared by the main voice chat and Agent Skills screens.
 */
@Composable
fun AgentToolsActionHost(
  agentTools: AgentTools,
  taskId: String,
  skillManagerViewModel: SkillManagerViewModel,
  mcpManagerViewModel: McpManagerViewModel,
  onSkillProgress: (SkillProgressAgentAction) -> Unit,
  onLogMessage: (LogMessage) -> Unit = {},
  modifier: Modifier = Modifier,
) {
  val context = LocalContext.current
  val scope = rememberCoroutineScope()
  var webViewRef: WebView? by remember { mutableStateOf(null) }
  val chatWebViewClient = remember { ChatWebViewClient(context = context) }

  var showAskInfoDialog by remember { mutableStateOf(false) }
  var currentAskInfoAction by remember { mutableStateOf<AskInfoAgentAction?>(null) }
  var askInfoInputValue by remember { mutableStateOf("") }

  var currentMcpPermissionAction by remember {
    mutableStateOf<AskMcpToolCallPermissionAction?>(null)
  }

  var currentPermissionAction by remember { mutableStateOf<RequestPermissionAgentAction?>(null) }
  val permissionLauncher =
    rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
      currentPermissionAction?.result?.complete(granted)
      currentPermissionAction = null
    }

  LaunchedEffect(agentTools) {
    for (action in agentTools.actionChannel) {
      Log.d(TAG, "Handling action: $action")
      when (action) {
        is SkillProgressAgentAction -> onSkillProgress(action)
        is CallJsAgentAction -> {
          val skillName =
            if (action.url.contains("/skills/")) {
              action.url.substringAfter("/skills/").substringBefore("/")
            } else if (action.url.startsWith(LOCAL_URL_BASE + "/")) {
              action.url.substringAfter(LOCAL_URL_BASE + "/").substringBefore("/")
            } else {
              action.url
            }
          val skill = skillManagerViewModel.getSkill(name = skillName)
          val skillId = skill?.let { skillManagerViewModel.getSkillShortId(it) } ?: "xxxx"
          try {
            launch {
              delay(60_000L)
              if (!action.result.isCompleted) {
                Log.e(TAG, "JS Execution timed out, completing with error.")
                firebaseAnalytics?.logEvent(
                  GalleryEvent.SKILL_EXECUTION.id,
                  Bundle().apply {
                    putString("capability_name", taskId)
                    putString("skill_name", skillName)
                    putString("skill_id", skillId)
                    putBoolean("success", false)
                    putString("error_type", "timeout")
                  },
                )
                action.result.complete(
                  "{\"error\": \"Skill execution timed out. Please check network connection.\"}"
                )
              }
            }

            suspendCancellableCoroutine<Unit> { continuation ->
              chatWebViewClient.setPageLoadListener {
                chatWebViewClient.setPageLoadListener(null)
                continuation.resume(Unit)
              }
              Log.d(TAG, "Loading url: ${action.url}")
              webViewRef?.loadUrl(action.url)
            }

            chatViewJavascriptInterface.onResultListener = { result ->
              Log.d(TAG, "Got result:\n$result")
              action.result.complete(result)
              val isSuccess = !result.contains("\"error\":")
              val errorType = if (isSuccess) "" else "js_error"
              firebaseAnalytics?.logEvent(
                GalleryEvent.SKILL_EXECUTION.id,
                Bundle().apply {
                  putString("capability_name", taskId)
                  putString("skill_name", skillName)
                  putString("skill_id", skillId)
                  putBoolean("success", isSuccess)
                  putString("error_type", errorType)
                },
              )
            }

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
                    await new Promise(resolve=>{
                      setTimeout(resolve, 100)
                    });
                    if (Date.now() - startTs > 10000) {
                      break;
                    }
                  }
                  var result = await ai_edge_gallery_get_result($safeData, $safeSecret);
                  AiEdgeGallery.onResultReady(result);
              })()
              """
                .trimIndent()
            webViewRef?.evaluateJavascript(script, null)
          } catch (e: Exception) {
            firebaseAnalytics?.logEvent(
              GalleryEvent.SKILL_EXECUTION.id,
              Bundle().apply {
                putString("capability_name", taskId)
                putString("skill_name", skillName)
                putString("skill_id", skillId)
                putBoolean("success", false)
                putString("error_type", "exception")
              },
            )
            action.result.completeExceptionally(e)
          }
        }
        is AskInfoAgentAction -> {
          currentAskInfoAction = action
          askInfoInputValue = ""
          showAskInfoDialog = true
        }
        is RequestPermissionAgentAction -> {
          currentPermissionAction = action
          permissionLauncher.launch(action.permission)
        }
        is AskMcpToolCallPermissionAction -> {
          currentMcpPermissionAction = action
        }
      }
    }
  }

  GalleryWebView(
    modifier = modifier.size(300.dp),
    onWebViewCreated = { webView ->
      webViewRef = webView
      webView.addJavascriptInterface(chatViewJavascriptInterface, "AiEdgeGallery")
    },
    customWebViewClient = chatWebViewClient,
    onConsoleMessage = { consoleMessage ->
      consoleMessage?.let { curConsoleMessage ->
        val logMessage =
          LogMessage(
            level =
              when (curConsoleMessage.messageLevel()) {
                ConsoleMessage.MessageLevel.LOG -> LogMessageLevel.Info
                ConsoleMessage.MessageLevel.ERROR -> LogMessageLevel.Error
                ConsoleMessage.MessageLevel.WARNING -> LogMessageLevel.Warning
                else -> LogMessageLevel.Info
              },
            source = curConsoleMessage.sourceId(),
            lineNumber = curConsoleMessage.lineNumber(),
            message = curConsoleMessage.message(),
          )
        onLogMessage(logMessage)
      }
    },
  )

  if (showAskInfoDialog && currentAskInfoAction != null) {
    val action = currentAskInfoAction!!
    SecretEditorDialog(
      title = action.dialogTitle,
      fieldLabel = action.fieldLabel,
      value = askInfoInputValue,
      onValueChange = { askInfoInputValue = it },
      onDone = {
        action.result.complete(askInfoInputValue)
        showAskInfoDialog = false
        currentAskInfoAction = null
      },
      onDismiss = {
        action.result.complete("")
        showAskInfoDialog = false
        currentAskInfoAction = null
      },
    )
  }

  currentMcpPermissionAction?.let { action ->
    McpToolCallPermissionDialog(
      toolName = action.toolName,
      argument = action.argument,
      onResult = { result ->
        action.result.complete(result)
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
        currentMcpPermissionAction = null
      },
    )
  }
}
