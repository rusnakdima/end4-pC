#!/usr/bin/env bash
# List the model IDs currently loaded in LM Studio's OpenAI-compatible API.
# Usage: show-running-lmstudio-models.sh [base-url]
base="${1:-http://localhost:1234}"
base="${base%/}"

response=$(curl -fsS --max-time 4 "$base/v1/models" 2>/dev/null) || { echo "[]"; exit 0; }

printf '%s' "$response" | jq -c '[.data[]?.id // empty]' 2>/dev/null || echo "[]"
