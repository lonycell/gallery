#!/usr/bin/env python3
# Patch a MeloTTS training config.json (produced by preprocess_text.py) for an 8 GB GPU fine-tune
# that starts from the official Korean checkpoint.
#
# Usage: python patch_config.py <config.json> <kr_checkpoint.pth> [batch_size]
import json
import sys

cfg_path = sys.argv[1]
kr_ckpt = sys.argv[2]
batch_size = int(sys.argv[3]) if len(sys.argv) > 3 else 4

c = json.load(open(cfg_path, encoding="utf-8"))
c.setdefault("train", {})
c["train"]["batch_size"] = batch_size      # 8 GB VRAM: keep small to avoid OOM
# fp16 MUST stay off: it makes the VITS normalizing-flow rational-quadratic spline numerically
# unstable (empty/out-of-range inputs -> "min(): numel()==0" crash on every step). fp32 is stable.
c["train"]["fp16_run"] = False
# Fine-tune LR: the default 0.0003 is a from-scratch VITS LR — too hot for fine-tuning a strong
# pretrained checkpoint (it erodes the good Korean phonetics faster than the new speakers adapt).
# 1e-4 protects the pretrain and gently specializes the (now KR-seeded) speaker embeddings.
c["train"]["learning_rate"] = 1e-4
c["train"]["eval_interval"] = 500          # checkpoint every 500 steps (overnight-friendly)
c["train"]["epochs"] = 10000               # effectively "until time budget"; we stop via timeout
# Start the generator from the Korean voice (best Korean phonetics). The discriminator and duration
# predictor come from MeloTTS's fine-tune base via load_pretrain_model() (empty => use base).
# load_checkpoint tolerates the speaker-embedding shape change (1 -> N speakers).
c["pretrain_G"] = kr_ckpt
c["pretrain_D"] = ""
c["pretrain_dur"] = ""
# The published checkpoints use num_languages=10 (the installed code's buggy map gives 8). api.py
# reads this from the config at export, so it MUST be 10 to match the trained model. num_tones=16.
c["num_languages"] = 10
c["num_tones"] = 16

json.dump(c, open(cfg_path, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
# NOTE: pretrain_G written here is IGNORED by training — MeloTTS get_hparams() overwrites
# hps.pretrain_G with the --pretrain_G CLI arg. train_pipeline.sh passes --pretrain_G "$KR"
# explicitly. This config value is still used by the ONNX export step (export-onnx-ko.py).
print(f"[patch_config] batch_size={batch_size} fp16_run=False eval_interval=500 pretrain_G={kr_ckpt}")
print(f"[patch_config] n_speakers={c['data'].get('n_speakers')} spk2id={list(c['data'].get('spk2id', {}).keys())}")
