#!/usr/bin/env python3
# Copyright 2025
# SPDX-License-Identifier: MIT
#
# Verify a converted MeloTTS-Korean sherpa-onnx model by synthesizing a WAV file
# WITHOUT needing PyTorch or MeloTTS — it uses only onnxruntime + the generated
# tokens.txt / lexicon.txt, exactly the way the on-device sherpa-onnx runtime
# does. If this produces clear Korean speech, the model is good to ship.
#
# This mirrors the on-device path: split text on whitespace, look each word up in
# the lexicon, fall back to per-syllable lookup for unknown words (Korean uses no
# Chinese segmenter -> jieba=0), insert blanks if the model uses add_blank.
#
# Usage:
#   python test-onnx-ko.py
#   python test-onnx-ko.py --text "원하는 한국어 문장" --out hello.wav

import argparse
from typing import Dict, List, Tuple

import onnxruntime as ort
import soundfile as sf
import torch

DEFAULT_TEXT = "안녕하세요. 만나서 반갑습니다. 오늘 날씨가 참 좋네요."


class Lexicon:
    """Loads tokens.txt + lexicon.txt and converts Korean text to phone/tone ids.

    Word lookup first, then per-syllable fallback, then bare-token fallback for
    punctuation. This matches what the sherpa-onnx MeloTTS frontend does for a
    jieba=0 (non-Chinese) model.
    """

    def __init__(self, lexicon_filename: str, tokens_filename: str):
        self.tokens: Dict[str, int] = {}
        with open(tokens_filename, encoding="utf-8") as f:
            for line in f:
                parts = line.split()
                if len(parts) != 2:
                    continue
                s, i = parts
                self.tokens[s] = int(i)

        self.lexicon: Dict[str, Tuple[List[int], List[int]]] = {}
        with open(lexicon_filename, encoding="utf-8") as f:
            for line in f:
                splits = line.split()
                if not splits:
                    continue
                word = splits[0]
                rest = splits[1:]
                assert len(rest) % 2 == 0, line
                half = len(rest) // 2
                phones = [self.tokens[p] for p in rest[:half] if p in self.tokens]
                tones = [int(t) for t in rest[half:]]
                if len(phones) != len(tones):
                    # A phone not in tokens.txt -> skip the malformed entry.
                    continue
                self.lexicon[word] = (phones, tones)

        # Blank/space separator between words.
        self.space = ([self.tokens["_"]], [0]) if "_" in self.tokens else ([], [])

    def _lookup_char(self, ch: str) -> Tuple[List[int], List[int]]:
        if ch in self.lexicon:
            return self.lexicon[ch]
        if ch in self.tokens:  # punctuation present as a bare token
            return ([self.tokens[ch]], [0])
        return ([], [])

    def convert(self, text: str) -> Tuple[List[int], List[int]]:
        phones: List[int] = []
        tones: List[int] = []
        for word in text.split():
            if phones:
                phones += self.space[0]
                tones += self.space[1]
            if word in self.lexicon:
                p, t = self.lexicon[word]
                phones += p
                tones += t
            else:
                for ch in word:
                    p, t = self._lookup_char(ch)
                    phones += p
                    tones += t
        return phones, tones


class OnnxModel:
    def __init__(self, filename: str):
        opts = ort.SessionOptions()
        opts.inter_op_num_threads = 1
        opts.intra_op_num_threads = 4
        self.session = ort.InferenceSession(
            filename, sess_options=opts, providers=["CPUExecutionProvider"]
        )
        meta = self.session.get_modelmeta().custom_metadata_map
        self.add_blank = int(meta.get("add_blank", "1"))
        self.sample_rate = int(meta["sample_rate"])
        self.speaker_id = int(meta.get("speaker_id", "0"))
        print(f"[test] sample_rate={self.sample_rate} add_blank={self.add_blank} "
              f"speaker_id={self.speaker_id} is_melo={'melo' in meta.get('comment', '')}")

    def __call__(self, phones: List[int], tones: List[int]):
        x = torch.tensor(phones, dtype=torch.int64).unsqueeze(0)
        tones_t = torch.tensor(tones, dtype=torch.int64).unsqueeze(0)
        sid = torch.tensor([self.speaker_id], dtype=torch.int64)
        noise_scale = torch.tensor([0.6], dtype=torch.float32)
        length_scale = torch.tensor([1.0], dtype=torch.float32)
        noise_scale_w = torch.tensor([0.8], dtype=torch.float32)
        x_lengths = torch.tensor([x.shape[-1]], dtype=torch.int64)
        y = self.session.run(
            ["y"],
            {
                "x": x.numpy(),
                "x_lengths": x_lengths.numpy(),
                "tones": tones_t.numpy(),
                "sid": sid.numpy(),
                "noise_scale": noise_scale.numpy(),
                "noise_scale_w": noise_scale_w.numpy(),
                "length_scale": length_scale.numpy(),
            },
        )[0]
        return y[0][0]


def main() -> None:
    parser = argparse.ArgumentParser(description="Synthesize Korean speech from the converted model.")
    parser.add_argument("--model", default="model.onnx")
    parser.add_argument("--tokens", default="tokens.txt")
    parser.add_argument("--lexicon", default="lexicon.txt")
    parser.add_argument("--text", default=DEFAULT_TEXT)
    parser.add_argument("--out", default="test.wav")
    args = parser.parse_args()

    lexicon = Lexicon(args.lexicon, args.tokens)
    phones, tones = lexicon.convert(args.text)
    if not phones:
        raise SystemExit("[test] no phones produced — check tokens.txt/lexicon.txt")

    model = OnnxModel(args.model)
    if model.add_blank:
        new_phones = [0] * (2 * len(phones) + 1)
        new_tones = [0] * (2 * len(tones) + 1)
        new_phones[1::2] = phones
        new_tones[1::2] = tones
        phones, tones = new_phones, new_tones

    y = model(phones, tones)
    sf.write(args.out, y, model.sample_rate)
    dur = len(y) / model.sample_rate
    print(f"[test] wrote {args.out} ({dur:.2f}s). Listen to it: is the Korean clear?")
    print(f"[test] text: {args.text}")


if __name__ == "__main__":
    main()
