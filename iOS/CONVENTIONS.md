# iOS conversion conventions (READ FIRST)

This iOS app is a faithful SwiftUI port of the Android **찐친 Ai** app (Google AI
Edge Gallery fork) located at `../Android/src/app/src/main`. The **foundation
layer is already built** — do NOT redefine any of it. Translate Android
Kotlin/Compose into SwiftUI using these rules.

## Source ↔ target mapping
- Android root: `gallery-ondev/Android/src/app/src/main/java/com/google/ai/edge/gallery/<pkg>`
- iOS root: `gallery-ondev/iOS/Gallery/<Folder>` (folders mirror Kotlin packages, PascalCase)
  - `ui/common/chat` → `UI/Common/Chat`, `customtasks/tinygarden` → `CustomTasks/TinyGarden`,
    `ui/home` → `UI/Home`, `character` → `Character`, etc.
- One Kotlin file → one Swift file with the same base name (e.g. `HomeScreen.kt` → `HomeScreen.swift`).
- The Xcode project uses a **synchronized folder group**: any `.swift` you add under
  `Gallery/` is automatically included. Just write files in the right folder.

## Translation rules
- Jetpack Compose `@Composable fun Foo(...)` → a SwiftUI `struct Foo: View`. Keep the
  same name. Preview functions can be omitted or use `#Preview`.
- Compose `ViewModel` (Hilt `@HiltViewModel`) → `final class FooViewModel: ObservableObject`,
  `MutableStateFlow`/`uiState` → `@Published var uiState`. Annotate VMs `@MainActor`.
  Screens hold them with `@StateObject` (owner) or `@ObservedObject`/`@EnvironmentObject`.
- `StateFlow.collectAsState()` → observe the `@Published` property.
- `remember { mutableStateOf(x) }` → `@State`.
- `LaunchedEffect` → `.task {}` / `.onAppear`. `coroutineScope.launch` → `Task {}`.
- `suspend fun` → `async`. `Dispatchers.IO/Default` → `Task.detached` or `await`.
- Material3 components → SwiftUI equivalents: `Scaffold`→`VStack`+toolbar, `TopAppBar`→
  `.toolbar`, `LazyColumn`→`List`/`LazyVStack` in `ScrollView`, `Card`→rounded `RoundedRectangle`
  background, `Button`/`OutlinedButton`/`FilledTonalButton`→`Button` with styling,
  `ModalBottomSheet`→`.sheet`, `AlertDialog`→`.alert`/`.confirmationDialog`,
  `Icon(Icons.*)`→`Image(systemName:)` (pick the closest SF Symbol).
- `stringResource(R.string.foo_bar)` → `Str.fooBar` (camelCase; see `Resources/Strings.swift`).
  Plurals: `Str.fooBar(count)`.
- Drawable vector resources (`R.drawable.xxx`) → SF Symbols where possible; raster ones
  (`char_01.jpg`, `persona_hero.jpg`) are in the asset catalog → `Image("char_01")`.

## Foundation you MUST use (already defined — never redefine)
- **Theme**: `@Environment(\.galleryColors) var colors` (Material roles: `colors.primary`,
  `colors.surface`, `colors.onSurface`, `colors.surfaceContainer`, …) and
  `@Environment(\.customColors) var customColors` (`customColors.taskBgColors`,
  `userBubbleBgColor`, `agentBubbleBgColor`, `linkColor`, `successColor`,
  `warningTextColor`, `taskIconColors`, gradients, …). Compose `MaterialTheme.colorScheme.x`
  → `colors.x`; `MaterialTheme.customColors.y` → `customColors.y`.
- **Typography**: `AppTypography.titleMedium`, `.bodyLarge`, `.homePageTitleStyle`, … and
  `AppFont.font(size:weight:)`. Use `.font(AppTypography.bodyMedium)`.
- **Data**: `Task`, `Model` (reference classes), `Config`/`ConfigKeys`/`NumberSliderConfig`/
  `BooleanSwitchConfig`/`SegmentedButtonConfig`/`LabelConfig`/`BottomSheetSelectorConfig`,
  `Category`/`CategoryInfo`, `Accelerator`, `BuiltInTaskId`, `ModelDownloadStatus(Type)`,
  consts in `Consts.swift`.
- **Chat core**: `ChatMessage` hierarchy + `ChatViewModel` (base ObservableObject with
  `uiState: ChatUiState`, `addMessage`, `updateLastTextMessageContentIncrementally`, etc.).
  Subclass `ChatViewModel` for feature chat VMs.
- **Central state**: `ModelManagerViewModel` (`@MainActor ObservableObject`,
  `@Published uiState: ModelManagerUiState`; methods `getModelByName`, `selectModel`,
  `initializeModel`, `cleanupModel`, `downloadModel`, `isModelDownloaded`, `getCustomTaskByTaskId`,
  `processTasks`, `loadModelAllowlist`, theme + text-input-history APIs). Injected via
  `@EnvironmentObject` or passed in.
- **Navigation**: `Router` (`@EnvironmentObject`) with `navigate(.route)`, `navigateUp()`,
  `popTo`, `Route` enum (`.home`, `.modelList(taskId:)`, `.model(taskId:modelName:query:)`,
  `.modelManager`, `.benchmark(modelName:)`, `.notifications`, `.voiceSettings`,
  `.characters`, `.subscription`, `.mainPage`).
- **Runtime**: `LlmModelHelper` protocol (+ `StubLlmModelHelper`, `LlmModelInstance`). Real
  on-device inference is stubbed — call through `LlmModelHelper`; do not invent a new runtime.
- **Custom tasks**: implement `CustomTask` protocol (`var task: Task`, `initializeModelFn`,
  `cleanUpModelFn`, `@MainActor func mainScreen(data:) -> AnyView`). The `data` is a
  `CustomTaskData` (or `CustomTaskDataForBuiltinTask` for legacy tasks LLM_CHAT/PROMPT_LAB/
  ASK_IMAGE/ASK_AUDIO/AGENT_CHAT).
- **Repositories**: `DataStoreRepository`, `DownloadRepository`, `SystemPromptRepository`,
  `NotificationScheduleManager` (already implemented).
- **DI**: `AppContainer` (`@EnvironmentObject`) exposes `dataStoreRepository`,
  `downloadRepository`, `systemPromptRepository`, `modelManagerViewModel`, `router`.
- **Proto data**: `Settings`, `UserData`, `Skill`/`Skills`, `McpServer(s)`, `McpTool`,
  `ChatSessionProto`, `ScheduledNotification`, `BenchmarkResult`, `Theme`, `Cutout`. Codable.

## Task module registration (IMPORTANT — avoid merge conflicts)
- If your feature owns a home-screen task, create a `*TaskModule.swift` exposing a
  `static func make() -> CustomTask` (and additional `make...()` for multi-task modules
  like LlmChat → chat/askImage/askAudio). **Do NOT edit `BuiltInTasks.swift` or
  `FeatureTaskModules`** — the integrator wires them in. Just expose the factory and list
  the exact call(s) in your final summary.

## Style
- Apache 2.0 license header comment at the top of every file (short form is fine), plus a
  `// Port of <android path>` line.
- Match the Korean strings already present (the app default language is Korean).
- Native-only Android pieces with no iOS equivalent (LiteRT-LM inference, sherpa-onnx TTS/STT,
  MCP transport, Firebase, CameraX, WorkManager) → use the provided stub/abstraction and add a
  clear `// NOTE:` explaining the bridge point. Keep the UI and view-model logic complete.
- Prefer correctness and structural fidelity over pixel-perfection. Keep view bodies readable.
- Do not add app-wide singletons; reuse `AppContainer`.
