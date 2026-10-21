# Private Ollama service on a Cloud Run GPU (NVIDIA L4), with the model baked into the image.
# Pin the tag (e.g. ollama/ollama:0.x.y) once you have a version that works for you.
FROM ollama/ollama:latest

ENV OLLAMA_HOST=0.0.0.0:8080 \
    OLLAMA_MODELS=/models \
    OLLAMA_DEBUG=false \
    OLLAMA_KEEP_ALIVE=-1

# Must match OLLAMA_MODEL in the app (default "llama3.1:latest")
ARG MODEL=llama3.1:latest
RUN ollama serve & sleep 5 && ollama pull ${MODEL}

ENTRYPOINT ["ollama", "serve"]
