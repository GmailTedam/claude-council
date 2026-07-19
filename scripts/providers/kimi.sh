#!/bin/bash
# ABOUTME: Queries Moonshot AI's Kimi API with a prompt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/retry.sh"
source "$SCRIPT_DIR/../lib/verbosity.sh"

verbosity_prefix VERBOSITY_PREFIX "${COUNCIL_VERBOSITY:-standard}"
DEBUG="${COUNCIL_DEBUG:-}"

PROMPT="${1:-}"
if [[ -z "$PROMPT" ]]; then
    echo "Error: No prompt provided" >&2
    exit 1
fi

API_KEY="${KIMI_CODE_API_KEY:-${MOONSHOT_API_KEY:-}}"
if [[ -z "$API_KEY" ]]; then
    echo "Error: MOONSHOT_API_KEY or KIMI_CODE_API_KEY not set" >&2
    exit 1
fi

if [[ -n "${KIMI_MODEL:-}" ]]; then
    MODEL="$KIMI_MODEL"
elif [[ -n "${KIMI_CODE_API_KEY:-}" ]]; then
    MODEL="k3"
else
    MODEL="kimi-k2.7-code"
fi
TOKENS="${COUNCIL_MAX_TOKENS:-2048}"
SYSTEM="${VERBOSITY_PREFIX:+$VERBOSITY_PREFIX }$BASE_SYSTEM_PROMPT"
if [[ -n "${KIMI_BASE_URL:-}" ]]; then
    BASE_URL="$KIMI_BASE_URL"
elif [[ -n "${KIMI_CODE_API_KEY:-}" ]]; then
    BASE_URL="https://api.kimi.com/coding/v1"
else
    BASE_URL="https://api.moonshot.ai/v1"
fi

PAYLOAD=$(jq -n --arg prompt "$PROMPT" --arg model "$MODEL" \
    --argjson tokens "$TOKENS" --arg system "$SYSTEM" '{
    model: $model,
    messages: [
        {role: "system", content: $system},
        {role: "user", content: $prompt}
    ],
    max_tokens: $tokens
}')

RESPONSE=$(curl_json_with_retry "$PAYLOAD" -s -X POST \
    "${BASE_URL%/}/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}")

TEXT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')
if [[ -z "$TEXT" ]]; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error.message // .error // empty')
    echo "Error from Kimi: ${ERROR:-Unable to parse response}" >&2
    exit 1
fi

echo "$TEXT"
