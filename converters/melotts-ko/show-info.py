#!/usr/bin/env python3
# Copyright 2025
# SPDX-License-Identifier: MIT
#
# Inspect a converted model.onnx: print its inputs/outputs and ALL metadata, and
# sanity-check the values the sherpa-onnx MeloTTS runtime depends on. Use this to
# confirm a conversion before packaging.
#
# Usage:  python show-info.py [model.onnx]

import sys

import onnxruntime as ort

REQUIRED = {
    "comment": "must contain 'melo' (selects the MeloTTS frontend)",
    "version": "must be >= 2 (older versions are rejected by the runtime)",
    "sample_rate": "synthesis sample rate",
    "add_blank": "whether to interleave blank tokens",
    "jieba": "should be 0 for Korean (no Chinese segmenter)",
    "bert_dim": "zero-BERT width fed by the runtime",
    "ja_bert_dim": "zero-BERT (ja) width fed by the runtime",
    "lang_id": "MeloTTS language id for KR",
    "tone_start": "global tone offset for KR",
    "speaker_id": "default speaker",
}


def main() -> None:
    filename = sys.argv[1] if len(sys.argv) > 1 else "model.onnx"
    session = ort.InferenceSession(filename, providers=["CPUExecutionProvider"])

    print(f"=== {filename} ===\n")
    print("Inputs:")
    for i in session.get_inputs():
        print(f"  {i.name:14s} {i.type:18s} {i.shape}")
    print("\nOutputs:")
    for o in session.get_outputs():
        print(f"  {o.name:14s} {o.type:18s} {o.shape}")

    meta = session.get_modelmeta().custom_metadata_map
    print("\nMetadata:")
    for k in sorted(meta):
        print(f"  {k:14s} = {meta[k]}")

    print("\nChecks:")
    ok = True
    for key, why in REQUIRED.items():
        val = meta.get(key)
        if val is None:
            print(f"  [MISSING] {key:12s} — {why}")
            ok = False
            continue
        note = ""
        if key == "comment" and "melo" not in val:
            note = "  <-- ERROR: must contain 'melo'"
            ok = False
        if key == "version" and val.isdigit() and int(val) < 2:
            note = "  <-- ERROR: must be >= 2"
            ok = False
        if key == "jieba" and val not in ("0", "1"):
            note = "  <-- unexpected"
        print(f"  [ok]      {key:12s} = {val}{note}")

    print("\nResult:", "PASS — looks like a valid MeloTTS Korean model."
          if ok else "FAIL — fix the issues above before packaging.")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
