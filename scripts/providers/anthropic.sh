#!/bin/bash
# ABOUTME: Queries Anthropic API with a prompt

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

API_KEY="${ANTHROPIC_API_KEY:-}"
if [[ -z "$API_KEY" ]]; then
    echo "Error: ANTHROPIC_API_KEY not set" >&2
    exit 1
fi

MODEL="${ANTHROPIC_MODEL:-claude-sonnet-4-6}"
BASE_TOKENS="${COUNCIL_MAX_TOKENS:-2048}"
TOKENS="$BASE_TOKENS"

SYSTEM="${VERBOSITY_PREFIX:+$VERBOSITY_PREFIX }$BASE_SYSTEM_PROMPT"
ENDPOINT="https://api.anthropic.com/v1/messages"

PAYLOAD=$(jq -n --arg prompt "$PROMPT" --arg model "$MODEL" --argjson tokens "$TOKENS" --arg system "$SYSTEM" '{
    model: $model,
    system: $system,
    messages: [{
        role: "user",
        content: $prompt
    }],
    max_tokens: $tokens
}')

RESPONSE=$(curl_json_with_retry "$PAYLOAD" -s -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${API_KEY}" \
    -H "anthropic-version: 2023-06-01")

TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text // empty')

if [[ -z "$TEXT" ]]; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error.message // .error // empty')
    if [[ -z "$ERROR" ]]; then
        echo "Error from Anthropic: Unable to parse response" >&2
        echo "Raw response: $RESPONSE" >&2
    else
        echo "Error from Anthropic: $ERROR" >&2
    fi
    exit 1
fi

echo "$TEXT"
