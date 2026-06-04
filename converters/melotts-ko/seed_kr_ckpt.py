#!/usr/bin/env python3
# Seed a multi-speaker fine-tune from the single-speaker Korean checkpoint by tiling its learned
# speaker embedding into all N speaker rows.
#
# Why: MeloTTS load_checkpoint SKIPS emb_g.weight when the shapes differ (KR ckpt is [1, gin],
# the N-speaker model is [N, gin]) -> all N speaker embeddings start RANDOM. With random speaker
# conditioning the decoder produces mumbled/unintelligible audio for thousands of steps until
# emb_g adapts. Copying the KR speaker's vector into every row instead means training STARTS from
# intelligible Korean and only has to specialize each speaker -> far faster, much better quality.
#
# Usage: python seed_kr_ckpt.py <kr_ckpt.pth> <out_ckpt.pth> <n_speakers>
import sys

import torch

src, dst, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
ck = torch.load(src, map_location="cpu")
sd = ck["model"]
emb = sd["emb_g.weight"]  # [n_src, gin_channels]
if emb.shape[0] == n:
    print(f"[seed] emb_g already {tuple(emb.shape)} (n_speakers={n}) — no change")
elif emb.shape[0] == 1:
    sd["emb_g.weight"] = emb.repeat(n, 1).contiguous()
    print(f"[seed] emb_g {tuple(emb.shape)} -> {tuple(sd['emb_g.weight'].shape)} "
          f"(tiled the single KR speaker into all {n} rows)")
else:
    # Unexpected source speaker count: tile the first row so the load still succeeds.
    sd["emb_g.weight"] = emb[:1].repeat(n, 1).contiguous()
    print(f"[seed] WARNING emb_g had {emb.shape[0]} rows; tiled row 0 -> {tuple(sd['emb_g.weight'].shape)}")
torch.save(ck, dst)
print(f"[seed] wrote {dst}")
