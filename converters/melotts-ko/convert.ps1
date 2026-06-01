# One-command MeloTTS-Korean -> sherpa-onnx conversion on Windows, via Docker.
#
# This is the easiest path on a Windows dev PC: it builds a Linux image with the
# whole conversion stack (torch CPU, MeloTTS, g2pkk, python-mecab-ko) and runs
# the full pipeline, leaving the artifacts in .\out\.
#
#   PS> .\convert.ps1
#
# Output (in .\out\): vits-melo-tts-ko.tar.bz2, test.wav, model.onnx, tokens.txt,
# lexicon.txt, CONSTANTS.txt. Listen to test.wav, then host the .tar.bz2 and run
# set_app_constants.py (see README).
#
# NOTE: we do NOT use `$ErrorActionPreference = 'Stop'`. `docker` writes its normal
# build/run progress to stderr; under a non-interactive/redirected host PowerShell
# turns native stderr into errors, and 'Stop' would abort on docker's first
# (harmless) stderr line. We rely on $LASTEXITCODE checks instead, which reflect
# docker's real exit status.
$ErrorActionPreference = "Continue"

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$out = Join-Path $here "out"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Error "Docker not found. Install Docker Desktop, or use WSL + convert.sh (see README)."
  exit 1
}

New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host "==> Building image 'melotts-ko-converter' (first build downloads ~GBs; later builds are cached)..."
docker build -t melotts-ko-converter $here
if ($LASTEXITCODE -ne 0) { Write-Error "docker build failed."; exit 1 }

Write-Host "==> Running conversion (downloads the Korean model from Hugging Face on first run)..."
docker run --rm -e OUT_DIR=/work/out -v "${out}:/work/out" melotts-ko-converter
if ($LASTEXITCODE -ne 0) { Write-Error "conversion failed."; exit 1 }

Write-Host ""
Write-Host "==> Done. Artifacts:"
Get-ChildItem $out | Format-Table Name, Length -AutoSize

$constants = Join-Path $out "CONSTANTS.txt"
if (Test-Path $constants) {
  Write-Host "`n==> App constants (also in out\CONSTANTS.txt):`n"
  Get-Content $constants
}
Write-Host "`nNext: listen to out\test.wav, host out\vits-melo-tts-ko.tar.bz2, then run:"
Write-Host "  python set_app_constants.py --url <hosted-url> --archive out\vits-melo-tts-ko.tar.bz2"
