#!/bin/sh
# Link v_raw/ (source clips) and v_fin/ (finished videos) to the Cloud Storage volume when mounted.
# temp/ stays on the container's local (in-memory) filesystem: it is scratch space per job.
set -e
APP_DIR="${APP_DIR:-/app}"
cd "$APP_DIR"

DATA_DIR="${DATA_DIR:-/mnt/data}"
if [ -d "$DATA_DIR" ]; then
  for d in v_raw v_fin; do
    mkdir -p "$DATA_DIR/$d"
    rm -rf "$APP_DIR/$d"
    ln -s "$DATA_DIR/$d" "$APP_DIR/$d"
  done
  echo "[entrypoint] v_raw/, v_fin/ -> $DATA_DIR"
else
  mkdir -p v_raw v_fin
  echo "[entrypoint] no volume at $DATA_DIR, using local folders"
fi
mkdir -p temp

# One worker keeps the in-memory pipeline state (review gates, cancel flag) in a single process;
# threads serve HTTP + Socket.IO (WebSocket via simple-websocket). --timeout 0: long jobs.
exec gunicorn --chdir server -w 1 --threads 100 --timeout 0 \
  --bind "0.0.0.0:${PORT:-8080}" app:app
