"""
Shared Ollama connection settings for ollama_generate_script.py and ollama_generate_title.py.

Locally nothing changes: defaults point at http://127.0.0.1:11434 with llama3.1.
On Cloud Run, set:
    OLLAMA_URL=https://ollama-xxxx.a.run.app   (base URL of the private Ollama service)
    OLLAMA_USE_ID_TOKEN=1                      (attach a Google ID token for Cloud Run IAM)
"""
import os

import requests

OLLAMA_BASE_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")
OLLAMA_GENERATE_URL = f"{OLLAMA_BASE_URL}/api/generate"
MODEL_NAME = os.getenv("OLLAMA_MODEL", "llama3.1:latest")
# A GPU service that scaled to zero needs time to cold-start and load the model.
TIMEOUT_S = int(os.getenv("OLLAMA_TIMEOUT", "300"))

_METADATA_IDENTITY_URL = (
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity"
)


def auth_headers() -> dict:
    """Return an Authorization header with a Google ID token when running on Cloud Run."""
    if os.getenv("OLLAMA_USE_ID_TOKEN", "0") != "1":
        return {}
    resp = requests.get(
        _METADATA_IDENTITY_URL,
        params={"audience": OLLAMA_BASE_URL},
        headers={"Metadata-Flavor": "Google"},
        timeout=10,
    )
    resp.raise_for_status()
    return {"Authorization": f"Bearer {resp.text}"}
