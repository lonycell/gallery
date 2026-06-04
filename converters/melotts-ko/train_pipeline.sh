#!/usr/bin/env bash
# Unattended end-to-end: AIHub-prepared data -> fine-tuned multi-speaker MeloTTS Korean ->
# sherpa-onnx ONNX -> packaged .tar.bz2 ready to host. Runs inside the GPU training container:
#
#   docker run -d --name melo-ms-train --gpus all \
#     -v V:\data-ko\run:/work/run -v <converters\melotts-ko>:/work/scripts \
#     -e TRAIN_SECONDS=28800 melotts-ko-train bash /work/scripts/train_pipeline.sh
#
# Everything is logged to /work/run/pipeline.log (= host V:\data-ko\run\pipeline.log).
set -uo pipefail

RUN=/work/run
SCR=/work/scripts
DS=$RUN/melo-ko-ms
OUT=$RUN/out
LOGS=$RUN/logs
MODEL=melo-ko-ms
TRAIN_SECONDS=${TRAIN_SECONDS:-28800}     # default 8h budget

exec > >(tee -a "$RUN/pipeline.log") 2>&1
echo "================ pipeline start $(date -u) ================"
echo "TRAIN_SECONDS=$TRAIN_SECONDS"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader || true
mkdir -p "$OUT" "$LOGS/$MODEL"

cd /opt/MeloTTS/melo
# Persist checkpoints to the mounted volume (get_hparams writes to ./logs/<model>).
rm -rf logs && ln -s "$LOGS" logs

# CRITICAL version-compat fix: the published MeloTTS checkpoints (base + KR) were trained with
# num_languages=10, but the installed code's language_id_map has only 8 keys (and a bug: 'ES' and
# 'SP' both map to 5). With 8, the checkpoint's language_emb (10 rows) is DISCARDED on load ->
# broken fine-tune (unintelligible output). Restore a 10-entry map (KR stays at id 4) so
# num_languages=10 and the pretrain loads cleanly. KR-only training never touches the other langs.
# (symbol/num_languages alignment to the KR checkpoint happens after preprocess, see below)

echo "================ [1/5] remap paths + preprocess (BERT on GPU) ================"
CFG="$DS/config.json"
# Skip the (slow) BERT feature extraction if a previous run already produced everything.
if [ -f "$CFG" ] && [ -f "$DS/train.list" ] && [ -f "$DS/val.list" ]; then
  echo "preprocess outputs already present -> skipping (reusing config/train/val + .bert.pt)"
else
  python "$SCR/fix_paths.py" "$DS/metadata.list" "$DS/metadata.container.list" "V:\\data-ko\\run" "/work/run"
  python preprocess_text.py \
    --metadata "$DS/metadata.container.list" \
    --config_path /opt/MeloTTS/melo/configs/config.json \
    --val-per-spk 4 --max-val-total 12
  test -f "$CFG" || { echo "FATAL: preprocess did not produce $CFG"; exit 1; }
fi

# Align symbol set + num_languages/num_tones to the KR checkpoint (every symbols.py + the config),
# so the pretrained KR weights (esp. the Korean phoneme embeddings) load CORRECTLY. Without this the
# installed (newer) MeloTTS symbol order is off-by-2 vs the checkpoint -> scrambled Korean -> garbage.
python "$SCR/align_kr.py" "$CFG"

echo "================ [2/5] deps + fetch KR checkpoint + patch config ================"
# matplotlib<3.8 is required by MeloTTS training (mel plots use canvas.tostring_rgb(), removed in
# 3.8+). Installed at runtime so we don't have to rebuild the image. Cached after first run.
pip install -q "matplotlib<3.8" onnx==1.15.0 onnxruntime==1.18.1 sherpa-onnx==1.13.2 >/dev/null 2>&1 && echo "deps ready (matplotlib/onnx/onnxruntime/sherpa-onnx)"
KR=$(python -c "from melo.download_utils import DOWNLOAD_CKPT_URLS; from cached_path import cached_path; print(cached_path(DOWNLOAD_CKPT_URLS['KR']))")
echo "KR checkpoint: $KR"
# Seed the N speaker embeddings from the KR single speaker (else load_checkpoint skips emb_g and
# all speakers start RANDOM -> mumbled output for thousands of steps). Train from the seeded ckpt.
NSPK=$(python -c "import json;print(len(json.load(open('$CFG',encoding='utf-8'))['data']['spk2id']))")
KR_SEEDED="$DS/G_kr_seeded.pth"
python "$SCR/seed_kr_ckpt.py" "$KR" "$KR_SEEDED" "$NSPK"
KR="$KR_SEEDED"
python "$SCR/patch_config.py" "$CFG" "$KR" 2

echo "================ [3/5] fine-tune (budget ${TRAIN_SECONDS}s) ================"
run_train() {
  # --max-restarts 0: fail fast instead of torchrun's elastic restart loop (a deterministic crash
  # such as the old shm bus-error otherwise spins forever producing nothing).
  # --pretrain_G "$KR" is MANDATORY: MeloTTS get_hparams() OVERWRITES hps.pretrain_G with the
  # --pretrain_G CLI arg (default None) AFTER loading config.json, so the pretrain_G we wrote into
  # config.json via patch_config.py is IGNORED for training. Without this flag train.py falls back
  # to load_pretrain_model()'s BASE multilingual G (not Korean) -> unintelligible Korean output.
  timeout -k 60 "$TRAIN_SECONDS" torchrun --nproc_per_node=1 --max-restarts 0 --master_port=10902 \
    train.py --c "$CFG" --model "$MODEL" --pretrain_G "$KR"
}
run_train; echo "train exited rc=$? ($(date -u))"
# If nothing was saved (likely OOM), retry once with batch_size=2.
if ! ls "$LOGS/$MODEL"/G_*.pth >/dev/null 2>&1; then
  echo "no G_*.pth yet -> retry with batch_size=2"
  python "$SCR/patch_config.py" "$CFG" "$KR" 2
  run_train; echo "retry exited rc=$? ($(date -u))"
fi

echo "================ [4/5] export latest checkpoint -> sherpa-onnx ================"
LATEST=$(ls -t "$LOGS/$MODEL"/G_*.pth 2>/dev/null | head -1)
echo "latest checkpoint: ${LATEST:-<none>}"
if [ -z "${LATEST:-}" ]; then echo "FATAL: no checkpoint to export"; exit 1; fi
cd "$OUT"
python "$SCR/export-onnx-ko.py" --ckpt "$LATEST" --config "$CFG" --extra-words "$SCR/extra_words.txt"
python "$SCR/show-info.py" "$OUT/model.onnx" || true

echo "================ [5/5] per-speaker test WAVs + package ================"
python "$SCR/test_multispeaker.py" "$OUT" || echo "(test synth failed — non-fatal)"
python "$SCR/package.py" --src "$OUT" --out "$OUT"

echo "================ DONE $(date -u) ================"
echo "Artifacts in $OUT:"; ls -lh "$OUT"
echo "speakers:"; cat "$OUT/speakers.txt" 2>/dev/null || echo "(none)"
echo "Trained checkpoint: $LATEST"
