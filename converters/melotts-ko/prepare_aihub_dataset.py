#!/usr/bin/env python3
# Copyright 2025
# SPDX-License-Identifier: MIT
#
# Build a MeloTTS multi-speaker training set from the AIHub dataset
#   "133. 감성 및 발화 스타일 동시 고려 음성합성 데이터"
# (Training/{01.원천데이터=audio zips, 02.라벨링데이터=label zips}).
#
# Each `TS_<style>_NNN.zip` is ONE reciter's audio (44.1 kHz / mono / 16-bit studio WAVs, one per
# utterance) and the matching `TL_<style>_NNN.zip` holds JSON labels. In each label JSON object,
# `sentences[i].voice_piece.filename` is the WAV name and `.tr` is the transcript; the object-level
# `reciter` {id, gender, age} identifies the speaker. We keep ALL emotions per speaker (one voice =
# one sid), as chosen.
#
# Output (default V:\data-ko\run\melo-ko-ms):
#   wavs/<speaker>/<file>.wav        extracted audio
#   metadata.list                    one line per utterance:  <abs_wav>|<speaker>|KR|<text>
#
# This step is pure stdlib (zipfile/json) — no GPU, no MeCab. Run it on the host Python.
#
# Example:
#   python prepare_aihub_dataset.py            # uses the default 6 speakers below
#   python prepare_aihub_dataset.py --speakers 001,017,021 --limit-per-speaker 300

import argparse
import json
import os
import shutil
import sys
import zipfile

# The Windows console is cp949 by default; our prints include Korean speaker keys and an em-dash.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:  # noqa: BLE001
    pass

DEFAULT_DATASET = (
    r"V:\data-ko\133.감성 및 발화 스타일 동시 고려 음성합성 데이터"
    r"\01-1.정식개방데이터\Training"
)
DEFAULT_OUT = r"V:\data-ko\run\melo-ko-ms"
DEFAULT_STYLE = "구연체"
# Balanced 6 speakers (reciter numbers within the 구연체 style): 3 male / 3 female, ages 20–50.
DEFAULT_SPEAKERS = ["001", "017", "021", "029", "032", "039"]

GENDER_KR = {"MALE": "남", "FEMALE": "여"}


def speaker_key(reciter: dict) -> str:
    """Stable, human-friendly speaker label, e.g. '남20_001'. reciter.id is globally unique."""
    g = GENDER_KR.get(str(reciter.get("gender", "")), "기타")
    age = reciter.get("age", 0)
    rid = reciter.get("id", 0)
    return f"{g}{age}_{int(rid):03d}"


def read_label_zip(path: str):
    """Yield (wav_basename, text, speaker_key, reciter) for every utterance in a TL_*.zip."""
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if not name.lower().endswith(".json"):
                continue
            with z.open(name) as f:
                try:
                    objs = json.loads(f.read().decode("utf-8"))
                except Exception as e:  # noqa: BLE001
                    print(f"  [warn] bad JSON {name}: {e}")
                    continue
            for obj in objs:
                reciter = obj.get("reciter", {})
                spk = speaker_key(reciter)
                for s in obj.get("sentences", []):
                    vp = s.get("voice_piece", {})
                    fn = vp.get("filename", "")
                    text = (vp.get("tr") or s.get("origin_text") or "").strip()
                    if fn and text:
                        yield os.path.basename(fn), text, spk, reciter


def free_gb(path: str) -> float:
    try:
        return shutil.disk_usage(path).free / 1e9
    except Exception:  # noqa: BLE001
        return -1.0


def main() -> None:
    p = argparse.ArgumentParser(description="Prepare AIHub 133 data as a MeloTTS metadata.list.")
    p.add_argument("--dataset", default=DEFAULT_DATASET, help="...\\Training folder")
    p.add_argument("--style", default=DEFAULT_STYLE)
    p.add_argument(
        "--speakers",
        default=",".join(DEFAULT_SPEAKERS),
        help="comma-separated reciter numbers within the style (e.g. 001,017,021)",
    )
    p.add_argument("--out", default=DEFAULT_OUT)
    p.add_argument(
        "--limit-per-speaker",
        type=int,
        default=0,
        help="cap utterances per speaker (0 = all). Use a small value for a quick test.",
    )
    args = p.parse_args()

    src_dir = os.path.join(args.dataset, "01.원천데이터")
    lbl_dir = os.path.join(args.dataset, "02.라벨링데이터")
    speakers = [s.strip() for s in args.speakers.split(",") if s.strip()]
    os.makedirs(args.out, exist_ok=True)
    wavs_root = os.path.join(args.out, "wavs")
    os.makedirs(wavs_root, exist_ok=True)

    print(f"[disk] free space — out drive: {free_gb(args.out):.1f} GB")
    print(f"[plan] style={args.style}  speakers={speakers}  out={args.out}")

    metadata_path = os.path.join(args.out, "metadata.list")
    total = 0
    per_speaker = {}
    with open(metadata_path, "w", encoding="utf-8") as meta:
        for num in speakers:
            ts = os.path.join(src_dir, f"TS_{args.style}_{num}.zip")
            tl = os.path.join(lbl_dir, f"TL_{args.style}_{num}.zip")
            if not (os.path.isfile(ts) and os.path.isfile(tl)):
                print(f"[skip] missing zip for {args.style}_{num}: TS={os.path.isfile(ts)} TL={os.path.isfile(tl)}")
                continue

            # 1) Read labels: wav basename -> (text, speaker)
            mapping = {}
            spk_name = None
            for base, text, spk, reciter in read_label_zip(tl):
                mapping[base] = (text, spk)
                spk_name = spk
            if not mapping:
                print(f"[skip] no labeled utterances in {tl}")
                continue
            spk_dir = os.path.join(wavs_root, spk_name)
            os.makedirs(spk_dir, exist_ok=True)

            # 2) Extract matching WAVs and write metadata lines.
            written = 0
            with zipfile.ZipFile(ts) as z:
                for entry in z.namelist():
                    if not entry.lower().endswith(".wav"):
                        continue
                    base = os.path.basename(entry)
                    hit = mapping.get(base)
                    if hit is None:
                        continue
                    text, spk = hit
                    out_wav = os.path.join(spk_dir, base)
                    if not os.path.exists(out_wav):
                        with z.open(entry) as zf, open(out_wav, "wb") as out:
                            shutil.copyfileobj(zf, out)
                    meta.write(f"{os.path.abspath(out_wav)}|{spk}|KR|{text}\n")
                    written += 1
                    total += 1
                    if args.limit_per_speaker and written >= args.limit_per_speaker:
                        break
            per_speaker[spk_name] = written
            print(f"[ok] {args.style}_{num} -> speaker '{spk_name}': {written} utterances")
            if free_gb(args.out) < 5:
                print("[disk] WARNING: < 5 GB free on the output drive. Consider --out W:\\... .")

    print("\n=== summary ===")
    for k, v in per_speaker.items():
        print(f"  {k}: {v}")
    print(f"  speakers: {len(per_speaker)}   utterances: {total}")
    print(f"  metadata.list: {metadata_path}")
    print("\nNext: feed this to MeloTTS preprocess_text.py (builds train/val/config with spk2id),")
    print("then fine-tune from the KR checkpoint. (Requires the GPU training env.)")


if __name__ == "__main__":
    main()
