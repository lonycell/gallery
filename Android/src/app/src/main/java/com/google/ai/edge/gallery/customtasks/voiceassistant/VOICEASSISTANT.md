# Voice Assistant (음성 어시스턴트)

A hands-free, on-device voice assistant custom task. The user speaks, an on-device LLM replies, and
the reply is shown on screen as it streams **and** read aloud at the same time. It ships no model of
its own — it reuses the app's downloadable chat LLMs — and it layers tools, skills, and MCP on top so
the assistant can actually *do* things (send a KakaoTalk message, call an MCP tool, run a skill).

Package: `com.google.ai.edge.gallery.customtasks.voiceassistant`
Task id: `speech_voice_assistant` (`VOICE_ASSISTANT_TASK_ID`)

---

## What it does

```
🎙️ 사용자 음성
   │  STT (시스템 SpeechRecognizer  또는  다운로드형 신경망 SenseVoice)
   ▼
📝 텍스트
   │  LLM 추론 (LlmChatModelHelper) + 시스템 프롬프트(주제/스킬/도구) + 함수호출
   ├──► 도구 호출  → sendKakaoMessage / MCP runMcpTool / 스킬 loadSkill
   ▼
💬 화면에 스트리밍 표시  ─┬─►  🔊 TTS 로 동시에 낭독
                          │     (시스템 TextToSpeech  또는  다운로드형 신경망 KSS 음성)
```

Highlights:
- **손 안 쓰는 대화**: 말하면 답이 실시간으로 화면에 뜨고 동시에 음성으로 읽힙니다.
- **모델 비탑재**: 채팅용으로 내려받은 LLM(Gemma 3/4, Qwen …)을 그대로 공유합니다.
- **주제(topic) 진입**: 특정 주제/문제에 집중한 상태로 들어올 수 있고, 그에 맞는 시스템 프롬프트로
  대화를 이끕니다.
- **한국어 우선**: STT/TTS 기본 로케일이 한국어이며, 주제가 BCP-47 태그로 언어를 덮어쓸 수 있습니다.
- **도구·스킬·MCP 통합**: 카카오톡 전송 도구는 항상 제공되고, 선택된 스킬과 연결된 MCP 도구가 있으면
  추가로 노출됩니다.

---

## Files

| 파일 | 역할 |
| --- | --- |
| `VoiceAssistantTask.kt` | `CustomTask` 구현. 모델 초기화 시 시스템 프롬프트 구성 + 도구 주입. |
| `VoiceAssistantViewModel.kt` | STT/TTS 엔진, 대화 상태, 추론 스트리밍, MCP 권한/진행 상태 관리. |
| `VoiceAssistantScreen.kt` | Compose UI. ViewModel과 `AgentTools`를 연결(attach)하고 모델을 주입. |
| `VoiceAssistantEntryParams.kt` | 진입 시 집중할 "주제"를 담는 프로세스 전역 싱글턴. |
| `VoiceAssistantModule.kt` | Hilt 바인딩: 프롬프트 소스 바인딩 + 태스크를 커스텀 태스크 집합에 기여. |
| `prompts/VoiceAssistantPromptSource.kt` | 주제→프롬프트 변환 인터페이스(미래에 원격/저장소 기반 교체 가능). |
| `prompts/SampleVoiceAssistantPromptSource.kt` | 현재 쓰이는 인메모리 샘플 프롬프트 소스. |
| `prompts/TopicPrompt.kt` | 주제별 프롬프트 번들(제목·시스템 프롬프트·스타터·언어). |

관련(공유) 코드:
- `customtasks/speech/` — `KoreanNeuralStt`(SenseVoice), `WhisperNeuralStt`(Whisper),
  `KoreanNeuralTts`(KSS), `MeloNeuralTts`(MeloTTS), `AudioRecorder`, `AudioPlayer` 등 음성 파이프라인.
- `customtasks/agentchat/AgentTools.kt` — 스킬/MCP 매니저를 묶은 공유 도구 표면(Agent Skills와 동일).
- `customtasks/kakao/` — 카카오톡 전송 도구 + 스킬 예제 (`README.md` 참고).

---

## Architecture

### 1. Task & model sharing
`VoiceAssistantTask`는 자체 모델을 갖지 않습니다 (`models = mutableListOf()`). 모델 매니저가
`llm_chat`용으로 허용된 LLM을 이 태스크에도 모두 추가하므로, 사용자는 표준 모델 선택기로 동일한
모델을 내려받고 전환할 수 있습니다 (`ModelManagerViewModel.loadModelAllowlist`).

### 2. Speech in (STT) — 시스템 + 다중 신경망 인식기
- **SYSTEM**: 기기 내장 `android.speech.SpeechRecognizer` (기본, 다운로드 불필요, 저지연, 부분 결과
  스트리밍 지원).
- **NEURAL (SenseVoice)**: 다운로드형 sherpa-onnx 다국어 인식기(~239MB). `AudioRecorder`로 원시
  PCM을 녹음해 디코드.
- **WHISPER (small, 다국어)**: 다운로드형 sherpa-onnx Whisper 인식기(~374MB). 한국어 정확도가 높지만
  모델이 크고 디코딩이 (자기회귀라) 더 느립니다. `language="ko"`로 구성. Speech to Text 태스크의
  `Whisper small (multilingual)` 모델과 다운로드를 공유합니다.

전환은 `selectSttEngine()`. **메모리 보호를 위해 신경망 인식기는 한 번에 하나만** `neuralStt`
슬롯에 로드되며(선택 시 로드, 전환 시 이전 인식기 해제 — `ensureActiveRecognizer`/
`releaseActiveRecognizer`), `loadedSttEngine`이 현재 로드된 엔진을 추적합니다. 각 모델의 다운로드
가용성은 `uiState.neuralStt`(SenseVoice) / `uiState.whisperStt`(Whisper)로 따로 표시되고,
다운로드 상태는 `onNeuralSttStatus()` / `onWhisperSttStatus()`가, 로드 실패 재시도는
`retryNeuralSttPreparation()` / `retryWhisperSttPreparation()`가 구동합니다. 신경망 엔진은
READY(다운로드 완료) + 선택 + 로드 완료일 때만 실제로 사용되고, 그 외에는 시스템 인식기로 동작합니다.

### 3. Speech out (TTS) — 시스템 + 다중 신경망 음성
- **시스템 `TextToSpeech`**: 한국어 시스템 음성 목록을 읽어 선택 가능.
- **신경망 KSS 음성**(sherpa-onnx VITS `OfflineTts`): 다운로드 후 unpack/init 되면 고품질·기기 독립
  음성으로 제공.
- **신경망 MeloTTS 음성**(MyShell.ai, sherpa-onnx VITS): 더 자연스러운 한국어 음성. KSS와 동일한
  파이프라인으로 독립적으로 내려받아 사용. (한국어 sherpa-onnx 변환본 호스팅이 필요 — `TtsTask`의
  `TODO(melo-ko)` 참고. URL이 비어 있으면 다운로드 배너가 숨겨집니다.)

신경망 음성은 모두 `AudioPlayer`로 재생됩니다. 선택은 `selectVoice()`이고, 선택된 신경망 음성이
"선택 + 로드 완료"일 때만 그 엔진으로, 그 외에는 시스템 엔진으로 낭독합니다. 음성 선택 칩은 로드된
음성이 2개 이상일 때 표시됩니다.

신경망 모델 준비는 각각 단계 머신으로 UI에 노출됩니다:
`NOT_INSTALLED → DOWNLOADING → PREPARING(unpack/init) → READY` (실패 시 `ERROR`, 재시도 지원).
KSS는 `onKoreanTtsStatus()`/`retryNeuralPreparation()`, MeloTTS는 `onMeloTtsStatus()`/
`retryMeloPreparation()`, 신경망 STT는 SenseVoice `onNeuralSttStatus()`/
`retryNeuralSttPreparation()` · Whisper `onWhisperSttStatus()`/`retryWhisperSttPreparation()`가
구동합니다. (STT 인식기는 위 2절처럼 한 번에 하나만 메모리에 로드됩니다.)

> **MeloTTS 참고**: MeloTTS는 sherpa-onnx에서 VITS 모델(`model.onnx` + `tokens.txt` +
> `lexicon.txt` + `dict/`)로 동작합니다. 공식 sherpa-onnx 변환본은 `vits-melo-tts-zh_en`(중국어+
> 영어)뿐이고 **한국어 변환본은 아직 공개되지 않았습니다.** `myshell-ai/MeloTTS-Korean`(PyTorch,
> MIT)을 sherpa-onnx의 `scripts/melo-tts`로 변환해 `.tar.bz2`로 호스팅한 뒤, `TtsTask`의
> `MELO_KO_URL`/`MELO_KO_SIZE_BYTES`를 채우면 즉시 동작합니다. 코드·UI·선택·로딩은 모두 준비돼
> 있습니다.

### 4. Conversation loop
1. STT 결과 텍스트 → `submitUserInput()`가 사용자 메시지 + 빈 스트리밍 어시스턴트 메시지를 추가.
2. `runLlm()`이 `runtimeHelper.runInference()`로 추론. `<ctrl…>` 제어 토큰은 표시에서 제외.
3. 부분 결과가 올 때마다 `updateStreamingAssistant()`로 마지막 어시스턴트 메시지를 갱신(화면 스트리밍).
4. 낭독은 **발화 모드(`speakMode`)** 에 따라 달라집니다(아래 4-1).

#### 4-1. 발화 모드 (`TtsSpeakMode`) — 화면의 "발화:" 칩으로 선택

- **`AFTER_COMPLETE`(전체 발화, 기본)**: 완료(`done`) 시 최종 텍스트를 `speak()`로 한 번에 낭독. 가장
  자연스러운 억양.
- **`STREAMING`(실시간 발화)**: 생성되는 동안 **문장 단위로 즉시 낭독**해 첫 음성까지의 지연을 크게 줄임.
  동작:
  - `beginStreamingSpeech()`가 문장 큐(`Channel`)와 단일 소비자 코루틴을 시작.
  - 부분 결과마다 `enqueueReadySentences()`가 마지막 문장 종결부호(`. ! ? … 。 ! ? \n`)까지 완성된
    구간을 잘라 큐에 넣음(종결부호 유지 → 억양 보존; 종결부호 없이 길어지면 `STREAMING_SOFT_FLUSH_CHARS`
    에서 단어 경계로 강제 플러시).
  - 소비자가 문장을 **순차적으로** 낭독: 신경망 음성은 `AudioPlayer.playToCompletion()`(재생 완료까지
    suspend), 시스템 TTS는 `QUEUE_ADD`+utterance 완료 await로 끝까지 기다린 뒤 다음 문장.
  - `done` 시 `finishStreamingSpeech()`가 남은 꼬리 문장을 넣고 채널을 닫아 소비자가 마저 비우고 종료.
  - 끼어들기(새 발화/`stopSpeaking`/음성·모드 변경)는 `cancelStreamingSpeech()`로 큐·코루틴·오디오를
    즉시 정리.

> 두 모드 모두 화면 텍스트 스트리밍(3번)은 동일합니다 — **음성 타이밍만** 달라집니다. 신경망 음성의
> 스트리밍은 문장마다 합성하므로 문장 사이에 약간의 합성 간격이 생길 수 있습니다(차후 선합성 파이프라인으로
> 개선 가능).

### 5. Topic-driven prompts
진입 주제는 `VoiceAssistantEntryParams`(싱글턴)에 담깁니다. 다른 화면/딥링크가 네비게이션 **전에**
`setTopic()`을 호출하면, 태스크가 모델 초기화 때 주제를 읽어 해당 시스템 프롬프트를 적용합니다.
주제가 없으면 일반 어시스턴트 프롬프트가 쓰입니다. ViewModel은 같은 주제를 "소비하지 않고" 들여다보고
제목/스타터를 표시하며, 주제의 `bcp47Language`로 STT/TTS 로케일을 덮어쓸 수 있습니다.

---

## Tools, Skills & MCP

이 셋이 음성 어시스턴트에 결합되는 방식 (개념 비교는 `customtasks/exampleagent/README.md` 참고):

| 계층 | 무엇 | 어디서 노출/주입 |
| --- | --- | --- |
| **Tool (앱 내장 함수)** | `sendKakaoMessage` (카카오톡 공유 인텐트) | **항상** 주입 (`customtasks/kakao`) |
| **Skill (행동 지침 md)** | 선택된 스킬들 | 선택 시 시스템 프롬프트에 목록 노출, `loadSkill`로 로드 |
| **MCP (외부 서버 도구)** | 연결된 MCP 서버의 도구 | 연결 시 목록 노출, `runMcpTool`로 호출 |

### 주입 코드 (`VoiceAssistantTask.initializeModelFn`)
모델 초기화 시 다음을 수행합니다:

```kotlin
// 1) 스킬/MCP 목록을 읽어 시스템 프롬프트에 넣을 텍스트 준비
val toolsPrompt  = agentTools.mcpManagerViewModel.getToolsPrompt()             // 연결된 MCP 도구
val skillsPrompt = agentTools.skillManagerViewModel
                     .getSelectedSkillsNamesAndDescriptions()                  // 선택된 스킬
val hasTools  = toolsPrompt.isNotEmpty()
val hasSkills = skillsPrompt.isNotEmpty()

// 2) 시스템 프롬프트: 주제 프롬프트 + 카톡 안내 + (있으면) 스킬/도구 목록
val finalPrompt = buildString {
  if (basePrompt.isNotEmpty()) append(basePrompt)
  append("…사용자가 카톡 보내달라고 하면 sendKakaoMessage 호출, 보내기 전 수신자·내용 확인…")
  if (hasSkills) append("…사용 가능한 스킬 목록… loadSkill 로 로드…\n" + skillsPrompt)
  if (hasTools)  append("…사용 가능한 도구 목록… runMcpTool 로 호출…\n" + toolsPrompt)
}

// 3) 도구 집합: 카톡은 항상, agentTools(스킬+MCP)는 있을 때만
val toolSets = mutableListOf<ToolProvider>()
toolSets.add(tool(KakaoShareTools(context = context.applicationContext)))   // 항상
if (hasTools || hasSkills) toolSets.add(tool(agentTools))

// 4) 함수 호출은 항상 활성화 (카톡 도구가 늘 있으므로)
LlmChatModelHelper.initialize(
  …,
  systemInstruction = instruction,
  tools = toolSets,
  enableConversationConstrainedDecoding = true,
)
```

요지: **도구를 선언하고 → 런타임에 넘기고 → 시스템 프롬프트로 언제 쓸지 알려준다.** 그러면 모델이
스스로 판단해 함수를 호출합니다.

### MCP 권한·진행 상태 (ViewModel)
음성 흐름은 자체 UI 표면이 제한적이라, `AgentTools`의 액션 채널을 `attachAgentTools()`에서 구독해
처리합니다 (`handleAgentAction`):

- `AskMcpToolCallPermissionAction` → 권한 다이얼로그를 띄우고 `resolveMcpPermission()`으로 사용자
  선택을 반영.
- `SkillProgressAgentAction` → "도구 사용 중…" 짧은 상태 줄(`toolActivity`)로 표시.
- `CallJsAgentAction`(JS 스킬), `AskInfoAgentAction`(자유 입력), `RequestPermissionAgentAction`
  (런타임 권한) → 음성 흐름이 제공하지 못하는 UI라서, 추론이 멈추지 않도록 **즉시** "미지원/거부"로
  완료시켜 모델이 다음 행동으로 넘어가 사용자에게 설명하게 함.

`mcpToolCount` / `skillCount`는 "도구/스킬 사용 가능" UI를 구동합니다.

---

## Extending

- **새 내장 도구 추가**: `ToolSet`을 구현하는 클래스에 `@Tool` 함수를 만들고
  (`KakaoShareTools.kt` 참고), `initializeModelFn`의 `toolSets`에
  `toolSets.add(tool(MyTools(...)))`로 추가. 필요하면 시스템 프롬프트에 사용 안내 한 줄 추가.
- **새 스킬 추가**: 스킬 매니저(`SkillManagerBottomSheet`)로 markdown 스킬을 추가/선택. 코드 변경 없이
  행동 규칙을 얹을 수 있음 (`kakao-messenger-skill.md` 참고).
- **새 MCP 서버 연결**: MCP 매니저(`McpManagerBottomSheet`)에서 URL로 서버를 추가하면 그 도구들이
  자동으로 목록에 노출되고 `runMcpTool`로 호출됨 (예: `korean-law-mcp`).
- **프롬프트 소스 교체**: `VoiceAssistantPromptSource`를 다른 구현(원격 API/저장소 기반)으로 바꾸고
  `VoiceAssistantModule`의 바인딩만 변경.

---

## Notes & limitations

- 함수 호출은 항상 켜져 있습니다(카톡 도구가 늘 제공되므로). 스킬/MCP가 없어도 모델은 카톡 도구를
  쓸 수 있습니다.
- 카카오톡 전송은 **공유 인텐트** 방식이라 실제 전송은 카카오톡 화면에서 사용자가 수신자를 고르고
  확정합니다(되돌릴 수 없는 동작에 대한 안전장치). 자세한 설계 근거는 `customtasks/kakao/README.md`.
- JS 스킬·웹뷰·자유 입력·런타임 권한이 필요한 도구 동작은 음성 흐름에서 미지원으로 처리됩니다.
- 신경망 STT/TTS는 선택형 다운로드이며, 미설치/실패 시 자동으로 시스템 엔진으로 동작합니다.
