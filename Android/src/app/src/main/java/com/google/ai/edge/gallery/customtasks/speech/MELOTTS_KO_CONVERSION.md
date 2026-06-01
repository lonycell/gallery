# MeloTTS(한국어) → sherpa-onnx 변환 가이드

이 문서는 [`myshell-ai/MeloTTS-Korean`](https://huggingface.co/myshell-ai/MeloTTS-Korean)
(PyTorch, MIT)을 **sherpa-onnx에서 동작하는 VITS 모델**로 변환해, 이 앱의 음성 어시스턴트 ·
Text to Speech 화면에서 쓰는 절차를 설명합니다.

> **자동화된 도구가 이미 있습니다.** 이 문서가 설명하는 단계(아래 1~5절)는 저장소 루트의
> `converters/melotts-ko/` 폴더에 실행 가능한 도구로 구현돼 있습니다. Windows 개발 PC에서는
> 그 폴더에서 `convert.ps1` 한 줄이면 `vits-melo-tts-ko.tar.bz2`까지 만들어집니다. 아래 본문은
> 그 도구가 내부적으로 무엇을 하는지에 대한 배경 설명으로 읽으세요.

> **왜 변환이 필요한가**
> 앱의 음성 스택은 전부 sherpa-onnx(ONNX Runtime, 네이티브 C++) 기반입니다. PyTorch 런타임이
> 없고, MeloTTS의 한국어 텍스트 프런트엔드(MeCab-ko · g2pkk · 한국어 BERT)를 온디바이스에서
> 재현하지도 않습니다. 따라서 데스크톱/서버에서 **1회 ONNX로 변환**한 뒤 결과물(`model.onnx` +
> `tokens.txt` + `lexicon.txt` (+ `dict/`))을 내려받아 ONNX 런타임으로 돌리는 것이 유일하고
> 표준적인 경로입니다. sherpa-onnx의 공식 `vits-melo-tts-zh_en`도 같은 방식으로 만들어졌습니다.
>
> **주의:** 공식 변환 스크립트(`scripts/melo-tts/export-onnx.py`)는 **중국어+영어(ZH)** 전용입니다.
> 한국어는 공식 릴리스가 없어, 아래 "한국어 적응" 절의 수정이 필요합니다. 또한 sherpa-onnx 런타임은
> MeloTTS의 BERT 입력을 0으로 채우므로(운율 정보 일부 손실), 원본 PyTorch 대비 억양이 다소
> 단조로울 수 있습니다. 이는 한국어 공식 변환본이 아직 없는 주요 이유이기도 합니다 — 변환 후 반드시
> 청취 평가를 하세요.

---

## 1. 사전 준비 (데스크톱/서버, Linux 권장)

- Python 3.9~3.11, x86_64 Linux (CPU만으로 충분)
- 디스크 ~5GB, 메모리 8GB+
- 인터넷(모델·의존성 다운로드)

```bash
# 격리 환경
python3 -m venv melo-convert && source melo-convert/bin/activate

# sherpa-onnx 변환 스크립트 가져오기
git clone https://github.com/k2-fsa/sherpa-onnx
cd sherpa-onnx/scripts/melo-tts

# 변환 의존성 (공식 run.sh와 동일 버전 고정)
pip install torch==2.3.1+cpu torchaudio==2.3.1+cpu \
  -f https://download.pytorch.org/whl/torch_stable.html
pip install soundfile onnx==1.15.0 onnxruntime==1.16.3

# MeloTTS 본체 + 한국어 프런트엔드 의존성
git clone https://github.com/myshell-ai/MeloTTS
pip install -e ./MeloTTS
python -m unidic download          # MeCab 사전
pip install python-mecab-ko g2pkk   # 한국어 형태소/g2p (KR 경로에 필요)
```

> 참고: `scripts/melo-tts/`에는 `export-onnx.py`(ZH+EN), `export-onnx-en.py`(EN),
> `run.sh`(오케스트레이션), `test.py`(검증), `show-info.py`가 있습니다. 먼저 `run.sh`를 읽어
> ZH+EN 변환이 동작하는지 확인한 뒤 한국어로 적응하는 것을 권장합니다.

---

## 2. 표준 흐름 이해 (ZH+EN, 그대로 동작)

`export-onnx.py`가 하는 일:

1. `TTS(language="ZH", device="cpu")`로 MeloTTS 모델 로드.
2. `eng_dict`(영어) + pinyin 분해(중국어)로 **`lexicon.txt`** 생성 (단어→음소+성조).
3. 심볼 집합을 **`tokens.txt`**(음소→정수 id)로 출력.
4. `ModelWrapper`로 모델을 감싸 `lang_id`/`tone_start`를 주입.
5. `sample_rate`, `lang_id`, `tone_start`, `bert_dim=1024`, `ja_bert_dim=768`, 라이선스 등을
   ONNX 메타데이터로 임베드.
6. `torch.onnx.export()`로 **`model.onnx`** 저장.

`dict/` 디렉터리와 `*.fst`(date/number/phone/new_heteronym)는 **중국어 jieba 분절·텍스트
정규화용**입니다. **한국어에는 불필요**하므로 한국어 모델에는 보통 포함하지 않습니다(앱도 `dict/`를
선택 사항으로 처리합니다).

---

## 3. 한국어 적응 (`export-onnx.py` 수정)

`export-onnx.py`를 복사해 `export-onnx-ko.py`로 만들고 다음을 바꿉니다.

1. **언어 로드**: `TTS(language="KR", device="cpu")`.
2. **심볼/토큰**: MeloTTS의 한국어 심볼 집합을 사용해 `tokens.txt` 생성. MeloTTS는
   `melo/text/symbols.py`와 한국어 cleaner(`melo/text/korean.py`, `g2pkk` 사용)에서 한국어
   음소를 정의합니다. ZH의 pinyin 분해 로직은 제거하고, 한국어 어휘에 대해 g2p를 돌려
   `lexicon.txt`(표기→음소열)를 만듭니다.
3. **`lang_id` / `tone_start`**: 한국어(KR) 항목 값으로 설정. MeloTTS의
   `language_id_map` / `language_tone_start_map`을 참조.
4. **BERT 차원**: 한국어 MeloTTS는 한국어 BERT(`kykim/bert-kor-base`, hidden 768)를 씁니다.
   `bert_dim`/`ja_bert_dim` 메타데이터를 한국어 구성에 맞게 설정. (런타임이 BERT를 0으로 채워도
   동작하지만 억양 품질이 떨어질 수 있음 — 위 주의 참고.)
5. **렉시콘 커버리지**: `lexicon.txt`에 없는 표기는 발음되지 않습니다. 한국어는 음절 단위 g2p로
   넓은 커버리지를 확보하거나, 자주 쓰는 어휘 사전을 추가하세요.

수정 후 실행:

```bash
python ./export-onnx-ko.py          # model.onnx, lexicon.txt, tokens.txt 생성
python ./test.py                    # (가능하면 KR용으로 수정해) 합성 음성 청취 검증
```

> 한국어 적응은 사소하지 않습니다. MeloTTS 한국어 프런트엔드의 심볼/토큰/cleaner를 export 로직과
> 정확히 일치시켜야 하며, 토큰 순서가 어긋나면 잡음만 납니다. `test.py`로 반드시 실제 음성을
> 들어보고 검증하세요.

---

## 4. 모델 디렉터리 구성 & 패키징

앱이 기대하는 **압축 해제 후 레이아웃**(see `MeloNeuralTts.kt`, `TtsTask.buildMeloVitsConfig`):

```
vits-melo-tts-ko/          # ← 최상위 디렉터리 이름 = MELO_TTS_DIR
├── model.onnx             # 필수  (MELO_TTS_ONNX)
├── tokens.txt             # 필수  (MELO_TTS_TOKENS)
├── lexicon.txt            # 필수  (MELO_TTS_LEXICON)
├── dict/                  # 선택  (MELO_TTS_DICT_DIR) — 한국어는 없어도 됨
└── README.md / LICENSE    # 선택
```

`.tar.bz2`로 묶습니다. **최상위 디렉터리 이름이 `vits-melo-tts-ko`여야** 합니다(앱의
`MELO_TTS_DIR` 상수와 일치). 다르게 만들려면 `MeloNeuralTts.kt`의 `MELO_TTS_DIR`를 함께 바꾸세요.

```bash
mkdir -p vits-melo-tts-ko
cp model.onnx tokens.txt lexicon.txt vits-melo-tts-ko/
# (선택) cp -r dict vits-melo-tts-ko/
tar cjf vits-melo-tts-ko.tar.bz2 vits-melo-tts-ko
ls -l vits-melo-tts-ko.tar.bz2     # 크기 기록 → MELO_KO_SIZE_BYTES
```

---

## 5. 호스팅 & 앱 연결

1. `vits-melo-tts-ko.tar.bz2`를 안정적인 공개 URL에 업로드(예: 자체 Hugging Face 모델 레포의
   `resolve/main/...`, GitHub Release 자산 등). **라이선스(MIT) 고지**를 함께 두세요.
2. `customtasks/tts/TtsTask.kt`의 `TODO(melo-ko)` 자리 두 상수를 채웁니다:

   ```kotlin
   private const val MELO_KO_URL = "https://.../vits-melo-tts-ko.tar.bz2"
   private const val MELO_KO_SIZE_BYTES = 1234567L   // 4절에서 기록한 실제 바이트 크기
   ```

   - 다운로드 파일명(`MELO_KO_ARCHIVE`)과 디렉터리 상수(`MELO_TTS_DIR`)는 이미 일치하도록
     설정돼 있으니, 4절에서 아카이브/디렉터리 이름을 바꾸지 않았다면 그대로 두면 됩니다.
3. URL이 채워지면 음성 어시스턴트 화면의 **"MeloTTS 한국어 음성"** 다운로드 배너가 자동으로
   나타나고(빈 URL일 땐 숨김), 받기 → 압축 해제/초기화 → 음성 선택 칩에 "MeloTTS (ko)"가
   추가됩니다. Text to Speech 화면의 모델 목록에도 즉시 노출됩니다.

코드·UI·선택·로딩 파이프라인은 이미 완성돼 있어, **위 두 상수만 채우면** 바로 동작합니다.

---

## 6. 검증 체크리스트

- [ ] `test.py`(또는 sherpa-onnx CLI)로 변환 직후 합성 음성을 청취 — 한국어가 또렷한가?
- [ ] `tar tjf vits-melo-tts-ko.tar.bz2` 최상위가 `vits-melo-tts-ko/`인가?
- [ ] 압축 해제 시 `model.onnx`/`tokens.txt`/`lexicon.txt`가 그 디렉터리 바로 아래 있는가?
- [ ] 앱에서 받기 → 준비 완료 → "MeloTTS (ko)" 선택 후 어시스턴트 답변이 한국어로 낭독되는가?
- [ ] 자주 쓰는 단어/숫자/영어 혼용 문장이 누락 없이 발음되는가? (없으면 `lexicon.txt` 보강)

---

## 참고 링크

- 변환 스크립트: <https://github.com/k2-fsa/sherpa-onnx/tree/master/scripts/melo-tts>
- MeloTTS 본체: <https://github.com/myshell-ai/MeloTTS>
- 한국어 PyTorch 모델: <https://huggingface.co/myshell-ai/MeloTTS-Korean>
- 공식 ZH+EN 변환본(레이아웃 참고): sherpa-onnx tts-models 릴리스의 `vits-melo-tts-zh_en.tar.bz2`
- sherpa-onnx TTS 문서: <https://k2-fsa.github.io/sherpa/onnx/tts/>
