#!/usr/bin/env bash
# Export an intermediate training checkpoint to a sherpa-onnx multi-speaker model + per-speaker test
# WAVs + packaged .tar.bz2 — all on CPU, so GPU training can keep running in parallel.
# Usage: bash export_intermediate.sh [G_checkpoint.pth] [out_dir]
set -uo pipefail
# Default to the NEWEST checkpoint (safe: keep_ckpts prunes oldest, never the latest).
CKPT="${1:-$(ls -t /work/run/logs/melo-ko-ms/G_*.pth 2>/dev/null | head -1)}"
OUTDIR="${2:-/work/run/out-intermediate}"
echo "using checkpoint: $CKPT"
CFG=/work/run/melo-ko-ms/config.json
SCR=/work/scripts

echo "=== exporting $CKPT -> $OUTDIR ==="
mkdir -p "$OUTDIR"; cd "$OUTDIR"
pip install -q onnx==1.15.0 onnxruntime==1.18.1 sherpa-onnx==1.13.2 >/dev/null 2>&1 || true
# Align symbols/num_languages/num_tones to the KR checkpoint (same as training) so the exported
# model + tokens.txt match the trained weights.
python "$SCR/align_kr.py" /work/run/melo-ko-ms/config.json
python "$SCR/export-onnx-ko.py" --ckpt "$CKPT" --config "$CFG" --extra-words "$SCR/extra_words.txt"
python "$SCR/show-info.py" "$OUTDIR/model.onnx" || true
echo "=== per-speaker test WAVs (sherpa-onnx) ==="
python "$SCR/test_multispeaker.py" "$OUTDIR"
echo "=== package ==="
python "$SCR/package.py" --src "$OUTDIR" --out "$OUTDIR"
echo "=== artifacts ==="
ls -lh "$OUTDIR"
