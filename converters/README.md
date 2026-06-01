# converters/

개발용 PC에서 1회 실행해 **온디바이스용 모델 리소스를 생성**하는 도구 모음입니다. 변환 결과물은
용량이 크므로 저장소에 커밋하지 않고(각 도구의 `.gitignore` 참고) 외부에 호스팅한 뒤, 앱의 상수에
URL을 채워 사용합니다.

| 도구 | 용도 |
| --- | --- |
| [`melotts-ko/`](melotts-ko/) | **MeloTTS(한국어) → sherpa-onnx VITS** 변환. 앱의 음성 어시스턴트 · Text to Speech 화면용 "MeloTTS (ko)" 음성을 만든다. Windows에서 `convert.ps1` 한 줄. |

각 폴더의 `README.md`에 상세 절차가 있습니다.
