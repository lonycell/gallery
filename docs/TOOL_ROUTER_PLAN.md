# 2-모델 도구 라우터 설계 — 범용 대화 + FunctionGemma 함수호출

## 1. 배경 / 동기

현재 음성 컴패니언은 **하나의 LLM**이 대화와 함수호출을 모두 담당한다. litert-lm의 함수호출(제약
디코딩)은 Gemma 계열·Qwen3만 지원하고, 그 외 모델(Qwen2.5·DeepSeek 등)은 도구를 켜면 네이티브
크래시가 난다(그래서 현재는 모델 패밀리로 게이팅 중).

문제의 본질: **"대화를 잘하는 것"과 "함수호출을 잘하는 것"은 다른 능력**이다.

- 범용 대화 모델(Gemma 3n, Qwen3, Llama 3.2 …)은 자연스럽게 말하지만 도구 호출은 들쑥날쑥.
- FunctionGemma(Gemma 3 270M)는 **함수호출 전용**으로, 자연어를 구조화된 함수 호출로 번역하는 데
  특화됐지만 **대화는 못 한다**(도구 JSON만 뱉음).

➡ 두 모델을 **역할 분리**해서, 대화는 범용 모델이, 도구 결정은 FunctionGemma가 맡는 라우터 구조로
가면 양쪽의 장점을 모두 얻는다.

### 부수 효과 (중요)
대화 모델에서 **함수호출/제약 디코딩을 끌 수 있으므로**, 대화 모델은 **아무거나** 써도 된다
(Qwen2.5·DeepSeek·Llama 포함). 즉 현재의 크래시 문제도 구조적으로 사라진다 — 도구는 항상
FunctionGemma가 담당하기 때문이다.

## 2. 아키텍처 개요 (라우터 우선)

```
사용자 발화
   │
   ▼
[FunctionGemma 라우터]  ── 도구 스키마(웹검색/카카오/스킬·MCP)를 프롬프트로 받음
   │
   ├─(함수호출 없음)──────────────► [범용 대화 모델] ──► 자연스러운 응답
   │
   └─(함수호출 있음)──► [도구 실행] ──► 결과 ──► [범용 대화 모델] ──► 결과를 녹인 자연 응답
```

- **대화 모델**: 제약 디코딩 OFF. 그냥 대화만 한다(모든 모델 호환).
- **FunctionGemma**: 도구가 필요한지/어떤 도구를 어떤 인자로 호출할지만 판단한다.
- 한 턴에 FunctionGemma 1회(빠름·소형) → (필요 시) 도구 실행 → 대화 모델 1회.

## 3. 턴 라이프사이클 (상세)

1. **라우팅**: 사용자 메시지 + 사용 가능한 도구 스키마를 FunctionGemma에 전달.
   - 출력 파싱: 함수 호출(name, args) 목록 또는 "없음".
2. **분기 A — 도구 없음**: 사용자 메시지를 대화 모델에 그대로 전달 → 응답 스트리밍(현행과 동일).
3. **분기 B — 도구 있음**:
   1. 호출된 도구를 실행(웹검색/카카오/스킬·MCP). 진행 상태는 기존 `ToolProgress` UI로 표시.
   2. 도구 결과를 **컨텍스트로 합성**해 대화 모델에 전달:
      "사용자가 X를 물었고, 도구 결과는 [..]. 이 결과를 활용해 캐릭터답게 자연스럽게 답해줘."
   3. 대화 모델이 결과를 녹여 **사람처럼** 답한다(원시 JSON 노출 금지).
4. **메모리/히스토리**: 대화 모델의 대화 히스토리에는 자연 발화만 쌓는다(도구 호출/결과는 숨은
   컨텍스트로만 1회 주입). FunctionGemma는 상태가 거의 없는 단발 라우터로 둔다.

## 4. 컴포넌트 / 통합 지점

| 구성요소 | 위치(현행 코드) | 변경/추가 |
| --- | --- | --- |
| `ToolRouter` 인터페이스 | 신규 `customtasks/voiceassistant/router/` | `suspend fun route(userText, tools): List<ToolCall>` |
| `FunctionGemmaRouter` 구현 | 신규 | FunctionGemma Engine/Conversation로 라우팅, 출력 파싱 |
| `NoopRouter`(폴백) | 신규 | FunctionGemma 미설치 시 항상 "도구 없음" → 현행 동작 유지 |
| 대화 모델 init | `VoiceAssistantTask.initializeModelFn` | tools=[], `enableConversationConstrainedDecoding=false`로 단순화 |
| 도구 실행 | 기존 `WebSearchTools`/`KakaoShareTools`/`AgentTools` | 라우터 결과로 **직접 호출**(litert ToolSet 대신 수동 디스패치) |
| 추론 흐름 | `VoiceAssistantViewModel.submitUserInput`/`runLlm` | 라우팅 → (도구 실행) → 대화 모델 호출 순서로 재구성 |
| FunctionGemma 로딩 | 신규 (별도 litert-lm Engine) | 대화 모델과 **별도 인스턴스**로 상주 |

핵심: **litert의 내장 ToolSet/제약 디코딩 경로를 더 이상 대화 모델에 쓰지 않는다.** 도구 호출 결정은
FunctionGemma가, 실행은 우리 코드가, 응답은 대화 모델이 한다.

## 5. litert-lm 통합 세부

- **두 개의 Engine**: 대화 모델 Engine(기존) + FunctionGemma Engine(신규, 소형). 둘 다 메모리에
  상주(270M은 양자화 시 수백 MB 수준이라 현대 폰에서 동시 로딩 가능).
- **FunctionGemma 프롬프트 형식**: FunctionGemma가 학습된 함수 선언/호출 포맷(JSON 스키마)에 맞춰
  도구 목록을 구성. 도구 = 웹검색, 카카오 공유, 선택된 스킬/MCP 툴.
- **출력 파싱**: FunctionGemma의 함수호출 출력(구조화 텍스트/JSON)을 파싱해 `ToolCall(name, args)`로
  변환. 견고한 파서 필요(빈/형식 오류 시 "도구 없음"으로 안전 폴백).
- **대화 모델**: `tools=emptyList()`, 제약 디코딩 off → 어떤 모델이든 안전.

## 6. 모델 준비 (선행 과제)

FunctionGemma는 현재 **바로 쓰는 `.litertlm`/`.task` 아티팩트가 공개돼 있지 않다**(공식 문서엔 변환
가이드만 존재). 따라서:

1. **변환**: HF `google/functiongemma-270m-it` → MediaPipe `.task` 또는 litert-lm `.litertlm`로 변환
   (gemma-cookbook의 변환 노트북 사용). 양자화(int4/int8) 권장.
2. **배포**: 변환물을 HF(예: 자체 repo)에 올리고, 앱의 **커스텀 모델 항목**으로 주입하거나 앱에 번들.
   - 원격 allowlist는 구글이 관리하므로, 우리 항목은 `AllowedModel`을 코드에서 주입하는 경로로 추가.
3. **검증**: 실제 기기에서 라우팅 정확도/지연 측정.

> 이 선행 과제가 끝나야 FunctionGemmaRouter를 실제로 켤 수 있다. 그 전까지는 NoopRouter로 동작
> (=현행 단일 모델 대화, 도구는 Gemma/Qwen3에서만)하도록 두어 회귀가 없게 한다.

## 7. 단계별 구현 계획

1. **(스캐폴딩, 모델 불필요)**
   - `ToolRouter` 인터페이스 + `NoopRouter` + 라우팅 훅을 `submitUserInput`에 삽입(기본 Noop).
   - 도구 "수동 디스패치" 경로 정리(라우터 결과 → WebSearch/Kakao/Agent 실행 → 결과 합성).
   - 대화 모델 init에서 제약 디코딩/ToolSet 제거 옵션(플래그)로 분리.
2. **(FunctionGemma 연결)**
   - FunctionGemma `.litertlm` 확보 후 별도 Engine 로딩 + `FunctionGemmaRouter` 구현/파서.
   - 도구 스키마 → FunctionGemma 프롬프트 직렬화.
3. **(고도화)**
   - 멀티 도구/연쇄 호출, 라우팅 캐시, 지연 최적화(라우터 결과 없으면 대화 모델 바로 시작).
   - 라우팅 실패 안전망, 도구 결과 요약 길이 제한.

## 8. 메모리 / 지연 / 배터리

- 동시 2모델 상주 → 메모리 ↑. 저사양 기기 대비 **FunctionGemma 지연 로딩**(첫 도구 필요 시 로드) 옵션.
- 매 턴 라우터 1패스 추가 지연(소형이라 짧음). "명백히 도구 불필요"한 짧은 발화는 라우터를 건너뛰는
  휴리스틱도 고려.
- 통화(call) 모드의 반이중 루프와 호환: 라우팅·도구 실행도 "생각 중" 상태로 표시.

## 9. 위험 / 한계

- FunctionGemma `.litertlm` 아티팩트 부재(변환 필요) — 1차 블로커.
- 270M 라우터의 도구 결정 정확도는 파인튜닝/프롬프트에 민감(데모 정확도 58→85%는 파인튜닝 후).
- 2모델 동시 로딩이 저사양 기기에서 메모리 부담 → 지연 로딩/온오프 설정 필요.
- 온디바이스 함수호출 생태계가 아직 성숙 단계.

## 10. 결론

라우터 구조는 (a) 대화 품질과 도구 신뢰성을 분리하고, (b) 대화 모델을 자유롭게 선택하게 하며,
(c) 현재의 크래시 게이팅을 구조적으로 불필요하게 만든다. **선행 과제는 FunctionGemma의 litert-lm
아티팩트 확보**이며, 그 전까지는 NoopRouter로 안전하게 단계 1 스캐폴딩부터 진행할 수 있다.
