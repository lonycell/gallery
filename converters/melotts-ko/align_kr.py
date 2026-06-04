#!/usr/bin/env python3
# Align the installed MeloTTS symbol space to the official KR checkpoint so its pretrained weights
# load correctly. The installed code (newer) has a different symbol order + num_languages than the
# published checkpoints, which scrambles the Korean phoneme embeddings on load -> unintelligible
# fine-tunes. We overwrite `symbols`, `num_languages`, `num_tones` in EVERY melo/text/symbols.py
# (train uses /opt copy, api uses site-packages copy) and in the training config.json, with the
# values from the KR config that the checkpoint was trained with.
#
# Usage: python align_kr.py [config.json]
import glob
import json
import subprocess
import sys

from cached_path import cached_path
from melo.download_utils import DOWNLOAD_CONFIG_URLS

kr = json.load(open(cached_path(DOWNLOAD_CONFIG_URLS["KR"])))
syms = kr["symbols"]
num_languages = int(kr.get("num_languages", 10))
num_tones = int(kr.get("num_tones", 16))
print(f"[align] KR symbols={len(syms)} num_languages={num_languages} num_tones={num_tones} "
      f"(jamo 'ᄀ' at idx {syms.index('ᄀ') if 'ᄀ' in syms else -1})")

override = (
    "\n# === KR-checkpoint compatibility override (added by align_kr.py) ===\n"
    f"symbols = {syms!r}\n"
    f"num_languages = {num_languages}\n"
    f"num_tones = {num_tones}\n"
)

files = subprocess.check_output(
    "find / -path '*/melo/text/symbols.py' 2>/dev/null", shell=True
).decode().split()
for f in files:
    txt = open(f, encoding="utf-8").read()
    if "KR-checkpoint compatibility override" not in txt:
        open(f, "a", encoding="utf-8").write(override)
    print(f"[align] patched {f}")

if len(sys.argv) > 1:
    cp = sys.argv[1]
    c = json.load(open(cp, encoding="utf-8"))
    c["symbols"] = syms
    c["num_languages"] = num_languages
    c["num_tones"] = num_tones
    json.dump(c, open(cp, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"[align] patched config {cp}")

# Verify what a fresh import sees.
import importlib
import melo.text.symbols as ms
importlib.reload(ms)
print(f"[align] verify: num_languages={ms.num_languages} len(symbols)={len(ms.symbols)} "
      f"'ᄀ'@{ms.symbols.index('ᄀ') if 'ᄀ' in ms.symbols else -1}")
