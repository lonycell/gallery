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
package com.google.ai.edge.gallery.customtasks.exampleagent

import android.content.Context
import android.util.Log
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.runtime.Composable
import com.google.ai.edge.gallery.customtasks.common.CustomTask
import com.google.ai.edge.gallery.customtasks.common.CustomTaskData
import com.google.ai.edge.gallery.data.Category
import com.google.ai.edge.gallery.data.Model
import com.google.ai.edge.gallery.data.Task
import com.google.ai.edge.gallery.ui.llmchat.LlmChatModelHelper
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.tool
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

private const val TAG = "AGExampleAgentTask"

/** The task id of the example agent. Reused by the model manager to share the chat LLMs. */
const val EXAMPLE_AGENT_TASK_ID = "example_agent"

/**
 * TEMPLATE: a custom task ("agent") that connects an on-device LLM to local function-calling tools.
 *
 * This is the end-to-end template for wiring tools/skills/MCP into your own feature. It shows the
 * three pieces you need:
 * 1. A [Task] (this file) — the home-screen tile and the place where the model is initialized.
 * 2. A [ToolSet] (see [ExampleAgentTools]) — the functions the model can call.
 * 3. A Hilt module ([ExampleAgentModule]) — registers the task with the app.
 *
 * Model handling: this task ships with an empty [models][Task.models] list. Like the built-in chat
 * task, the model manager fills it with the same downloadable LLMs offered for chat, so the user can
 * download and switch between them with the standard model selector. (See
 * `ModelManagerViewModel.loadModelAllowlist`; built-in LLM tasks like chat/agent/mobile-actions use
 * the same approach.) Tip: function calling works best on larger or function-calling-tuned models.
 *
 * Tools vs skills vs MCP — pick what you need:
 * - Local tools (this template): annotate Kotlin functions with `@Tool`; lowest effort, fully
 *   in-process. Great for device actions, calculations, repository lookups.
 * - Skills: reusable markdown/JS instruction bundles managed by `SkillManagerViewModel`. Advertise
 *   the selected ones in the system prompt and expose the `loadSkill` tool (see
 *   `customtasks/agentchat/AgentTools`). Good for prompt-engineered, user-shareable behaviors.
 * - MCP: connect external Model Context Protocol servers via `McpManagerViewModel`; expose a
 *   `runMcpTool` tool and inject the tool list into the system prompt (see `AgentTools`). Good for
 *   reusing an existing ecosystem of remote tools.
 *
 * You can combine all three by exposing several tools at once:
 * `tools = listOf(tool(ExampleAgentTools(...)), tool(agentTools))`. The Voice Assistant
 * (`customtasks/voiceassistant`) is a worked example that integrates skills + MCP this way; mirror
 * it when you need the full set.
 */
class ExampleAgentTask : CustomTask {

  // The functions the model can call. The onToolCalled callback is a hook for progress/analytics.
  private val tools = ExampleAgentTools(onToolCalled = { Log.d(TAG, "Tool: $it") })

  override val task: Task =
    Task(
      id = EXAMPLE_AGENT_TASK_ID,
      label = "Example Agent",
      // Reuse a built-in category, or define your own CategoryInfo(id = ..., label = ...).
      category = Category.EXPERIMENTAL,
      icon = Icons.Outlined.Hub,
      description =
        "A template task that connects an on-device LLM to local function-calling tools " +
          "(date/time, calculator, word count). Use it as a starting point for your own tools, " +
          "skills, agents, and MCP integrations.",
      shortDescription = "Tool-calling agent template",
      docUrl =
        "https://github.com/google-ai-edge/gallery/blob/main/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/exampleagent/README.md",
      sourceCodeUrl =
        "https://github.com/google-ai-edge/gallery/blob/main/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/exampleagent",
      experimental = true,
      // How this task gets a model, two options:
      // (a) modelNames (used here): the model manager looks up these exact allowlist model names and
      //     attaches them — fully self-contained, no core changes. Keep names in sync with the
      //     allowlist (model_allowlist.json / model_allowlists/*.json).
      // (b) Share the chat LLMs: leave models empty and add this task id where llm_chat models are
      //     distributed in ModelManagerViewModel.loadModelAllowlist (this is what the Voice
      //     Assistant does, giving the full Gemma/Qwen switcher).
      models = mutableListOf(),
      modelNames = listOf("Gemma3-1B-IT"),
    )

  override fun initializeModelFn(
    context: Context,
    coroutineScope: CoroutineScope,
    model: Model,
    systemInstruction: Contents?,
    onDone: (error: String) -> Unit,
  ) {
    coroutineScope.launch(Dispatchers.Default) {
      // A short system prompt nudges the model to actually use the tools. For skills/MCP, append
      // the advertised skill/tool lists here as well (see ExampleAgentTask's KDoc and AgentTools).
      val systemPrompt =
        "You are a helpful assistant with access to tools. When a request needs the current time, " +
          "arithmetic, or a word count, CALL THE MATCHING TOOL instead of guessing. Keep replies " +
          "short."
      val instruction: Contents = Contents.of(listOf(Content.Text(systemPrompt)))

      LlmChatModelHelper.initialize(
        context = context,
        model = model,
        taskId = task.id,
        supportImage = false,
        supportAudio = false,
        onDone = onDone,
        systemInstruction = instruction,
        // The key line: hand your ToolSet(s) to the runtime. Add tool(agentTools) here too to also
        // enable skills + MCP.
        tools = listOf(tool(tools)),
        // Recommended when tools are present: keeps the model's tool-call output well-formed.
        enableConversationConstrainedDecoding = true,
      )
    }
  }

  override fun cleanUpModelFn(
    context: Context,
    coroutineScope: CoroutineScope,
    model: Model,
    onDone: () -> Unit,
  ) {
    LlmChatModelHelper.cleanUp(model = model, onDone = onDone)
  }

  @Composable
  override fun MainScreen(data: Any) {
    val customTaskData = data as CustomTaskData
    ExampleAgentScreen(
      task = task,
      modelManagerViewModel = customTaskData.modelManagerViewModel,
    )
  }
}
