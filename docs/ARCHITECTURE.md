# 아키텍처 보고서 — 보이스 컴패니언 채팅 앱

이 문서는 본 앱(원본 *Google AI Edge Gallery*를 캐릭터 기반 온디바이스 보이스 컴패니언으로 개조)의
**(1) 네비게이션 구조**, **(2) 모델 추론·스트리밍 구조**, **(3) 도구·스킬·에이전트 구조**,
**(4) 메시지 렌더링/블럭 구조**를 코드 기준으로 분석한다. 경로는 모두
`Android/src/app/src/main/java/com/google/ai/edge/gallery/` 기준이며, 핵심 위치는 `파일:라인`으로 표기한다.

---

## 1. 개요

- **시작 화면 = 보이스 채팅(MainPage)**. 사용자는 캐릭터(아바타)와 음성/텍스트로 대화한다.
- **모델 비탑재**: 채팅용 온디바이스 LLM(Gemma 등)을 다운로드해 공유하며, 음성 인식(STT)·합성(TTS)도
  시스템 엔진 + 다운로드형 신경망 + 상용 클라우드 API 중에서 선택한다.
- **에이전트 능력**: 함수호출(tool calling)로 카카오톡 전송·인터넷 검색·스킬·MCP 도구를 사용한다.
- **렌더링**: 어시스턴트 답변은 마크다운/코드블럭으로 렌더링하고, 음성으로 읽을 땐 코드·이모지·기호를
  제거한다. 이모지는 화면 위 떠오르는 감정 이펙트로 표현한다.

핵심 컴포넌트:

| 영역 | 핵심 파일 |
| --- | --- |
| 네비게이션 | `ui/navigation/GalleryNavGraph.kt` |
| 메인 채팅 UI | `ui/mainpage/MainPage.kt` |
| 통합 설정 | `ui/mainpage/VoiceChatSettingsScreen.kt` |
| 공유 배선(headless) | `ui/mainpage/VoiceChatWiring.kt` |
| 감정 오버레이 | `ui/mainpage/EmotionOverlay.kt` |
| 채팅/음성 상태·로직 | `customtasks/voiceassistant/VoiceAssistantViewModel.kt` |
| 태스크·도구 주입·시스템 프롬프트 | `customtasks/voiceassistant/VoiceAssistantTask.kt` |
| 캐릭터 모델/영속/경제 | `character/Character.kt`, `character/CharacterRepository.kt`, `character/CharacterViewModel.kt` |
| 캐릭터 선택 화면 | `character/CharacterScreen.kt` |
| 도구(함수호출) | `customtasks/agentchat/AgentTools.kt`, `customtasks/kakao/KakaoShareTools.kt`, `customtasks/websearch/WebSearchTools.kt` |
| 추론 런타임 | `ui/llmchat/LlmChatModelHelper.kt` |
| TTS/STT 엔진 | `customtasks/speech/*` (+ `customtasks/speech/CloudTts.kt`) |
| 발화 정제/이모지 | `customtasks/voiceassistant/EmotionText.kt` |
| 채팅 히스토리 영속 | `customtasks/voiceassistant/ChatHistoryStore.kt` |
| 마크다운 렌더 | `ui/common/MarkdownText.kt` |

---

## 2. 네비게이션 구조

`GalleryNavGraph.kt`의 `GalleryNavHost`가 전체 그래프를 정의한다. 시작 목적지는
**중첩 그래프 `voice_graph`** 이며, 그 시작은 `mainpage`이다 (`GalleryNavGraph.kt:200,207`).

### 2.1 라우트 맵

```
NavHost(startDestination = voice_graph)
├─ navigation(route = "voice_graph", start = "mainpage")     ← 보이스 채팅 경험(공유 VM 스코프)
│   ├─ "mainpage"        → MainPage           (메인 보이스 채팅)
│   ├─ "voice_settings"  → VoiceChatSettingsScreen (LLM/STT/TTS/도구/스킬/구독 통합 설정)
│   └─ "characters"      → CharacterScreen    (캐릭터 선택/상세/구매)
├─ "subscription"        → SubscriptPage      (Pro 구독 페이월)
└─ (기존 갤러리 라우트, 현재 메인 흐름에서는 비활성/보조)
    ├─ "homepage"        → HomeScreen
    ├─ "model_list"      → ModelManager
    ├─ "route_model"     → 커스텀/빌트인 태스크 화면
    ├─ "model_manager"   → GlobalModelManager
    ├─ "benchmark"       → BenchmarkScreen
    └─ "notifications"   → NotificationsScreen
```

상수 정의: `GalleryNavGraph.kt:102‑112`.

### 2.2 화면 간 이동

- **MainPage** 상단 우측: 👥(캐릭터 선택) → `characters`, ⚙️(설정) → `voice_settings`
  (`GalleryNavGraph.kt:208‑219`).
- **CharacterScreen** 상세에서 "○○와 대화하기" → `popBackStack(mainpage)`로 채팅 복귀,
  "Pro 구독" → `subscription`.
- **VoiceChatSettingsScreen** → 모델/음성 다운로드·선택, 스킬/MCP 관리, `subscription` 진입.

### 2.3 공유 ViewModel 스코핑 (중요)

`mainpage`·`voice_settings`·`characters`는 **같은 `voice_graph` 백스택 엔트리에 스코프된 ViewModel**을
공유한다. 각 `composable`에서

```kotlin
val parentEntry = remember(entry) { navController.getBackStackEntry(ROUTE_VOICE_GRAPH) }
viewModel               = hiltViewModel(parentEntry)   // VoiceAssistantViewModel
skillManagerViewModel   = hiltViewModel(parentEntry)
mcpManagerViewModel     = hiltViewModel(parentEntry)
characterViewModel      = hiltViewModel(parentEntry)
```

로 동일 인스턴스를 주입한다 (`GalleryNavGraph.kt:205‑253`). 덕분에 **설정에서 바꾼 음성/스킬/모델 선택이
채팅에 즉시 반영**되고, 로딩된 TTS/STT 엔진과 대화 상태가 화면 간 공유된다.

- `ModelManagerViewModel`은 액티비티 레벨에서 주입되어 더 넓게 공유된다.
- `CharacterRepository`/`ChatHistoryStore`/`CloudTtsService`는 `@Singleton`이라 어디서 주입되든 동일 상태다.

---

## 3. 모델 추론 · 메시지 스트리밍 구조

### 3.1 런타임 (litert-lm)

추론은 `LlmChatModelHelper`(object, `LlmModelHelper` 구현)가 담당한다.

- `initialize(...)`: `Engine(EngineConfig(modelPath, backend, …))` 생성 → `engine.initialize()` →
  `engine.createConversation(ConversationConfig(systemInstruction, tools, samplerConfig, initialMessages))`.
  - **백엔드(가속기)**: 기본 GPU(`Backend.GPU()`), CPU/NPU/TPU 선택 가능
    (`LlmChatModelHelper.kt:80‑117`).
  - **함수호출 제약 디코딩**: `ExperimentalFlags.enableConversationConstrainedDecoding`
    (`LlmChatModelHelper.kt:157`).
  - **initialMessages**: 대화 이력을 세션에 주입(문맥 복원)할 수 있음(`resetConversation`도 동일).
- `runInference(model, input, resultListener, …)`:
  `instance.conversation.sendMessageAsync(message, MessageCallback)`로 비동기 스트리밍
  (`LlmChatModelHelper.kt:300+`).

### 3.2 스트리밍 콜백

`MessageCallback`(`LlmChatModelHelper.kt:316+`):

```kotlin
onMessage(message) → resultListener(message.toString(), done=false, message.channels["thought"])
onDone()          → resultListener("", done=true, null)
```

- **`thought` 채널**: 일부 모델(Gemma 4 등)은 추론 과정을 별도 채널로 보낸다 → 메인 답변과 분리.
- 토큰은 부분 결과로 누적 전달된다.

### 3.3 ViewModel의 대화 루프

`VoiceAssistantViewModel.runLlm()` (`VoiceAssistantViewModel.kt:~1300`):

1. `runInference`의 `resultListener { partialResult, done, thought -> … }`에서
   - `<ctrl…>` 제어 토큰은 표시에서 제외(`partialResult.startsWith("<ctrl")` 필터).
   - 누적 텍스트를 `updateStreamingAssistant()`로 마지막 어시스턴트 메시지에 반영(화면 실시간 스트리밍).
   - 발화 모드가 STREAMING이면 문장 단위로 TTS 큐에 적재.
2. `done` 시: `isThinking=false`, 발화 마무리, **이모지 감정 큐 emit**, **히스토리 영속**.
3. **대화 전환 가드**: `convId = activeConversationId`를 캡처해, 생성 중 캐릭터가 바뀌면 옛 결과가
   새 대화에 섞이지 않도록 무시한다.

### 3.4 상태(UiState)

`VoiceAssistantUiState`(`VoiceAssistantViewModel.kt:~159`): `messages`, `isListening`, `isThinking`,
`isSpeaking`, `partialTranscript`, `error`, `voices`, `selectedVoiceId`, `speakMode`,
`sttEngine`, `neuralVoice/meloVoice/neuralStt/whisperStt`(다운로드 단계), `mcpToolCount`, `skillCount`,
`toolActivity`(도구 사용 중 라벨) 등. UI는 이 상태로 애니메이션/렌더를 구동한다.

---

## 4. 도구 · 스킬 · 에이전트 구조

메인 채팅은 홈스크린의 에이전트 채팅과 **동일한 `AgentTools` 표면**을 재사용한다.

### 4.1 함수호출(Tool) 메커니즘

litert-lm의 `ToolSet`/`@Tool`/`@ToolParam`로 정의한 코드 함수를 `createConversation(tools=…)`에
넘기고, `enableConversationConstrainedDecoding=true`로 모델이 스스로 함수를 호출하게 한다.
도구 함수는 `Map<String,String>`을 반환하며 모델이 그 결과를 받아 답변을 잇는다.

### 4.2 주입되는 도구 세트 (`VoiceAssistantTask.initializeModelFn`, `:164‑201`)

```kotlin
toolSets += tool(KakaoShareTools(context))          // 항상
toolSets += tool(WebSearchTools(agentTools))        // 항상 (인터넷 검색)
if (hasTools || hasSkills) toolSets += tool(agentTools)  // 스킬/MCP 있을 때
```

| 도구 | 파일 | 역할 |
| --- | --- | --- |
| `sendKakaoMessage` | `customtasks/kakao/KakaoShareTools.kt` | 카카오톡 공유 인텐트(사용자가 수신자 확정) |
| `searchWeb` | `customtasks/websearch/WebSearchTools.kt` | 인터넷 검색(무료) — DuckDuckGo HTML(lite) → 실패 시 Wikipedia 폴백, 키 불필요 |
| `loadSkill` | `customtasks/agentchat/AgentTools.kt` | 선택된 마크다운 스킬을 불러와 지시 적용 |
| `runMcpTool` | `customtasks/agentchat/AgentTools.kt` | 연결된 MCP 서버의 외부 도구 호출 |

### 4.3 시스템 프롬프트 조립 (`VoiceAssistantTask.kt:132‑160`)

`buildString`으로 다음을 합친다:
1. **캐릭터 페르소나**(선택 캐릭터의 `systemPrompt`; `SampleVoiceAssistantPromptSource`가 제공),
2. 카카오톡 사용 안내,
3. **인터넷 검색 사용 안내**(시의성/최신 정보면 `searchWeb` 호출 후 요약),
4. (있으면) 사용 가능한 스킬 목록 + `loadSkill` 안내,
5. (있으면) 연결된 MCP 도구 목록 + `runMcpTool` 안내.

### 4.4 스킬 / MCP

- **스킬**: 행동 지침 마크다운. `SkillManagerBottomSheet`로 추가/선택(URL·로컬·featured). 선택분이
  프롬프트에 노출되고 `loadSkill`로 로드 (`SkillManagerViewModel`).
- **MCP**: 외부 서버를 `McpManagerBottomSheet`에서 URL로 연결 → 도구 목록 노출, `runMcpTool`로 호출
  (`McpManagerViewModel`). 호출 전 **권한 다이얼로그**(`McpToolCallPermissionDialog`).
- 설정의 "도구·스킬·에이전트" 섹션에서 관리하며, 스킬/MCP 변경 시 모델이 **force 재초기화**되어
  새 능력이 시스템 프롬프트·도구셋에 반영된다(`MainPage.kt` capability 효과).

### 4.5 진행 상태 채널 (도구 사용 중 표시)

`AgentTools._actionChannel`(`AgentTools.kt:59`)로 액션을 흘리고 VM이 `attachAgentTools`에서 구독해
`handleAgentAction`으로 처리한다 (`VoiceAssistantViewModel.kt:~1201`):

- `SkillProgressAgentAction` → `uiState.toolActivity`(짧은 "…중" 라벨) 갱신.
- `AskMcpToolCallPermissionAction` → 권한 다이얼로그.
- `CallJsAgentAction`/`AskInfoAgentAction`/`RequestPermissionAgentAction` → 음성 흐름이 못 주는 UI라
  추론이 멈추지 않도록 **즉시 미지원/거부로 완료**.

내장 도구(예: 웹검색)도 `AgentTools.postProgress(label, inProgress)`(`AgentTools.kt:64`)로 같은 채널에
"인터넷 검색 중…"을 보낸다. 결과적으로 **생각 중/도구 사용 중 상태가 채널 하나로 일원화**된다.

---

## 5. 메시지 렌더링 · 블럭 구조 / 능력

### 5.1 화면 렌더링 (`MainPage.kt`, `VoiceChatBubble`)

- **사용자 메시지**: 평문 `Text`(마크다운 파싱 없음) — `MainPage.kt:705‑714`.
- **어시스턴트 메시지**: `MarkdownText`로 렌더 — `MainPage.kt:715‑723`.
  - `ui/common/MarkdownText.kt`는 `compose-richtext`(`com.halilibo.richtext`)의 **CommonMark
    Markdown + RichText(material3)** 를 사용한다(`MarkdownText.kt:31‑34`).
  - 지원: 제목, **굵게/기울임**, 목록, 링크, 인용, 그리고 **코드블럭(모노스페이스 `CodeBlockStyle`)**.
- **타이핑 인디케이터**: 답변 토큰 전 `isTyping`일 때 점 3개 애니메이션(`TypingDots`).
- **롱프레스 메뉴**(`combinedClickable` + `DropdownMenu`, `MainPage.kt:~724`): 메시지 복사 ·
  다시 답하기(어시스턴트) · 이전 대화 삭제 · 새 대화 시작.
- **자동 스크롤**: 새 메시지/스트리밍마다 마지막 항목으로 `animateScrollToItem`.

### 5.2 발화(TTS)용 정제 (`EmotionText.kt`)

화면 텍스트는 그대로 두고 **읽을 때만** 다음을 제거/처리한다:

- `stripCodeForSpeech`: **펜스 코드블럭(```` ``` ````)·인라인 코드(`` ` ``) 전체 제거** → 코드를 읽지 않음
  (`EmotionText.kt:56`).
- `speakableStreamingView`: 스트리밍 중 **아직 닫히지 않은 코드펜스 이후는 보류**해 반쪽 코드가 읽히지
  않게 함 (`EmotionText.kt:66`).
- `sanitizeForSpeech`: 코드 + 이모지/픽토그램 + 마크다운 기호 제거 + 공백 정리. 결과가 비면(예: 코드/이모지
  뿐) **발화 생략** (`EmotionText.kt:79`).

### 5.3 감정 이펙트 (`EmotionOverlay.kt`)

답변 완료 시 텍스트에서 이모지를 추출(`extractEmojis`)해 **일회성 `EmotionCue`** 를 emit하고,
화면 위로 이모지가 떠오르며 팝→흔들→페이드하는 비상호작용 오버레이를 재생한다(영상통화 리액션 느낌).
즉 **이모지는 읽지 않고 시각적으로 교감**한다.

### 5.4 상태 애니메이션

- 상단 상태줄: 도구 활동 > 듣기 > 생각 > 말하기 순으로 라벨 표시(`statusLabel`).
- **도구 활동 칩**(`ToolActivityChip`): 스킬/MCP/웹검색 실행 중 입력바 위에 스피너+라벨("인터넷 검색 중…").
- **마이크-오브 버튼**: 듣기/생각/말하기 상태별 색·펄스·회전(원래 보이스어시스턴트의 상단 오브와 하단
  마이크를 하나로 머지).

---

## 6. 음성 파이프라인 (요약)

- **STT(입력)**: 시스템 `SpeechRecognizer`(기본) / 다운로드형 신경망 **SenseVoice·Whisper**
  (`AudioRecorder` 직접 녹음, 시스템 인식기 우회). 한 번에 하나만 메모리에 로드.
- **TTS(출력)**: 시스템 `TextToSpeech` / 신경망 **KSS·MeloTTS**(sherpa-onnx `OfflineTts`) / **상용
  클라우드 API ElevenLabs·Naver Clova**(`customtasks/speech/CloudTts.kt`, 키 파라미터로 설정, 모델
  다운로드 아님).
- **보이스 id 스킴**: `neural:kss[#sid]`, `neural:melo[#sid]`, `system:<name>`,
  `cloud:<provider>:<speaker>`. 다중 화자 신경망 모델은 화자(`sid`)별 보이스 옵션으로 노출된다.
- **캐릭터별 보이스**: `CharacterRepository.voiceByCharacter`(영속) + 전역 기본값(`defaultVoiceId`).
  우선순위 = 캐릭터 지정 → 전역 기본 → 목록 첫 항목(클라우드는 자동 기본 제외).
- **발화 모드**: 전체 발화(완료 후) / 실시간 발화(문장 단위 스트리밍).

---

## 7. 캐릭터 · 영속 · 히스토리

- **캐릭터**(`Character.kt`): 이름·소개·성격·말투·주제·스타터·이미지·코인가격·무료여부. 성격/말투/주제가
  `systemPrompt`로 합성되어 페르소나를 구동.
- **경제/권한**(`CharacterRepository.kt`, `@Singleton`, SharedPreferences): 코인 잔액, 해제 캐릭터,
  선택 캐릭터, Pro 플래그, 캐릭터별 보이스, 전역 기본 보이스를 영속. 첫 3개 무료 + 환영 코인. 구매/구독은
  현재 시뮬레이션이되 결과(플래그)는 저장되어 화면 분기에 사용.
- **채팅 히스토리**(`ChatHistoryStore.kt`): 캐릭터별 JSON 파일로 영속. 캐릭터 전환·앱 재시작에도 유지.
  모델 초기화 시 해당 캐릭터 이력을 `resetConversation(initialMessages=…)`로 **LLM 문맥까지 복원**.
- **진입 인사**: 캐릭터 상세 "대화하기"로 들어오면, 모델 준비 + 빈 대화일 때 캐릭터가 먼저 인사(LLM 생성,
  숨은 프롬프트, TTS 발화).

---

## 8. 확장 포인트 / 알려진 한계

- **웹검색**: 무료 DuckDuckGo/Wikipedia 기반 → 실시간 속보엔 약함. Brave/SerpAPI 등 키 기반 검색을
  `WebSearch`에 끼우면 강화 가능(클라우드 TTS와 동일한 파라미터 설정 패턴).
- **클라우드 TTS 인증정보**: 현재 코드 내 **샘플 placeholder**. 설정 UI에서 입력·저장하도록 확장 가능
  (`CloudTtsService.setProviders`).
- **함수호출 신뢰도**: 소형 온디바이스 LLM은 도구 호출 트리거가 불안정할 수 있음(프롬프트/모델 의존).
- **GPU 초기화**: 일부 기기에서 GPU 백엔드 네이티브 크래시 가능 → CPU 폴백/센티넬 가드가 향후 과제.
- **레거시 갤러리 화면**(homepage 등): 라우트는 존재하나 현재 메인 흐름에서는 직접 도달하지 않음.

---

### 부록: 한 턴의 데이터 흐름

```
사용자 음성/텍스트
  → (STT) SpeechRecognizer | 신경망 → 텍스트
  → VoiceAssistantViewModel.submitUserInput → runLlm
  → LlmChatModelHelper.runInference → conversation.sendMessageAsync
       ├─ 필요 시 모델이 tool 호출(searchWeb/sendKakaoMessage/runMcpTool/loadSkill)
       │     → 도구 결과(Map) 반환 + AgentTools 진행상태 → toolActivity 애니메이션
       └─ 토큰 스트리밍(+thought 채널)
  → updateStreamingAssistant(화면: MarkdownText 렌더, 코드블럭 포함)
  → (발화) sanitizeForSpeech(코드/이모지 제거) → 시스템/신경망/클라우드 TTS
  → done: 이모지 → EmotionOverlay 애니메이션, 히스토리 영속
```
