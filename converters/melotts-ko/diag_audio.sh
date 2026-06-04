#!/usr/bin/env bash
set -uo pipefail
pip install -q onnxruntime==1.18.1 >/dev/null 2>&1 || true
CKPT=$(ls -t /work/run/logs/melo-ko-ms/G_*.pth | head -1)
echo "=== checkpoint: $CKPT ==="
echo "=== exported ONNX metadata ==="
python "/work/scripts/show-info.py" /work/run/out-latest/model.onnx 2>/dev/null | grep -iE "sample_rate|n_speakers|language|version|lang_id|tone_start|comment|jieba"
echo "=== MeloTTS PyTorch-direct synthesis (reference) ==="
python - "$CKPT" <<'PY'
import sys
from melo.api import TTS
import soundfile as sf
ckpt = sys.argv[1]
m = TTS(language="KR", device="cpu", config_path="/work/run/melo-ko-ms/config.json", ckpt_path=ckpt)
print("hps.data.sampling_rate =", m.hps.data.sampling_rate)
print("hps.data.spk2id        =", dict(m.hps.data.spk2id))
print("hps filter/hop/win/n_mel=",
      m.hps.data.filter_length, m.hps.data.hop_length, m.hps.data.win_length, m.hps.data.n_mel_channels)
sid = list(m.hps.data.spk2id.values())[0]
spk = list(m.hps.data.spk2id.keys())[0]
m.tts_to_file("안녕하세요. 만나서 반갑습니다. 오늘 날씨가 참 좋네요.", sid,
              "/work/run/out-latest/ref_melo_%s.wav" % spk, speed=1.0)
d, sr = sf.read("/work/run/out-latest/ref_melo_%s.wav" % spk)
print("MeloTTS-direct wav: sr=%d dur=%.2fs peak=%.3f file=ref_melo_%s.wav" % (sr, len(d)/sr, abs(d).max(), spk))
PY
