# Reproducible Linux environment for converting MeloTTS-Korean -> sherpa-onnx.
#
# This is the recommended path on a Windows dev PC: it avoids building MeCab and
# the Korean g2p stack natively on Windows (which is painful). On Linux the
# python-mecab-ko and torch CPU wheels install cleanly.
#
# Build + run via convert.ps1 (Windows) or convert.sh ... or manually:
#   docker build -t melotts-ko-converter .
#   docker run --rm -e OUT_DIR=/work/out -v "${PWD}/out:/work/out" melotts-ko-converter
FROM python:3.10-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    HF_HUB_DISABLE_TELEMETRY=1 \
    PIP_NO_CACHE_DIR=1

# git: clone MeloTTS. build-essential: native deps. libsndfile1: soundfile I/O.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git build-essential libsndfile1 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /work

# 1) Pinned conversion deps first (cached layer).
COPY requirements.txt /work/requirements.txt
RUN pip install -r requirements.txt
# Belt-and-suspenders: strip any executable-stack flag from native .so files so
# onnxruntime loads under hardened container kernels. Non-fatal if execstack is
# unavailable (the pinned onnxruntime already ships a fixed wheel).
RUN apt-get update && apt-get install -y --no-install-recommends execstack && \
    find /usr/local/lib/python3.10/site-packages -name '*.so' -exec execstack -c {} + 2>/dev/null; \
    apt-get purge -y execstack >/dev/null 2>&1 || true; \
    rm -rf /var/lib/apt/lists/*; true

# 2) MeloTTS from source — pulls transformers/jamo/num2words/etc. Our pre-pinned
#    torch (2.3.1) satisfies its unpinned torch requirement, so it isn't replaced.
#    unidic download is needed because MeloTTS imports its Japanese module eagerly.
RUN git clone --depth 1 https://github.com/myshell-ai/MeloTTS /opt/MeloTTS && \
    pip install /opt/MeloTTS && \
    python -m unidic download

# 3) The converter scripts.
COPY export-onnx-ko.py test-onnx-ko.py show-info.py package.py \
     convert-pipeline.sh extra_words.txt /work/
RUN chmod +x /work/convert-pipeline.sh

# Runs the full pipeline and drops artifacts into $OUT_DIR (bind-mounted).
ENTRYPOINT ["/work/convert-pipeline.sh"]
