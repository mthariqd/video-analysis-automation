#!/usr/bin/env bash
# One-shot Cloud Run deployment for video-analysis-automation:
#   1. "ollama"          private GPU service (L4) serving llama3.1
#   2. "video-analysis"  CPU service (Flask + Socket.IO UI and pipeline), calls Ollama with an ID token
# Usage:  PROJECT_ID=my-project APP_PASSWORD='choose-one' ./deploy.sh
#         SKIP_OLLAMA=1 ...   redeploy only the app
# Re-running is safe: existing resources are reused, images are rebuilt and redeployed.
set -euo pipefail

: "${PROJECT_ID:?set PROJECT_ID}"
REGION="${REGION:-asia-southeast1}"          # must offer Cloud Run L4 GPUs
REPO="${REPO:-video-automation}"
APP_SERVICE="${APP_SERVICE:-video-analysis}"
OLLAMA_SERVICE="${OLLAMA_SERVICE:-ollama}"
BUCKET="${BUCKET:-${PROJECT_ID}-video-analysis-data}"
SA_NAME="${SA_NAME:-video-analysis-sa}"
SECRET="${SECRET:-video-analysis-app-password}"
MODEL="${MODEL:-llama3.1:latest}"
TAG="$(date +%Y%m%d-%H%M%S)"
AR="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud config set project "$PROJECT_ID" >/dev/null

echo "==> 1/8 Enabling APIs"
gcloud services enable run.googleapis.com artifactregistry.googleapis.com \
  cloudbuild.googleapis.com secretmanager.googleapis.com storage.googleapis.com

echo "==> 2/8 Artifact Registry repo"
gcloud artifacts repositories describe "$REPO" --location "$REGION" >/dev/null 2>&1 || \
  gcloud artifacts repositories create "$REPO" --repository-format docker --location "$REGION"

echo "==> 3/8 Data bucket (v_raw/, v_fin/)"
gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://$BUCKET" --location "$REGION" --uniform-bucket-level-access
[ -d v_raw ] && gcloud storage rsync -r v_raw "gs://$BUCKET/v_raw"

echo "==> 4/8 Service account + permissions"
gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1 || \
  gcloud iam service-accounts create "$SA_NAME" --display-name "video-analysis runtime"
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member "serviceAccount:$SA_EMAIL" --role roles/storage.objectUser >/dev/null

echo "==> 5/8 App password secret"
if ! gcloud secrets describe "$SECRET" >/dev/null 2>&1; then
  : "${APP_PASSWORD:?set APP_PASSWORD for the first deploy}"
  printf '%s' "$APP_PASSWORD" | gcloud secrets create "$SECRET" --data-file=-
fi
gcloud secrets add-iam-policy-binding "$SECRET" \
  --member "serviceAccount:$SA_EMAIL" --role roles/secretmanager.secretAccessor >/dev/null

if [ "${SKIP_OLLAMA:-0}" != "1" ]; then
  echo "==> 6/8 Ollama GPU service (image ~5 GB, first build ~10-20 min)"
  cat > /tmp/cloudbuild-ollama.yaml <<EOF
steps:
- name: gcr.io/cloud-builders/docker
  args: ["build", "--build-arg", "MODEL=${MODEL}", "-t", "${AR}/${OLLAMA_SERVICE}:${TAG}", "ollama"]
images: ["${AR}/${OLLAMA_SERVICE}:${TAG}"]
options:
  machineType: E2_HIGHCPU_8
  diskSizeGb: 100
timeout: 3600s
EOF
  gcloud builds submit --config /tmp/cloudbuild-ollama.yaml .
  gcloud run deploy "$OLLAMA_SERVICE" \
    --image "${AR}/${OLLAMA_SERVICE}:${TAG}" \
    --region "$REGION" \
    --gpu 1 --gpu-type nvidia-l4 --no-gpu-zonal-redundancy \
    --cpu 8 --memory 32Gi \
    --no-cpu-throttling \
    --min-instances 0 --max-instances 1 \
    --concurrency 4 \
    --timeout 600 \
    --no-allow-unauthenticated
fi
OLLAMA_URL="$(gcloud run services describe "$OLLAMA_SERVICE" --region "$REGION" --format 'value(status.url)')"
gcloud run services add-iam-policy-binding "$OLLAMA_SERVICE" --region "$REGION" \
  --member "serviceAccount:$SA_EMAIL" --role roles/run.invoker >/dev/null

echo "==> 7/8 Building app image (first build ~15-25 min)"
gcloud builds submit --tag "${AR}/${APP_SERVICE}:${TAG}" --machine-type e2-highcpu-8 --timeout 3600s .

echo "==> 8/8 Deploying app"
gcloud run deploy "$APP_SERVICE" \
  --image "${AR}/${APP_SERVICE}:${TAG}" \
  --region "$REGION" \
  --service-account "$SA_EMAIL" \
  --execution-environment gen2 \
  --cpu 4 --memory 8Gi \
  --no-cpu-throttling \
  --min-instances 0 --max-instances 1 \
  --concurrency 50 \
  --timeout 3600 \
  --session-affinity \
  --add-volume name=data,type=cloud-storage,bucket="$BUCKET" \
  --add-volume-mount volume=data,mount-path=/mnt/data \
  --set-env-vars OLLAMA_URL="$OLLAMA_URL",OLLAMA_USE_ID_TOKEN=1,OLLAMA_MODEL="$MODEL" \
  --set-secrets APP_PASSWORD="$SECRET":latest \
  --allow-unauthenticated

echo
echo "Done. URL:"
gcloud run services describe "$APP_SERVICE" --region "$REGION" --format 'value(status.url)'
echo "Log in with user 'admin' and your APP_PASSWORD."
