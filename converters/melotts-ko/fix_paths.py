#!/usr/bin/env python3
# Rewrite the wav paths in a MeloTTS metadata.list from host (Windows) paths to container paths,
# writing a new file. prepare_aihub_dataset.py records absolute host paths (V:\data-ko\run\...);
# inside the training container that mount is /work/run, so we remap before preprocess/train.
#
# Usage: python fix_paths.py <in_metadata> <out_metadata> <host_prefix> <container_prefix>
#   e.g. python fix_paths.py metadata.list metadata.container.list "V:\data-ko\run" /work/run
import sys

src, dst, host_prefix, cont_prefix = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
host_norm = host_prefix.replace("\\", "/").rstrip("/")

n = 0
with open(src, encoding="utf-8") as fin, open(dst, "w", encoding="utf-8") as fout:
    for line in fin:
        line = line.rstrip("\n")
        if not line:
            continue
        parts = line.split("|")
        wav = parts[0].replace("\\", "/")
        if wav.lower().startswith(host_norm.lower()):
            wav = cont_prefix.rstrip("/") + wav[len(host_norm):]
        parts[0] = wav
        fout.write("|".join(parts) + "\n")
        n += 1
print(f"[fix_paths] rewrote {n} lines -> {dst}")
