"""Download every model at image build time so Cloud Run cold starts never hit the network."""
import os

from transformers import pipeline

pipeline(task="image-to-text", model="Salesforce/blip-image-captioning-large", device=-1)
print("[warmup] BLIP captioner ready")

import whisper  # noqa: E402

whisper.load_model(os.getenv("WHISPER_MODEL", "base"), device="cpu")  # used by stable-ts
print("[warmup] whisper ready")

from kokoro import KPipeline  # noqa: E402

pipe = KPipeline(lang_code="a", repo_id="hexgrad/Kokoro-82M")
for _ in pipe("Warm up.", voice="af_heart"):  # also caches the af_heart voice pack
    pass
print("[warmup] kokoro ready")
