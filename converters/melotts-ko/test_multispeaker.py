#!/usr/bin/env python3
# Synthesize one WAV per speaker from an exported multi-speaker model, using sherpa-onnx (the same
# engine the app uses). Lets you listen to each voice. Usage: python test_multispeaker.py <out_dir>
import os
import struct
import sys
import wave

import sherpa_onnx

out = sys.argv[1]
text = sys.argv[2] if len(sys.argv) > 2 else "안녕하세요. 만나서 반갑습니다. 오늘 날씨가 참 좋네요."

names = []
sp = os.path.join(out, "speakers.txt")
if os.path.isfile(sp):
    names = [l.strip() for l in open(sp, encoding="utf-8") if l.strip()]

cfg = sherpa_onnx.OfflineTtsConfig(
    model=sherpa_onnx.OfflineTtsModelConfig(
        vits=sherpa_onnx.OfflineTtsVitsModelConfig(
            model=os.path.join(out, "model.onnx"),
            lexicon=os.path.join(out, "lexicon.txt"),
            tokens=os.path.join(out, "tokens.txt"),
            dict_dir="",
        ),
        num_threads=2,
        provider="cpu",
        debug=False,
    )
)
tts = sherpa_onnx.OfflineTts(cfg)
n = tts.num_speakers
print(f"[test] num_speakers={n} sample_rate={tts.sample_rate}")
for sid in range(n):
    audio = tts.generate(text, sid=sid, speed=1.0)
    label = names[sid] if sid < len(names) else str(sid)
    peak = max((abs(x) for x in audio.samples), default=0.0)
    fn = os.path.join(out, f"voice_{sid}_{label}.wav")
    with wave.open(fn, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(audio.sample_rate)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in audio.samples))
    print(f"[voice {sid}] {label}: {len(audio.samples)/audio.sample_rate:.2f}s peak={peak:.3f} -> {os.path.basename(fn)}")
