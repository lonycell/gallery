#!/usr/bin/env bash
# Runs the whole conversion end-to-end inside the container (or any Linux shell
# where the deps are installed). Writes artifacts to $OUT_DIR.
set -euo pipefail

OUT="${OUT_DIR:-/work/out}"
mkdir -p "$OUT"
cd /work

EXTRA=""
if [ -f /work/extra_words.txt ]; then
  EXTRA="--extra-words /work/extra_words.txt"
fi

echo "==> 1/4 export-onnx-ko.py"
python export-onnx-ko.py $EXTRA

echo "==> 2/4 show-info.py (metadata sanity check)"
python show-info.py model.onnx || echo "(metadata check reported issues — review above)"

echo "==> 3/4 test-onnx-ko.py (synthesize test.wav)"
python test-onnx-ko.py --out "$OUT/test.wav" || echo "(test synthesis failed — non-fatal, but inspect)"

echo "==> 4/4 package.py (build vits-melo-tts-ko.tar.bz2)"
python package.py --src . --out "$OUT"

# Keep the raw artifacts too, so the developer can repackage or inspect.
cp -f model.onnx tokens.txt lexicon.txt "$OUT"/ 2>/dev/null || true

echo
echo "==> Done. Artifacts in $OUT:"
ls -lh "$OUT"
