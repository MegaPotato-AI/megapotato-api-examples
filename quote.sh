#!/usr/bin/env bash
# Check what an upscale will cost before sending the photo. Nothing is uploaded or charged.
#
# Usage:  bash quote.sh WIDTH HEIGHT [scale]     scale: 1 (refine, same size), 2, 4 (default) or 8
# Needs:  curl, and your API key in the MEGAPOTATO_API_KEY environment variable.
#
#   $ bash quote.sh 4000 3000 2
#   {"cost_chips":21,"output_width":8000,"output_height":6000,"upscale":2}
set -euo pipefail

WIDTH="${1:?usage: bash quote.sh WIDTH HEIGHT [scale]}"
HEIGHT="${2:?usage: bash quote.sh WIDTH HEIGHT [scale]}"
SCALE="${3:-4}"
: "${MEGAPOTATO_API_KEY:?set MEGAPOTATO_API_KEY first}"

curl -sS --fail-with-body -w "\n" https://megapotato.app/v1/quote \
  -H "Authorization: Bearer $MEGAPOTATO_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"width\": $WIDTH, \"height\": $HEIGHT, \"upscale\": $SCALE}"
