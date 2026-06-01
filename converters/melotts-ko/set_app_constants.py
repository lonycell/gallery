#!/usr/bin/env python3
# Copyright 2025
# SPDX-License-Identifier: MIT
#
# Convenience: patch the two MELO_KO constants in the Android app's TtsTask.kt so
# the "MeloTTS (ko)" voice goes live. Computes the archive size for you and sets
# the hosted URL. Prints a diff and asks nothing else — the rest of the pipeline
# (UI, download, unpack, selection) is already wired in the app.
#
# Usage:
#   python set_app_constants.py --url https://.../vits-melo-tts-ko.tar.bz2 \
#                               --archive vits-melo-tts-ko.tar.bz2
#   python set_app_constants.py --url <url> --size 12345678   # if archive absent

import argparse
import os
import re
import sys

# TtsTask.kt location relative to the repo root.
TTS_TASK_REL = os.path.join(
    "Android", "src", "app", "src", "main", "java", "com", "google", "ai",
    "edge", "gallery", "customtasks", "tts", "TtsTask.kt",
)

URL_RE = re.compile(r'(private const val MELO_KO_URL\s*=\s*)"[^"]*"(.*)')
SIZE_RE = re.compile(r'(private const val MELO_KO_SIZE_BYTES\s*=\s*)\d+L(.*)')


def find_repo_root(start: str) -> str:
    """Walk upward from `start` until a directory containing TtsTask.kt is found."""
    cur = os.path.abspath(start)
    while True:
        if os.path.isfile(os.path.join(cur, TTS_TASK_REL)):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            raise SystemExit(
                "[patch] could not locate TtsTask.kt by walking up from "
                f"{start!r}. Pass --tts-task <path> explicitly."
            )
        cur = parent


def main() -> None:
    parser = argparse.ArgumentParser(description="Patch MELO_KO_URL / MELO_KO_SIZE_BYTES in TtsTask.kt.")
    parser.add_argument("--url", required=True, help="public URL of the hosted .tar.bz2")
    parser.add_argument("--archive", default=None, help="path to the .tar.bz2 (to read its size)")
    parser.add_argument("--size", type=int, default=None, help="archive size in bytes (if --archive not given)")
    parser.add_argument("--tts-task", default=None, help="explicit path to TtsTask.kt")
    args = parser.parse_args()

    if args.size is None:
        if not args.archive or not os.path.isfile(args.archive):
            raise SystemExit("[patch] provide --size, or --archive pointing to the built .tar.bz2")
        args.size = os.path.getsize(args.archive)

    if args.tts_task:
        path = args.tts_task
        if not os.path.isfile(path):
            raise SystemExit(f"[patch] no such file: {path}")
    else:
        root = find_repo_root(os.path.dirname(os.path.abspath(__file__)))
        path = os.path.join(root, TTS_TASK_REL)

    with open(path, encoding="utf-8") as f:
        text = f.read()

    if not URL_RE.search(text) or not SIZE_RE.search(text):
        raise SystemExit(
            "[patch] could not find the MELO_KO_URL / MELO_KO_SIZE_BYTES lines in "
            f"{path}. Has the file changed? Patch it by hand."
        )

    new = URL_RE.sub(rf'\g<1>"{args.url}"\2', text)
    new = SIZE_RE.sub(rf"\g<1>{args.size}L\2", new)

    if new == text:
        print("[patch] no change needed (values already set).")
        return

    with open(path, "w", encoding="utf-8") as f:
        f.write(new)

    print(f"[patch] updated {path}")
    print(f"          MELO_KO_URL        = \"{args.url}\"")
    print(f"          MELO_KO_SIZE_BYTES = {args.size}L")
    print("[patch] Rebuild the app - the 'MeloTTS (ko)' voice download will now appear.")


if __name__ == "__main__":
    main()
