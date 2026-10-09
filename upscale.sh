#!/usr/bin/env bash
# Upscale one photo with the MegaPotato API: upload it, wait for the result, download it.
#
# Usage:  bash upscale.sh photo.jpg [scale]     scale: 1 (refine, same size), 2, 4 (default) or 8
# Needs:  curl, jq, and your API key in the MEGAPOTATO_API_KEY environment variable.
set -euo pipefail

API="https://megapotato.app/v1"
FILE="${1:?usage: bash upscale.sh photo.jpg [scale]}"
SCALE="${2:-4}"
: "${MEGAPOTATO_API_KEY:?set MEGAPOTATO_API_KEY first}"
HEADERS=$(mktemp)
trap 'rm -f "$HEADERS"' EXIT

# One API call; prints the response body. Retries what can succeed later (429, 5xx, network
# errors) and stops on everything else.
api() {
  local method=$1 path=$2 attempt response code body type message pause
  shift 2
  for attempt in 0 1 2 3 4 5 6 7; do
    if ! response=$(curl -sS -D "$HEADERS" -X "$method" -w $'\n%{http_code}' "$API$path" \
      -H "Authorization: Bearer $MEGAPOTATO_API_KEY" "$@"); then
      sleep $((2 ** attempt))
      continue
    fi
    code=${response##*$'\n'}
    body=${response%$'\n'*}
    if [[ $code == 2?? ]]; then
      printf '%s' "$body"
      return
    fi
    type=$(jq -r '.error.type // empty' <<<"$body" 2>/dev/null || true)
    # spend_limit_reached is a 429 too, but it only resets at 00:00 UTC: not worth waiting for.
    if [[ $code == 5?? || ($code == 429 && $type != spend_limit_reached) ]]; then
      pause=$(tr -d '\r' <"$HEADERS" | awk -F': *' 'tolower($1) == "retry-after" { print int($2) }')
      sleep "${pause:-$((2 ** attempt))}"
      continue
    fi
    message=$(jq -r '.error.message // empty' <<<"$body" 2>/dev/null || true)
    echo "$code ${type:-error}: ${message:-${body:0:200}}" >&2
    exit 1
  done
  echo "gave up after repeated temporary errors" >&2
  exit 1
}

# One key per run: if the upload is retried, the server returns the same job and charges once.
KEY="upscale-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
JOB=$(api POST /upscale -H "Idempotency-Key: $KEY" -F "file=@$FILE" -F "upscale=$SCALE")
ID=$(jq -r .id <<<"$JOB")
echo "job $ID: $(jq -r .cost_chips <<<"$JOB") chips"

# Each request waits up to 55 s on the server. Read the job at least once even if the upload
# answer already says "completed": only this request carries result_url and error.
while :; do
  JOB=$(api GET "/jobs/$ID?wait=55")
  STATUS=$(jq -r .status <<<"$JOB")
  [[ $STATUS == completed || $STATUS == failed ]] && break
  jq -r '.status + if .eta_seconds then ", about \(.eta_seconds | round) s left" else "" end' \
    <<<"$JOB"
done

if [[ $STATUS == failed ]]; then
  echo "failed: $(jq -r .error <<<"$JOB")" >&2
  exit 1
fi

# The link works for about an hour. Results are PNG; test keys return a sample JPEG.
URL=$(jq -r .result_url <<<"$JOB")
EXT=${URL%%\?*}
OUT="${FILE%.*}_x$SCALE.${EXT##*.}"
curl -sS --fail -o "$OUT" "$URL"
echo "saved $OUT"
