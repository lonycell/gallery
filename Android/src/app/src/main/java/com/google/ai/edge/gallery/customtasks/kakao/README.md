# KakaoTalk send — a tool + agent + skill example

A concrete, worked example (built on the `customtasks/exampleagent` template) that lets the Voice
Assistant send a KakaoTalk message from what the user says — e.g. *"민수에게 30분 늦는다고 카톡
보내줘"*.

It demonstrates the three layers and how they connect.

## The three pieces

| Layer | File | What it does |
| --- | --- | --- |
| **Tool** | `KakaoShareTools.kt` | A `@Tool sendKakaoMessage(recipient, message)` that opens KakaoTalk's share screen with the composed text. |
| **Agent** | wired into `customtasks/voiceassistant/VoiceAssistantTask.kt` | The Voice Assistant always offers the Kakao tool and tells the model how/when to use it. |
| **Skill** | `kakao-messenger-skill.md` | Prompt-engineering layer: confirm recipient + content, be polite, never send without confirmation. |

## How it's wired (the important part)

In `VoiceAssistantTask.initializeModelFn`, the Kakao tool is added to the tool list given to the
LLM, and the system prompt gets a short instruction:

```kotlin
val toolSets = mutableListOf<ToolProvider>()
toolSets.add(tool(KakaoShareTools(context = context.applicationContext))) // always available
if (hasTools || hasSkills) toolSets.add(tool(agentTools))                  // skills + MCP

LlmChatModelHelper.initialize(
  ...,
  systemInstruction = instruction,   // includes "카톡 보내달라고 하면 sendKakaoMessage 호출, 보내기 전 확인"
  tools = toolSets,
  enableConversationConstrainedDecoding = true,
)
```

That's the whole connection: declare the tool, hand it to the runtime, and tell the model when to
use it. The runtime calls `sendKakaoMessage` automatically when the model decides to.

Manifest: `AndroidManifest.xml` adds `<queries><package android:name="com.kakao.talk"/></queries>`
so the explicit share intent can resolve KakaoTalk on Android 11+.

## Why the share intent (not auto-send)

KakaoTalk does **not** let an app silently send to an arbitrary friend (the friend-message API needs
friend+message permissions and business review; "send to me" only targets yourself). So this example
uses Android's `ACTION_SEND` share intent targeted at `com.kakao.talk`:

- No Kakao SDK, no login, no special permission.
- KakaoTalk shows its own recipient picker and the **user confirms sending** — the right safety
  model for a voice assistant doing an irreversible outbound action.

The tool returns `status = "shared"` (not "sent") to reflect that the user still confirms in
KakaoTalk.

## Flow

```
"민수에게 카톡으로 늦는다고 보내줘"
  → STT → LLM (with kakao-messenger skill + sendKakaoMessage tool)
  → LLM confirms: "민수님에게 '30분 늦어요'라고 보낼게요. 괜찮을까요?"  (skill behavior)
  → user: "응"
  → LLM calls sendKakaoMessage("민수", "30분 늦어요")
  → KakaoTalk opens with the text → user picks 민수, taps send
```

## Going further (optional, heavier)

If you need true auto-send, switch the tool body to the **Kakao SDK**:
- "Send to me" (`talk/memo/default/send`) — OAuth login only; sends to yourself.
- Friend message (`talk/friends/message/send`) — friend+message permissions and review; recipient
  must allow the app.
Add the Kakao SDK dependency + app key, run the OAuth flow, and keep the confirm-before-send step.
For automated sends, also add an explicit in-app confirmation dialog (reuse the Voice Assistant's
MCP permission-dialog pattern) since the KakaoTalk UI no longer gates the send.

## Reuse

`KakaoShareTools` is a plain `ToolSet`, so you can add it to any agent:
`tools = listOf(tool(KakaoShareTools(context)), ...)`. See `customtasks/exampleagent/README.md` for
the general tool/skill/agent/MCP guide.
