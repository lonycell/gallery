#!/usr/bin/env bash
# One-command MeloTTS-Korean -> sherpa-onnx conversion on Linux / WSL / macOS,
# WITHOUT Docker: creates a local venv, installs the stack, runs the pipeline.
#
#   ./convert.sh            # artifacts -> ./out
#   ./convert.sh mydir      # artifacts -> ./mydir
#
# On a Windows dev PC, prefer convert.ps1 (Docker) unless you run this from WSL.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
OUT="${1:-out}"

if [ ! -d .venv ]; then
  echo "==> Creating venv (.venv)"
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install --upgrade pip

echo "==> Installing pinned conversion deps"
pip install -r requirements.txt

if [ ! -d MeloTTS ]; then
  echo "==> Cloning MeloTTS"
  git clone --depth 1 https://github.com/myshell-ai/MeloTTS
fi
echo "==> Installing MeloTTS"
pip install ./MeloTTS
python -m unidic download || true

mkdir -p "$OUT"
EXTRA=""
[ -f extra_words.txt ] && EXTRA="--extra-words extra_words.txt"

echo "==> export-onnx-ko.py"
python export-onnx-ko.py $EXTRA
echo "==> show-info.py"
python show-info.py model.onnx || true
echo "==> test-onnx-ko.py"
python test-onnx-ko.py --out "$OUT/test.wav" || true
echo "==> package.py"
python package.py --src . --out "$OUT"
cp -f model.onnx tokens.txt lexicon.txt "$OUT"/ 2>/dev/null || true

echo
echo "==> Done. Artifacts in $OUT:"
ls -lh "$OUT"
echo
echo "Next: listen to $OUT/test.wav, host $OUT/vits-melo-tts-ko.tar.bz2, then:"
echo "  python set_app_constants.py --url <hosted-url> --archive $OUT/vits-melo-tts-ko.tar.bz2"
