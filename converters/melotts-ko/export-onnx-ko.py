#!/usr/bin/env python3
# Copyright 2025
# SPDX-License-Identifier: MIT
#
# Convert myshell-ai/MeloTTS-Korean (PyTorch, MIT) into a sherpa-onnx VITS model.
#
# This is the Korean adaptation of the official sherpa-onnx converter
#   https://github.com/k2-fsa/sherpa-onnx/blob/master/scripts/melo-tts/export-onnx.py
# which only ships a Chinese+English (ZH) export. The graph export is identical;
# what changes for Korean is:
#   * we load TTS(language="KR") instead of "ZH",
#   * the lexicon is built from the Korean g2p frontend (g2pkk) instead of pinyin,
#     and from every Hangul syllable so coverage is guaranteed,
#   * lang_id / tone_start come from MeloTTS's "KR" entry,
#   * the zero-BERT tensors are sized from the actual checkpoint (Korean MeloTTS
#     may differ from the zh_en 1024/768 pair), and that size is written to the
#     ONNX metadata so the sherpa-onnx runtime feeds tensors of the right shape.
#
# Output (in the current directory):
#   model.onnx     the VITS graph + metadata
#   tokens.txt     phoneme symbol -> integer id
#   lexicon.txt    word/syllable -> phonemes + (global) tones
#
# These three files are exactly what the Android app expects under
# `vits-melo-tts-ko/` (see customtasks/speech/MeloNeuralTts.kt). Run package.py
# afterwards to bundle and name them correctly.
#
# IMPORTANT: sherpa-onnx zeroes the BERT input at runtime, so Korean prosody is
# somewhat flatter than the original PyTorch model. Always listen to test.wav
# (produced by test-onnx-ko.py) before shipping.

import argparse
import sys
from typing import Any, Dict, List, Optional, Tuple

import onnx
import torch
from melo.api import TTS
from melo.text import language_id_map, language_tone_start_map
from melo.text.cleaner import clean_text
from melo.text.english import eng_dict, refine_syllables

LANGUAGE = "KR"

# Modern Hangul syllable block (가..힣). Every Korean syllable lives here; adding
# them all to the lexicon guarantees the runtime can pronounce any Korean text by
# falling back to per-syllable lookup, even for words it has never seen.
HANGUL_START = 0xAC00
HANGUL_END = 0xD7A3


def generate_tokens(symbol_list: List[str]) -> None:
    """Write tokens.txt: one `symbol id` line per MeloTTS symbol.

    The symbol set already contains the Korean jamo phonemes, so this is
    identical to the official ZH exporter.
    """
    with open("tokens.txt", "w", encoding="utf-8") as f:
        for i, s in enumerate(symbol_list):
            f.write(f"{s} {i}\n")
    print(f"[tokens] wrote tokens.txt with {len(symbol_list)} symbols")


def add_new_english_words(lexicon: Dict[str, Any]) -> None:
    """Hook to extend the English (code-switching) lexicon, in-place.

    MeloTTS Korean routinely speaks embedded English words; reusing MeloTTS's
    English dictionary here lets sentences like "AI 비서" or "GPU 가속" be
    pronounced. Add your own product/loan words below. The format mirrors
    cmudict: a list of syllables, each a list of ARPAbet phones.
    See https://github.com/myshell-ai/MeloTTS/blob/main/melo/text/cmudict.rep
    """
    lexicon["kaldi"] = [["K", "AH0"], ["L", "D", "IH0"]]
    lexicon["sf"] = [["EH1", "S"], ["EH1", "F"]]
    # e.g. lexicon["gpu"] = [["JH", "IY1"], ["P", "IY1"], ["Y", "UW1"]]


def _strip_boundary(
    phones: List[str], tones: List[int]
) -> Tuple[List[str], List[int]]:
    """Drop the leading/trailing "_" boundary symbols MeloTTS g2p adds.

    The sherpa-onnx runtime inserts its own blanks/word separators between
    lexicon entries, so a per-word entry must not carry boundary markers.
    """
    while phones and phones[0] == "_":
        phones, tones = phones[1:], tones[1:]
    while phones and phones[-1] == "_":
        phones, tones = phones[:-1], tones[:-1]
    return phones, tones


def _korean_entry(word: str) -> Optional[Tuple[List[str], List[int]]]:
    """Run the MeloTTS Korean frontend on a word/syllable -> (phones, tones).

    Returns None when normalization drops the input to nothing. Tones are mapped
    into the model's GLOBAL tone space via the KR tone_start offset (Korean's
    local tones are all 0, but the embedding table is shared across languages).
    """
    try:
        _norm, phones, tones, _word2ph = clean_text(word, LANGUAGE)
    except Exception as e:  # noqa: BLE001 - one bad syllable must not abort the run
        print(f"[lexicon] skip {word!r}: {e}", file=sys.stderr)
        return None
    phones, tones = _strip_boundary(list(phones), list(tones))
    if not phones:
        return None
    offset = language_tone_start_map[LANGUAGE]
    tones = [int(t) + offset for t in tones]
    return phones, tones


def _write_entry(f, key: str, phones: List[str], tones: List[int]) -> None:
    f.write(f"{key} {' '.join(phones)} {' '.join(str(t) for t in tones)}\n")


def generate_lexicon(extra_words_file: Optional[str]) -> None:
    """Write lexicon.txt covering English, optional curated words, and all syllables."""
    seen = set()
    n = 0
    with open("lexicon.txt", "w", encoding="utf-8") as f:
        # 1) English words (code-switching). Identical to the official exporter:
        #    cmudict syllables -> MeloTTS English symbols, tones offset to EN.
        add_new_english_words(eng_dict)
        en_offset = language_tone_start_map["EN"]
        for word in eng_dict:
            key = word.lower()
            if key in seen:
                continue
            phones, tones = refine_syllables(eng_dict[word])
            tones = [int(t) + en_offset for t in tones]
            seen.add(key)
            _write_entry(f, key, phones, [t for t in tones])
            n += 1

        # 2) Optional curated multi-syllable Korean words. Running the frontend on
        #    a whole word captures in-context pronunciation (연음/경음화 etc.) that
        #    per-syllable entries miss, so these sound more natural. Provide them
        #    via --extra-words (one word per line; '#' comments allowed).
        if extra_words_file:
            with open(extra_words_file, encoding="utf-8") as wf:
                for line in wf:
                    w = line.strip()
                    if not w or w.startswith("#") or w in seen:
                        continue
                    entry = _korean_entry(w)
                    if entry is None:
                        continue
                    seen.add(w)
                    _write_entry(f, w, entry[0], entry[1])
                    n += 1
            print(f"[lexicon] added curated words from {extra_words_file}")

        # 3) Every Hangul syllable -> guaranteed coverage for unseen words.
        total = HANGUL_END - HANGUL_START + 1
        for i, code in enumerate(range(HANGUL_START, HANGUL_END + 1)):
            syl = chr(code)
            if syl in seen:
                continue
            entry = _korean_entry(syl)
            if entry is None:
                continue
            seen.add(syl)
            _write_entry(f, syl, entry[0], entry[1])
            n += 1
            if (i + 1) % 2000 == 0:
                print(f"[lexicon] syllables {i + 1}/{total} ...")
    print(f"[lexicon] wrote lexicon.txt with {n} entries")


class ModelWrapper(torch.nn.Module):
    """Wraps MeloTTS so it exports with the exact (x, x_lengths, tones, sid, ...)
    signature sherpa-onnx expects, injecting zero BERT and the per-token lang_id.

    This mirrors the official ZH ModelWrapper; the only Korean-specific change is
    that the zero-BERT dimensions are read from the loaded checkpoint instead of
    being hardcoded to 1024/768.
    """

    def __init__(self, model: "TTS"):
        super().__init__()
        self.model = model
        self.lang_id = language_id_map[model.language]

        # The text encoder projects BERT features through fixed-width Conv1d
        # layers; their in_channels are the only correct zero-BERT widths.
        enc = getattr(model.model, "enc_p", None)
        self.bert_dim = getattr(getattr(enc, "bert_proj", None), "in_channels", 1024)
        self.ja_bert_dim = getattr(
            getattr(enc, "ja_bert_proj", None), "in_channels", 768
        )
        print(
            f"[model] language=KR lang_id={self.lang_id} "
            f"bert_dim={self.bert_dim} ja_bert_dim={self.ja_bert_dim}"
        )

    def forward(
        self,
        x,
        x_lengths,
        tones,
        sid,
        noise_scale,
        length_scale,
        noise_scale_w,
        max_len=None,
    ):
        bert = torch.zeros(x.shape[0], self.bert_dim, x.shape[1], dtype=torch.float32)
        ja_bert = torch.zeros(
            x.shape[0], self.ja_bert_dim, x.shape[1], dtype=torch.float32
        )
        lang_id = torch.zeros_like(x)
        lang_id[:, 1::2] = self.lang_id
        return self.model.model.infer(
            x=x,
            x_lengths=x_lengths,
            sid=sid,
            tone=tones,
            language=lang_id,
            bert=bert,
            ja_bert=ja_bert,
            noise_scale=noise_scale,
            noise_scale_w=noise_scale_w,
            length_scale=length_scale,
        )[0]


def add_meta_data(filename: str, meta_data: Dict[str, Any]) -> None:
    """Embed metadata into the ONNX model (replacing any existing props)."""
    model = onnx.load(filename)
    while len(model.metadata_props):
        model.metadata_props.pop()
    for key, value in meta_data.items():
        meta = model.metadata_props.add()
        meta.key = key
        meta.value = str(value)
    onnx.save(model, filename)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export MeloTTS-Korean to a sherpa-onnx VITS model."
    )
    parser.add_argument(
        "--extra-words",
        default=None,
        help="optional file of curated Korean words (one per line) to add to the "
        "lexicon for more natural in-context pronunciation.",
    )
    parser.add_argument(
        "--opset",
        type=int,
        default=17,
        help="ONNX opset version (default 17 — the max torch 2.3.1 supports).",
    )
    args = parser.parse_args()

    # 1) Lexicon first so a failure here doesn't waste the (slower) model load.
    generate_lexicon(args.extra_words)

    # 2) Load the Korean checkpoint. MeloTTS downloads it from Hugging Face
    #    (myshell-ai/MeloTTS-Korean) on first use; CPU is fine.
    print("[model] loading TTS(language='KR') (downloads from Hugging Face on first run)...")
    model = TTS(language=LANGUAGE, device="cpu")
    generate_tokens(model.hps["symbols"])

    torch_model = ModelWrapper(model)

    # 3) Export the graph. Dummy inputs only fix ranks; dynamic_axes keep N/L free.
    x = torch.randint(low=1, high=10, size=(60,), dtype=torch.int64)
    x_lengths = torch.tensor([x.size(0)], dtype=torch.int64)
    sid = torch.tensor([list(model.hps.data.spk2id.values())[0]], dtype=torch.int64)
    tones = torch.zeros_like(x)
    noise_scale = torch.tensor([1.0], dtype=torch.float32)
    length_scale = torch.tensor([1.0], dtype=torch.float32)
    noise_scale_w = torch.tensor([1.0], dtype=torch.float32)
    x = x.unsqueeze(0)
    tones = tones.unsqueeze(0)

    filename = "model.onnx"
    print(f"[model] exporting {filename} (opset {args.opset})...")
    torch.onnx.export(
        torch_model,
        (x, x_lengths, tones, sid, noise_scale, length_scale, noise_scale_w),
        filename,
        opset_version=args.opset,
        input_names=[
            "x",
            "x_lengths",
            "tones",
            "sid",
            "noise_scale",
            "length_scale",
            "noise_scale_w",
        ],
        output_names=["y"],
        dynamic_axes={
            "x": {0: "N", 1: "L"},
            "x_lengths": {0: "N"},
            "tones": {0: "N", 1: "L"},
            "y": {0: "N", 1: "S", 2: "T"},
        },
    )

    # 4) Metadata. These mirror the official ZH exporter, with the Korean-specific
    #    changes called out below. The sherpa-onnx runtime reads them to drive the
    #    MeloTTS frontend:
    #      * comment must contain "melo"  -> selects the MeloTTS lexicon path
    #        (offline-tts-vits-model.cc: `comment.find("melo")`).
    #      * version must be >= 2        -> otherwise the runtime refuses to load
    #        ("Please download the latest MeloTTS model and retry").
    #      * jieba = 0                   -> Korean uses NO Chinese word segmenter;
    #        the runtime splits on whitespace and falls back to per-syllable
    #        lexicon lookup (which is why we emit every Hangul syllable). The ZH
    #        model sets jieba = 1 and ships a dict/.
    #      * bert_dim/ja_bert_dim come from the checkpoint (see ModelWrapper) so
    #        the runtime's zero-BERT tensors match this graph.
    # language MUST be "English" — NOT "Korean". This is a deliberate routing hack:
    # sherpa-onnx (through at least v1.13.2 and current master) only wires the
    # MeloTtsLexicon frontend for two cases (offline-tts-vits-impl.h):
    #   (jieba && is_melo_tts)                  -> Chinese
    #   (is_melo_tts && language == "English")  -> English
    # There is NO branch for other languages, so a model tagged language="Korean"
    # falls through to the GENERIC Lexicon, which reads our tone column as phones
    # and floods "Unknown token: 7/11". Tagging it "English" routes us into
    # MeloTtsLexicon, which splits text per UTF-8 char, matches multi-syllable words
    # via PhraseMatcher, and falls back to per-syllable lookup — exactly what our
    # all-Hangul-syllable lexicon needs. The actual language is unaffected: lang_id
    # (=KR, see ModelWrapper) is baked INTO the ONNX graph, not read from this
    # string, and the only English-specific runtime tweak (lowercase v->V) is gated
    # on language=="en" (lowercase), which this value does not match. Verified with
    # sherpa-onnx 1.13.2: Korean synthesizes correctly. If a future sherpa-onnx adds
    # a generic is_melo_tts path, this can revert to "Korean".
    meta_data = {
        "model_type": "melo-vits",
        "comment": "melo",
        "version": 2,
        "language": "English",
        "add_blank": int(model.hps.data.add_blank),
        "n_speakers": len(model.hps.data.spk2id),
        "jieba": 0,
        "sample_rate": model.hps.data.sampling_rate,
        "bert_dim": torch_model.bert_dim,
        "ja_bert_dim": torch_model.ja_bert_dim,
        "speaker_id": list(model.hps.data.spk2id.values())[0],
        "lang_id": language_id_map[LANGUAGE],
        "tone_start": language_tone_start_map[LANGUAGE],
        "url": "https://huggingface.co/myshell-ai/MeloTTS-Korean",
        "license": "MIT license",
        "description": (
            "MeloTTS is a high-quality multi-lingual text-to-speech library by "
            "MyShell.ai. Korean conversion for sherpa-onnx."
        ),
    }
    add_meta_data(filename, meta_data)
    print("[model] metadata written:")
    for k, v in meta_data.items():
        print(f"          {k} = {v}")
    print("\n[done] model.onnx, tokens.txt, lexicon.txt are ready.")
    print("       Next: python show-info.py   (sanity-check metadata)")
    print("             python test-onnx-ko.py (listen to test.wav)")
    print("             python package.py      (build vits-melo-tts-ko.tar.bz2)")


if __name__ == "__main__":
    main()
