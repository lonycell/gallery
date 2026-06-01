#!/usr/bin/env python3
# Copyright 2025
# SPDX-License-Identifier: MIT
#
# Bundle the converted artifacts into the exact archive the Android app expects:
#
#   vits-melo-tts-ko/            <- top-level dir name == MELO_TTS_DIR
#   ├── model.onnx              (required)
#   ├── tokens.txt              (required)
#   ├── lexicon.txt             (required)
#   ├── dict/                   (optional; Korean usually omits it)
#   └── LICENSE                 (MIT notice, included automatically)
#
# packed as vits-melo-tts-ko.tar.bz2. The names here must match the constants in
# customtasks/speech/MeloNeuralTts.kt (MELO_TTS_DIR / _ONNX / _TOKENS / _LEXICON
# / _DICT_DIR). After building, it prints the byte size and the exact Kotlin
# constants to paste into TtsTask.kt — or run set_app_constants.py to patch them.
#
# Uses Python's tarfile so it runs identically on Windows, macOS, and Linux.
#
# Usage:
#   python package.py                       # uses ./model.onnx etc. in CWD
#   python package.py --src out --out dist  # custom dirs

import argparse
import os
import tarfile

# These MUST equal the constants in MeloNeuralTts.kt.
DIR_NAME = "vits-melo-tts-ko"
ONNX = "model.onnx"
TOKENS = "tokens.txt"
LEXICON = "lexicon.txt"
DICT_DIR = "dict"
ARCHIVE = f"{DIR_NAME}.tar.bz2"

MIT_LICENSE = """MeloTTS-Korean — converted to sherpa-onnx VITS format.

Source model: https://huggingface.co/myshell-ai/MeloTTS-Korean
MeloTTS by MyShell.ai, released under the MIT License.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the inclusion of the above copyright/permission notice.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
"""


def main() -> None:
    parser = argparse.ArgumentParser(description="Package the converted model into a sherpa-onnx archive.")
    parser.add_argument("--src", default=".", help="directory containing model.onnx/tokens.txt/lexicon.txt")
    parser.add_argument("--out", default=".", help="directory to write the .tar.bz2 into")
    args = parser.parse_args()

    required = [ONNX, TOKENS, LEXICON]
    missing = [n for n in required if not os.path.isfile(os.path.join(args.src, n))]
    if missing:
        raise SystemExit(
            f"[package] missing required files in {args.src!r}: {missing}\n"
            f"           run export-onnx-ko.py first."
        )

    os.makedirs(args.out, exist_ok=True)
    archive_path = os.path.join(args.out, ARCHIVE)

    def arc(name: str) -> str:
        # Force the top-level directory name regardless of where src points.
        return f"{DIR_NAME}/{name}"

    print(f"[package] building {archive_path} ...")
    with tarfile.open(archive_path, "w:bz2") as tar:
        for name in required:
            tar.add(os.path.join(args.src, name), arcname=arc(name))
            print(f"          + {arc(name)}")

        dict_path = os.path.join(args.src, DICT_DIR)
        if os.path.isdir(dict_path):
            tar.add(dict_path, arcname=arc(DICT_DIR))
            print(f"          + {arc(DICT_DIR)}/ (optional)")

        # Embed the MIT notice so the hosted archive carries its license.
        license_tmp = os.path.join(args.out, "_LICENSE.tmp")
        with open(license_tmp, "w", encoding="utf-8") as lf:
            lf.write(MIT_LICENSE)
        tar.add(license_tmp, arcname=arc("LICENSE"))
        os.remove(license_tmp)
        print(f"          + {arc('LICENSE')}")

    size = os.path.getsize(archive_path)
    print(f"\n[package] done: {archive_path}")
    print(f"[package] size: {size} bytes ({size / 1024 / 1024:.2f} MiB)")

    # Emit a constants file the developer (or set_app_constants.py) can use.
    constants = (
        "// Paste into customtasks/tts/TtsTask.kt (replace the TODO(melo-ko) lines):\n"
        f'private const val MELO_KO_URL = "" // <-- set to your hosted {ARCHIVE} URL\n'
        f"private const val MELO_KO_SIZE_BYTES = {size}L\n"
    )
    constants_path = os.path.join(args.out, "CONSTANTS.txt")
    with open(constants_path, "w", encoding="utf-8") as cf:
        cf.write(constants)

    print("\n" + "=" * 70)
    print("Next steps")
    print("=" * 70)
    print(f"1. Verify archive layout:  tar tjf {ARCHIVE}")
    print(f"   (top entry must be:     {DIR_NAME}/)")
    print(f"2. Upload {ARCHIVE} to a public URL (Hugging Face / GitHub Release).")
    print("3. Fill the app constants (size already known):")
    print()
    print(constants)
    print(f"   ...or run:  python set_app_constants.py --url <hosted-url> "
          f"--archive {archive_path}")
    print(f"   (size and the snippet above are also saved to {constants_path})")


if __name__ == "__main__":
    main()
