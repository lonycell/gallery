# MeloTTS (Korean) → sherpa-onnx 변환 도구

이 폴더는 [`myshell-ai/MeloTTS-Korean`](https://huggingface.co/myshell-ai/MeloTTS-Korean)
(PyTorch, MIT)을 **이 앱이 그대로 쓸 수 있는 sherpa-onnx VITS 모델**(`vits-melo-tts-ko.tar.bz2`)로
바꾸는 **완성된 변환 도구**입니다. 개발용 PC에서 한 번 실행하면 끝납니다.

> 배경 설명은 [`../../Android/src/app/.../speech/MELOTTS_KO_CONVERSION.md`](../../Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/speech/MELOTTS_KO_CONVERSION.md)
> 참고. 그 문서가 "수동으로 어떻게 하는가"라면, 이 폴더는 그걸 **자동화한 실행 도구**입니다.

---

## TL;DR — Windows 개발 PC에서 한 줄

```powershell
# Docker Desktop 설치되어 있으면 끝. (Linux 컨테이너 모드)
PS> .\convert.ps1
```

끝나면 `out\` 에 이렇게 생깁니다:

```
out\
├── vits-melo-tts-ko.tar.bz2   ← 앱에 호스팅할 최종 산출물
├── test.wav                   ← 변환 직후 합성된 한국어 음성 (반드시 들어볼 것)
├── model.onnx / tokens.txt / lexicon.txt
└── CONSTANTS.txt              ← TtsTask.kt 에 넣을 상수 (URL/크기)
```

그다음 3단계만 하면 앱에서 바로 동작합니다 → [아래 "앱에 연결"](#5-앱에-연결).

---

## 왜 변환이 필요한가 (요약)

앱의 음성 스택은 전부 sherpa-onnx(ONNX Runtime, 네이티브)입니다. PyTorch 런타임도, MeloTTS의
한국어 텍스트 프런트엔드(g2pkk · MeCab-ko · 한국어 BERT)도 기기에 없습니다. 그래서 데스크톱에서
**1회 ONNX로 변환**해 `model.onnx` + `tokens.txt` + `lexicon.txt`를 만들어 내려받는 것이
표준 경로입니다. 공식 `vits-melo-tts-zh_en`도 같은 방식입니다.

**한계:** sherpa-onnx 런타임은 MeloTTS의 BERT 입력을 0으로 채웁니다(운율 정보 일부 손실). 원본
PyTorch보다 억양이 다소 단조로울 수 있습니다 — 그래서 **`test.wav`를 꼭 들어보고** 판단하세요.

---

## 무엇이 들어 있나

| 파일 | 역할 |
| --- | --- |
| `export-onnx-ko.py` | **핵심.** MeloTTS-Korean → `model.onnx`+`tokens.txt`+`lexicon.txt`. 공식 ZH 변환 스크립트의 한국어 적응본. |
| `test-onnx-ko.py` | 변환물로 `test.wav` 합성 (PyTorch 없이 onnxruntime만 사용 — 기기와 동일 경로). |
| `show-info.py` | `model.onnx` 메타데이터/입출력 점검 + 런타임 필수값 검증. |
| `package.py` | 앱이 기대하는 레이아웃·이름으로 `vits-melo-tts-ko.tar.bz2` 생성 + 바이트 크기/Kotlin 상수 출력. |
| `set_app_constants.py` | `TtsTask.kt`의 `MELO_KO_URL`/`MELO_KO_SIZE_BYTES`를 자동 패치. |
| `extra_words.txt` | (선택) 자연스러움을 높일 한국어 단어 목록. 자유롭게 추가. |
| `Dockerfile` · `convert-pipeline.sh` | 재현 가능한 Linux 변환 환경 + 파이프라인. |
| `convert.ps1` / `convert.sh` | 원클릭 드라이버 (Windows-Docker / Linux·WSL-venv). |
| `requirements.txt` | 공식 `run.sh`와 동일하게 핀 고정된 의존성. |

한국어 모델 가중치는 **여기 두지 않습니다.** `export-onnx-ko.py`가 실행 시 Hugging Face에서
자동으로 내려받습니다(앱의 다운로드 URL이 비어 있는 이유).

---

## 실행 방법

### 방법 A — Docker (Windows 권장, 가장 안정적)

Windows에서 MeCab-ko/한국어 g2p 네이티브 빌드는 까다롭습니다. Docker가 이를 전부 우회합니다.

```powershell
PS> .\convert.ps1
```

내부적으로: 이미지 빌드 → 컨테이너에서 `export → show-info → test → package` 실행 →
`.\out\` 으로 산출물 복사. 첫 빌드는 의존성·모델 다운로드로 수 GB/수십 분 걸리고, 이후엔 캐시됩니다.

직접 docker로 돌리려면:
```powershell
docker build -t melotts-ko-converter .
docker run --rm -e OUT_DIR=/work/out -v "${PWD}\out:/work/out" melotts-ko-converter
```

### 방법 B — WSL / Linux / macOS (Docker 없이)

```bash
./convert.sh            # 산출물 → ./out
```
`.venv` 생성 → `requirements.txt` 설치 → MeloTTS clone/설치 → 파이프라인 실행.

### 방법 C — 단계별 수동 (디버깅용)

```bash
pip install -r requirements.txt
git clone --depth 1 https://github.com/myshell-ai/MeloTTS && pip install ./MeloTTS
python -m unidic download

python export-onnx-ko.py --extra-words extra_words.txt   # model/tokens/lexicon
python show-info.py model.onnx                            # 메타데이터 검증
python test-onnx-ko.py --out test.wav                     # 청취 검증
python package.py                                         # vits-melo-tts-ko.tar.bz2
```

> Windows 네이티브(방법 C)는 `python-mecab-ko` 휠 문제로 실패하기 쉽습니다. 방법 A/B를 쓰세요.

---

## 산출물이 앱 규약과 맞는지 (자동 보장됨)

`package.py`가 만드는 아카이브 레이아웃은 [`MeloNeuralTts.kt`](../../Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/speech/MeloNeuralTts.kt)
상수와 **정확히** 일치합니다:

```
vits-melo-tts-ko/        ← MELO_TTS_DIR
├── model.onnx           ← MELO_TTS_ONNX   (필수)
├── tokens.txt           ← MELO_TTS_TOKENS (필수)
├── lexicon.txt          ← MELO_TTS_LEXICON(필수)
└── LICENSE              (자동 포함, MIT 고지)
```

`dict/`는 중국어 jieba 전용이라 한국어엔 불필요합니다(메타데이터 `jieba=0`). 앱도 `dict/`를 선택
사항으로 처리합니다.

### 런타임 인식에 필요한 메타데이터 (스크립트가 자동 설정)

sherpa-onnx가 이 모델을 MeloTTS로 인식하려면 다음이 필수입니다 — `export-onnx-ko.py`가 자동으로 넣습니다:
- `comment` 에 `"melo"` 포함 → MeloTTS 프런트엔드 선택
- `version >= 2` → 아니면 런타임이 로드 거부
- `jieba = 0` → 한국어는 중국어 분절기 미사용(공백 분리 + 음절 단위 폴백)
- `bert_dim`/`ja_bert_dim` → 체크포인트에서 자동 감지(런타임이 0으로 채울 텐서 크기)

`show-info.py`가 이 값들을 PASS/FAIL로 검증해 줍니다.

---

## 5. 앱에 연결

1. **들어보기:** `out\test.wav` 재생 — 한국어가 또렷한가? (억양은 단조로울 수 있음, 위 한계 참고)
2. **호스팅:** `out\vits-melo-tts-ko.tar.bz2`를 안정적 공개 URL에 업로드
   (자체 Hugging Face 레포 `resolve/main/...`, GitHub Release 자산 등). **MIT 라이선스 고지** 동반.
3. **상수 채우기** (둘 중 하나):
   - 자동: `python set_app_constants.py --url <호스팅URL> --archive out\vits-melo-tts-ko.tar.bz2`
   - 수동: `out\CONSTANTS.txt`의 두 줄을 [`TtsTask.kt`](../../Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/tts/TtsTask.kt)
     의 `TODO(melo-ko)` 자리(`MELO_KO_URL`/`MELO_KO_SIZE_BYTES`)에 붙여넣기.

URL이 채워지면 음성 어시스턴트·Text to Speech 화면에 **"MeloTTS (ko)"** 다운로드가 자동으로
나타납니다. 코드·UI·선택·로딩은 이미 완성돼 있어 **이 두 상수만** 채우면 동작합니다.

---

## 검증 체크리스트

- [ ] `show-info.py` 가 **PASS** (comment=melo, version≥2, jieba=0, sample_rate 등)
- [ ] `test.wav` 의 한국어가 또렷한가?
- [ ] `tar tjf vits-melo-tts-ko.tar.bz2` 최상위가 `vits-melo-tts-ko/` 인가?
- [ ] 앱에서 받기 → 준비 완료 → "MeloTTS (ko)" 선택 후 한국어로 낭독되는가?
- [ ] 숫자/영어 혼용 문장도 누락 없이 발음되는가? (부족하면 `extra_words.txt`에 단어 추가 후 재변환)

---

## 동작 원리 (간단히)

- **tokens.txt**: `model.hps["symbols"]`(한국어 자모 음소 포함)을 그대로 id로 매핑.
- **lexicon.txt**: ① 영어 단어(코드스위칭, cmudict) ② (선택) `extra_words.txt`의 단어를
  문맥 g2p로 ③ **모든 현대 한글 음절(가..힣 11,172자)**을 각각 g2pkk로 변환해 등록.
  런타임은 어절(공백) 단위로 찾고, 없으면 **음절 단위로 폴백**하므로 모든 한국어가 발음됩니다.
  음절 단독 변환이라 연음/경음화 등 문맥 규칙은 일부 누락 → `extra_words.txt`로 보강.
- **model.onnx**: 공식 ZH `ModelWrapper`와 동일한 입력 시그니처(`x, x_lengths, tones, sid,
  noise_scale, length_scale, noise_scale_w`). BERT는 0으로 주입(런타임도 동일). 단, 0-BERT
  텐서 폭은 한국어 체크포인트에서 자동 감지해 메타데이터에 기록.

---

## 트러블슈팅

- **`docker: command not found`** → Docker Desktop 설치, 또는 WSL에서 `./convert.sh`.
- **`No module named 'mecab'` / mecab 빌드 실패 (Windows 네이티브)** → 방법 C를 쓰지 말고
  방법 A(Docker)나 B(WSL)로. Linux 휠은 mecab-ko 사전을 번들로 포함합니다.
- **`test.wav`가 잡음만** → tokens/lexicon 순서 불일치 가능. `show-info.py` PASS 확인,
  MeloTTS 버전이 한국어 심볼을 포함하는지 확인. (드물게 MeloTTS 메인 브랜치 변경 영향)
- **로드 시 "download the latest MeloTTS model"** → `version` 메타데이터가 2 미만. 본 스크립트는
  2로 설정하므로, 재변환했는지/구버전 onnx를 쓰는지 확인.
- **특정 단어가 이상하게 발음** → `extra_words.txt`에 그 단어를 추가하고 재변환(문맥 g2p 적용).

---

## 참고

- 변환 스크립트 원본(ZH): <https://github.com/k2-fsa/sherpa-onnx/tree/master/scripts/melo-tts>
- MeloTTS 본체: <https://github.com/myshell-ai/MeloTTS>
- 한국어 PyTorch 모델: <https://huggingface.co/myshell-ai/MeloTTS-Korean>
- sherpa-onnx TTS 문서: <https://k2-fsa.github.io/sherpa/onnx/tts/>
