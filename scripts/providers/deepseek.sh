#!/bin/bash
# ABOUTME: Queries DeepSeek API with a prompt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/retry.sh"
source "$SCRIPT_DIR/../lib/verbosity.sh"

verbosity_prefix VERBOSITY_PREFIX "${COUNCIL_VERBOSITY:-standard}"

PROMPT="${1:-}"

if [[ -z "$PROMPT" ]]; then
    echo "Error: No prompt provided" >&2
    exit 1
fi

API_KEY="${DEEPSEEK_API_KEY:-}"
if [[ -z "$API_KEY" ]]; then
    echo "Error: DEEPSEEK_API_KEY not set" >&2
    exit 1
fi

MODEL="${DEEPSEEK_MODEL:-deepseek-chat}"
BASE_TOKENS="${COUNCIL_MAX_TOKENS:-2048}"
TOKENS="$BASE_TOKENS"

SYSTEM="${VERBOSITY_PREFIX:+$VERBOSITY_PREFIX }$BASE_SYSTEM_PROMPT"
ENDPOINT="https://api.deepseek.com/chat/completions"

PAYLOAD=$(jq -n --arg prompt "$PROMPT" --arg model "$MODEL" --argjson tokens "$TOKENS" --arg system "$SYSTEM" '{
    model: $model,
    messages: [{
        role: "system",
        content: $system
    }, {
        role: "user",
        content: $prompt
    }],
    max_tokens: $tokens
}')

RESPONSE=$(curl_with_retry -s -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d "$PAYLOAD")

TEXT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')

if [[ -z "$TEXT" ]]; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error.message // .error // empty')
    if [[ -z "$ERROR" ]]; then
        echo "Error from DeepSeek: Unable to parse response" >&2
        echo "Raw response: $RESPONSE" >&2
    else
        echo "Error from DeepSeek: $ERROR" >&2
    fi
    exit 1
fi

echo "$TEXT"
