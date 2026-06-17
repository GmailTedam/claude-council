#!/bin/bash
# ABOUTME: Queries NVIDIA hosted NIM models through the OpenAI-compatible API
# ABOUTME: Uses NVIDIA_API_KEY, falling back to NVIDIA_BUILD_API_KEY

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/retry.sh"
source "$SCRIPT_DIR/../lib/keys.sh"
source "$SCRIPT_DIR/../lib/tokens.sh"
source "$SCRIPT_DIR/../lib/verbosity.sh"

verbosity_prefix VERBOSITY_PREFIX "${COUNCIL_VERBOSITY:-standard}"
resolve_nvidia_key

DEBUG="${COUNCIL_DEBUG:-}"
PROMPT="${1:-}"

if [[ -z "$PROMPT" ]]; then
    echo "Error: No prompt provided" >&2
    exit 1
fi

API_KEY="${NVIDIA_API_KEY:-}"
if [[ -z "$API_KEY" ]]; then
    echo "Error: NVIDIA_API_KEY (or NVIDIA_BUILD_API_KEY) not set" >&2
    exit 1
fi

MODEL="${NVIDIA_MODEL:-nvidia/llama-3.3-nemotron-super-49b-v1.5}"
BASE_TOKENS="${COUNCIL_MAX_TOKENS:-2048}"
bump_for_reasoning TOKENS "$MODEL" "$BASE_TOKENS" '*reasoning*'

SYSTEM="${VERBOSITY_PREFIX:+$VERBOSITY_PREFIX }$BASE_SYSTEM_PROMPT"
BASE_URL="${NVIDIA_BASE_URL:-https://integrate.api.nvidia.com/v1}"
ENDPOINT="${BASE_URL%/}/chat/completions"

PAYLOAD=$(jq -n --arg prompt "$PROMPT" --arg model "$MODEL" --argjson tokens "$TOKENS" --arg system "$SYSTEM" '{
    model: $model,
    messages: [{
        role: "system",
        content: $system
    }, {
        role: "user",
        content: $prompt
    }],
    temperature: 0.7,
    max_tokens: $tokens
}')

if [[ -n "$DEBUG" ]]; then
    echo "=== DEBUG: NVIDIA NIM ===" >&2
    echo "Endpoint: $ENDPOINT" >&2
    echo "Model: $MODEL" >&2
    echo "Max tokens: $TOKENS" >&2
fi

RESPONSE=$(curl_with_retry -s -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d "$PAYLOAD")

TEXT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')

if [[ -z "$TEXT" ]]; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error.message // .error // .detail // empty')
    if [[ -z "$ERROR" ]]; then
        echo "Error from NVIDIA: Unable to parse response" >&2
        echo "Raw response: $RESPONSE" >&2
    else
        echo "Error from NVIDIA: $ERROR" >&2
    fi
    exit 1
fi

echo "$TEXT"
