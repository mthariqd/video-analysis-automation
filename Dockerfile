FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# ffmpeg/ffprobe for 9:16 reformat + hardsubs, espeak-ng + libsndfile for Kokoro TTS
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg espeak-ng libsndfile1 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# CPU-only PyTorch (Cloud Run CPU instances); much smaller than the CUDA build
RUN pip install torch==2.5.1 torchaudio==2.5.1 torchvision==0.20.1 --index-url https://download.pytorch.org/whl/cpu

COPY requirements-cloud.txt .
RUN pip install -r requirements-cloud.txt

# Bake model weights into the image (no downloads at cold start)
ENV WHISPER_MODEL=base
COPY docker/warmup_models.py docker/warmup_models.py
RUN python docker/warmup_models.py

COPY server/ server/
COPY interface/ interface/
COPY docker/entrypoint.sh docker/entrypoint.sh
RUN chmod +x docker/entrypoint.sh

ENV PORT=8080 \
    WHISPER_DEVICE=cpu \
    HF_HUB_OFFLINE=1 \
    DATA_DIR=/mnt/data

EXPOSE 8080
CMD ["docker/entrypoint.sh"]
