#!/usr/bin/env bash
# Diagnostic: test whether disabling fp16 (and batch_size=2) fixes the VITS spline crash.
# Patches config, makes train.py print real tracebacks, runs ~150s, reports progress + any error.
set -uo pipefail
python - <<'PY'
import json
p = "/work/run/melo-ko-ms/config.json"
c = json.load(open(p, encoding="utf-8"))
c["train"]["fp16_run"] = False
c["train"]["batch_size"] = 2
json.dump(c, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("patched: fp16_run=False batch_size=2")
PY
pip install -q "matplotlib<3.8" >/dev/null 2>&1 && echo "matplotlib<3.8 installed"
sed -i 's/print(e)/__import__("traceback").print_exc()/g' /opt/MeloTTS/melo/train.py
cd /opt/MeloTTS/melo
rm -rf logs && ln -s /work/run/logs logs
timeout 200 torchrun --nproc_per_node=1 --max-restarts 0 --master_port=10903 \
  train.py --c /work/run/melo-ko-ms/config.json --model melo-ko-ms 2>&1 \
  | tr '\r' '\n' > /work/run/diag.log || true
echo "===== spline crashes? (want 0) ====="; grep -c "numel() == 0" /work/run/diag.log || true
echo "===== tostring_rgb errors? (want 0) ====="; grep -c "tostring_rgb" /work/run/diag.log || true
echo "===== training progress (want steps > 0) ====="; grep -aoE "[0-9]+/[0-9]+ \[[0-9]" /work/run/diag.log | tail -6
echo "===== loss / eval / saving markers ====="; grep -aiE "Losses|loss_disc|loss_gen|Saving|Evaluating|====> Epoch" /work/run/diag.log | tail -8
echo "===== any other traceback ====="; grep -aiE "Error:|Exception" /work/run/diag.log | grep -avE "FutureWarning" | tail -5
