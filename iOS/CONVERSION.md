# Android → iOS conversion map

This document records how the Android app (`../Android/src/app/src/main`) was
ported to this SwiftUI app. 235 Kotlin files → 229 Swift files (~33k LOC). The
folder structure mirrors the Kotlin packages; in almost all cases one `.kt`
became one `.swift` of the same base name.

## Package → folder
| Kotlin package | Swift folder |
|---|---|
| `com.google.ai.edge.gallery` (root) | `Gallery/` (GalleryApp, AppContainer, Analytics) |
| `common/` | `Common/` |
| `data/` | `Data/` |
| `proto/` (.proto) | `Proto/` (Codable structs) |
| `runtime/` | `Runtime/` |
| `notifications/` | `Notifications/` |
| `di/` | folded into `AppContainer.swift` |
| `customtasks/<x>/` | `CustomTasks/<X>/` |
| `ui/<x>/` | `UI/<X>/` |
| `character/` | `Character/` |

## Foundation (hand-ported for a stable contract)
- `Data/Types.swift` ← Accelerator; `Data/Consts.swift` ← Consts.kt
- `Data/Config.swift` / `ConfigValue.swift` ← Config.kt / ConfigValue.kt (full editor model + factories)
- `Data/Model.swift` ← Model.kt (reference class; getPath, config accessors, download status)
- `Data/Task.swift` ← Tasks.kt (Task, BuiltInTaskId, isLegacyTasks); `Categories.swift` ← Categories.kt
- `Data/ModelAllowlist.swift` ← ModelAllowlist.kt (`AllowedModel.toModel()`); `SkillAllowlist.swift`
- `Data/DataStoreRepository.swift` ← DataStoreRepository.kt (JSON-file backed, same blocking API)
- `Data/DownloadRepository.swift` ← DownloadRepository.kt (URLSession); `SystemPromptRepository.swift`; `AppBarAction.swift`
- `Proto/*` ← every `.proto` as Codable structs (Settings, ChatHistory, Mcp, Skill, Benchmark, ScheduledNotification)
- `UI/Theme/*` ← Color.kt, Type.kt, Theme.kt (GalleryColors + CustomColors via Environment), ThemeSettings.kt
- `UI/Common/Chat/ChatMessage.swift` ← ChatMessage.kt; `ChatViewModel.swift` ← ChatViewModel.kt (abstract base)
- `UI/ModelManager/ModelManagerViewModel.swift` ← ModelManagerViewModel.kt (central app state)
- `UI/Navigation/Router.swift` + `GalleryNavGraph.swift` ← GalleryNavGraph.kt
- `Runtime/LlmModelHelper.swift` ← LlmModelHelper.kt (protocol) + stub engine
- `CustomTasks/Common/*` ← CustomTask.kt, CustomTaskData.kt
- `Common/*` ← Types.kt, Utils.kt (+ FileSystem), ProjectConfig.kt, SystemPromptHelper.kt
- `Resources/Strings.swift` ← res/values/strings.xml (R.string → `Str.*`, plurals as funcs)

## Feature modules (converted by parallel agents, against the foundation)
- **Common UI** ← `ui/common/*` (MarkdownText, ModelPageAppBar, ModelPicker, ConfigDialog, ErrorDialog,
  EmptyState, TaskIcon, ColorUtils, …) + `ModelItem/`, `Tos/`, `TextAndVoiceInput/`
- **Chat UI** ← `ui/common/chat/*` (ChatView, ChatPanel, all MessageBody* renderers, input, history sheet, …)
- **Home / ModelManager / Benchmark** ← `ui/home/*`, `ui/modelmanager/*`, `ui/benchmark/*`
- **LLM Chat / Prompt Lab** ← `ui/llmchat/*`, `ui/llmsingleturn/*` (+ LlmChatModelHelper)
- **Agent Chat (Skills + MCP)** ← `customtasks/agentchat/*` (+ `websearch/`, `kakao/`)
- **Mobile Actions / Tiny Garden / Examples** ← `customtasks/mobileactions|tinygarden|exampleagent|examplecustomtask/*`
- **Speech (TTS/STT)** ← `customtasks/tts|stt|speech/*`
- **Voice Assistant / Main Page** ← `customtasks/voiceassistant/*`, `ui/mainpage/*` (the app's start screen)
- **Character / Subscription / Notifications** ← `character/*`, `ui/subscription/*`, `ui/notifications/*`

## Resources copied verbatim
- `res/font/nunito_*.ttf` → `Resources/Fonts/` (registered via Info.plist `UIAppFonts`)
- `assets/skills/` → `Resources/skills/`; `assets/tinygarden/` → `Resources/tinygarden/`
- `res/drawable/char_*.jpg`, `persona_hero.jpg` → `Assets.xcassets`
- `mipmap-*/ic_launcher.png` → `Assets.xcassets/AppIcon`
- `model_allowlist.json` → `Resources/` (bundled allowlist fallback)

## Intentional differences
- Android vector drawables (`R.drawable.*.xml`) → SF Symbols (closest match) in `TaskIcon`/icons.
- Manifest permissions → `Info.plist` usage descriptions + `Gallery.entitlements`.
- Proto/DataStore persistence → JSON files in Application Support (same data shapes).
- Build-not-required: native ML runtimes are stubbed behind protocols (see README "Native bridge points").

## Integration glue added during assembly
- `AppContainer` builds the repositories, sets `AppContainer.sharedLlmHelper`/`sharedDataStore`,
  registers all custom-task factories, wires `IntentHandler.notificationManager` and the
  `UNUserNotificationCenter` delegate, and constructs `ModelManagerViewModel`.
- `GalleryNavHost` wires the typed `Route`s to feature screens; MainPage/Settings/Characters
  share one `VoiceAssistantViewModel` + `CharacterViewModel`.
- De-duplicated types that two agents independently declared (`VoiceOption`, `FileSystem`,
  `AllowedSkill`, `SkillAllowlist`, `GalleryWebView`→`ChatGalleryWebView`, `PermissionResult`→
  `VAPermissionResult`, task-color helpers) — foundation definitions win.
