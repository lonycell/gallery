# 찐친 Ai — iOS

A faithful SwiftUI port of the Android **찐친 Ai** app (a Google AI Edge Gallery
fork) that lives in `../Android`. Same features, same architecture, same package
layout — re-expressed with SwiftUI + Swift instead of Jetpack Compose + Kotlin.

> Built with "no build" as a constraint: the goal is a high-fidelity, openable
> Xcode project whose structure, data models, view models, screens, navigation,
> theme and resources mirror the Android app 1:1. On-device ML runtimes that have
> no drop-in Swift package (LiteRT-LM, sherpa-onnx) are represented behind clean
> Swift abstractions with stub implementations — see "Native bridge points".

## Requirements
- Xcode 16+ (the project uses a synchronized file-system group, objectVersion 77)
- iOS 17.0+ (matches the README's "iOS 17 and up")
- Swift 5

## Open & run
- Open `Gallery.xcodeproj` and run the **찐친 Ai** scheme, **or**
- `cd iOS && xcodegen generate` (uses `project.yml`) then open the generated project.

App id `com.google.aiedge.gallery`, version 1.0.15 (33) — matching the Android
`applicationId` / `versionName` / `versionCode`.

## Project layout (mirrors the Kotlin packages)
```
Gallery/
  GalleryApp.swift            @main + GalleryApplication.onCreate   (MainActivity.kt / GalleryApplication.kt)
  AppContainer.swift          DI graph + custom-task registry        (di/AppModule.kt)
  Analytics.swift             event taxonomy                         (Analytics.kt)
  Common/                     shared types & helpers                 (common/*)
  Data/                       Task, Model, Config, repositories      (data/*)
  Proto/                      Codable mirrors of the .proto schemas  (proto/*)
  Runtime/                    LlmModelHelper protocol + stub         (runtime/*)
  Notifications/              UNUserNotificationCenter scheduling     (notifications/*)
  CustomTasks/                pluggable feature modules              (customtasks/*)
    Common/ AgentChat/ MobileActions/ TinyGarden/ Tts/ Stt/ Speech/
    VoiceAssistant/ ExampleAgent/ ExampleCustomTask/ Kakao/ WebSearch/
  UI/
    Theme/ Navigation/ Common/ (+ Common/Chat, ModelItem, Tos, TextAndVoiceInput)
    Home/ ModelManager/ Benchmark/ LlmChat/ LlmSingleTurn/ MainPage/
    Notifications/ Subscription/ Icon/
  Character/                  companion characters                   (character/*)
  Resources/                  fonts, skills/, tinygarden/, assets, strings, model_allowlist.json
```
See `CONVERSION.md` for the file-by-file mapping and translation rules, and
`CONVENTIONS.md` for the contract the conversion followed.

## Architecture parity
| Android | iOS |
|---|---|
| Jetpack Compose `@Composable` | SwiftUI `View` |
| Hilt `@HiltViewModel` + `StateFlow` | `ObservableObject` + `@Published` |
| Hilt `SingletonComponent` (AppModule) | `AppContainer` (env object) |
| `NavHost` + string routes + nested `voice_graph` | `NavigationStack` + `Route` enum + `Router` |
| `MaterialTheme.colorScheme` / `customColors` | `@Environment(\.galleryColors)` / `\.customColors` |
| DataStore `<proto>` | JSON files via `DefaultDataStoreRepository` |
| WorkManager downloads | `URLSession` download tasks |
| `CustomTask` + Hilt `@IntoSet` | `CustomTask` protocol + `AppContainer` task list |
| AlarmManager notifications | `UNUserNotificationCenter` |

The start destination is the companion voice-chat **MainPage** (Android
`startDestination = ROUTE_VOICE_GRAPH → ROUTE_MAINPAGE`); MainPage,
VoiceChatSettings and Characters share one `VoiceAssistantViewModel` +
`CharacterViewModel`, exactly like the Android nested-graph shared back-stack entry.

## Native bridge points (stubbed — wire a real SDK to enable)
These Android pieces use native runtimes with no pure-Swift equivalent; each is
behind a protocol with a working fallback and a `// NOTE:` marking the seam:
- **On-device LLM inference** (LiteRT-LM / AICore) → `LlmModelHelper` protocol +
  `StubLlmModelHelper` (streams placeholder text). Drop in MediaPipe
  `LlmInference` (`MediaPipeTasksGenAI`) and implement `LlmModelHelper`.
- **Neural TTS/STT** (sherpa-onnx Korean VITS / MeloTTS / Whisper) → `NeuralTtsEngine`
  / `NeuralSttEngine` protocols; the default uses `AVSpeechSynthesizer` /
  `SFSpeechRecognizer`. `tar.bz2` model extraction is a stub (add libarchive).
- **MCP transport** → `McpClient` over `URLSession` (JSON-RPC); SSE streaming stubbed.
- **Agent Skills JS** → `WKWebView` + a custom URL scheme handler serving the
  bundled `skills/` directory; the JS↔native bridge is implemented.
- **Firebase Analytics / FCM** → `Analytics` no-op logger + `NotificationActionHandler`.
- **HuggingFace OAuth** → endpoints kept; exchange flow stubbed (use ASWebAuthenticationSession).
- **StoreKit subscription** → `SubscriptPage.onPurchase` stub.

## Integration follow-ups
- In Xcode, ensure `Resources/tinygarden` and `Resources/skills` are added as
  **folder references** (blue folders) so the WebView features can load their
  nested `index.html`/`scripts/` by path. (The synchronized group includes the
  files; mark these two as folder references if the bundle flattens them.)
- Add a real on-device LLM by implementing `LlmModelHelper` and passing it to the
  task factories in `AppContainer.init` (replacing `StubLlmModelHelper`).
- Provide an `AppIcon` set if the placeholder 1024 icon is insufficient.
