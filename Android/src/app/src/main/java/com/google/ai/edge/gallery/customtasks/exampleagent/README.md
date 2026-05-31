# Agent Tools / Skills / MCP — Integration Template

This package is a **copy-paste template** for adding new capabilities to an on-device LLM in this
app: local **tools** (function calling), **skills** (instruction bundles), full **agents** (custom
tasks), and **MCP** (Model Context Protocol) servers.

It is intentionally self-contained and **disabled by default** (the Hilt provider in
`ExampleAgentModule` is commented out) so it doesn't appear in the app until you opt in.

## Files

| File | Role |
| --- | --- |
| `ExampleAgentTools.kt` | A `ToolSet` of `@Tool` functions (date/time, calculator, word count). **Start here for tools.** |
| `ExampleAgentTask.kt` | A `CustomTask` ("agent") that initializes an LLM **with the tools** and hosts the screen. |
| `ExampleAgentViewModel.kt` | Runs streaming inference via `model.runtimeHelper.runInference(...)`. Tool calls happen automatically inside inference. |
| `ExampleAgentScreen.kt` | Minimal chat UI. |
| `ExampleAgentModule.kt` | Hilt registration (`@Provides @IntoSet`). **Commented out** — uncomment to enable. |
| `example-skill.md` | Example of the **skill** file format (docs only). |

## The big picture

```
User text ──► LLM (runInference) ──► model asks to call a tool
                                   ──► LiteRT-LM runtime invokes your @Tool function
                                   ──► tool result fed back ──► LLM continues ──► reply
```

You only declare the tools and hand them to the runtime at init time. You do **not** call the tools
yourself; the runtime does, during generation.

---

## 1. Add a local tool (lowest effort)

In a `ToolSet`, annotate a Kotlin function:

```kotlin
class MyTools : ToolSet {
  @Tool(description = "Returns the current local date and time.")
  fun getCurrentDateTime(): Map<String, String> =
    mapOf("result" to LocalDateTime.now().toString(), "status" to "succeeded")

  @Tool(description = "Adds two numbers.")
  fun add(
    @ToolParam(description = "first operand") a: Double,
    @ToolParam(description = "second operand") b: Double,
  ): Map<String, Any> = mapOf("result" to a + b, "status" to "succeeded")
}
```

Rules of thumb:
- The `@Tool` **description** is how the model decides *when* to call it. Be specific.
- Use simple param types (String/Int/Double/Boolean), each with a `@ToolParam` description.
- Return a `Map` including a `status` and a `result`/`error` so the model can reason about it.
- Keep it quick; do heavy work off-thread.

Hand it to the model at init time (see `ExampleAgentTask.initializeModelFn`):

```kotlin
LlmChatModelHelper.initialize(
  context = context, model = model, taskId = task.id,
  onDone = onDone,
  systemInstruction = Contents.of(listOf(Content.Text(systemPrompt))),
  tools = listOf(tool(MyTools())),            // <-- the key line
  enableConversationConstrainedDecoding = true, // recommended when tools are present
)
```

## 2. Turn it into an agent (custom task)

`ExampleAgentTask` is the template. A `CustomTask` needs:
- a `task: Task` (label/category/icon/description shown on the home screen),
- `initializeModelFn` (init the LLM **with your tools**),
- `cleanUpModelFn` (`LlmChatModelHelper.cleanUp`),
- `MainScreen` (your Compose UI).

**Getting a model.** Two options:
- **`modelNames`** (used in the template): list exact allowlist model names; the model manager
  attaches them automatically — no core changes. Keep names in sync with
  `model_allowlist.json` / `model_allowlists/*.json`.
- **Share the chat LLMs**: leave `models` empty and add your task id where `llm_chat` models are
  distributed in `ModelManagerViewModel.loadModelAllowlist`. This gives the full Gemma/Qwen
  switcher. The Voice Assistant (`customtasks/voiceassistant`) does exactly this.

**Register it.** Add a Hilt module (see `ExampleAgentModule`):

```kotlin
@Module @InstallIn(SingletonComponent::class)
internal object MyModule {
  @Provides @IntoSet fun provideTask(): CustomTask = MyAgentTask()
}
```

`@IntoSet` adds the task to the app's `Set<CustomTask>`, which the home screen discovers
automatically. To enable this template, just uncomment the provider in `ExampleAgentModule.kt`.

## 3. Add skills

A **skill** is a shareable instruction bundle (markdown front-matter + body; optionally a JS
script). See `example-skill.md`. Skills are managed at runtime by the user, not compiled in.

To support skills in an agent (see `customtasks/agentchat/AgentTools` and the Voice Assistant):
1. Obtain a `SkillManagerViewModel` (via `hiltViewModel()` in your screen) and assign it onto a
   shared `AgentTools` instance.
2. At init: `agentTools.skillManagerViewModel.loadSkills()` then advertise the selected skills in
   the system prompt using `getSelectedSkillsNamesAndDescriptions()`.
3. Pass `tools = listOf(tool(agentTools))` so the model can call `loadSkill` to read a skill's
   instructions and follow them.
4. Let the user add/select skills via `SkillManagerBottomSheet`.

Note: plain markdown/instruction skills (`loadSkill`) work anywhere. JS-script skills and
secret-requiring skills emit UI actions (`CallJsAgentAction` / `AskInfoAgentAction`) that your
screen must handle (a WebView / input dialog), or you must complete their deferred result so the
call doesn't hang. The Voice Assistant resolves those as "unsupported" because it has no such UI.

## 4. Connect MCP servers

MCP lets the model call tools hosted by external Model Context Protocol servers.

To support MCP (see `customtasks/agentchat/AgentTools.runMcpTool` and the Voice Assistant):
1. Obtain a `McpManagerViewModel` (`hiltViewModel()`), assign it onto a shared `AgentTools`.
2. At init: `agentTools.mcpManagerViewModel.loadMcpServers()`, then inject the available tools into
   the system prompt with `getToolsPrompt()`.
3. Pass `tool(agentTools)` so the model can call the `runMcpTool` function.
4. **Handle the permission action**: `runMcpTool` emits `AskMcpToolCallPermissionAction` whose
   `result: CompletableDeferred<PermissionResult>` you MUST complete (show
   `McpToolCallPermissionDialog`) — otherwise the tool call blocks forever.
5. Let the user connect/manage servers via `McpManagerBottomSheet`.

## 5. Combine everything

Expose several tool sets at once:

```kotlin
tools = listOf(tool(MyTools()), tool(agentTools)) // local tools + skills + MCP
```

The **Voice Assistant** (`customtasks/voiceassistant`) is the worked, production example that wires
local speech I/O + the chat LLMs + skills + MCP with connect-on-demand UI and a permission dialog.
Read it alongside this template when you need the full integration.

## Tips & caveats

- **Model matters.** Function-calling reliability varies a lot by model. Larger or
  function-calling-tuned models (e.g. Gemma 4, or Mobile Actions' Function Gemma) call tools far
  more reliably than tiny chat models.
- `enableConversationConstrainedDecoding = true` keeps tool-call output well-formed; use it when
  tools are present.
- Return structured errors from tools instead of throwing.
- The home-screen category is set per task (`Category.*` or a custom `CategoryInfo`).
