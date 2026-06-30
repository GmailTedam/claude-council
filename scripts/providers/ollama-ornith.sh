#!/bin/bash
# ABOUTME: Queries Ornith through Ollama as a dedicated council member
# ABOUTME: Prefers the pulled local model and falls back to Ollama Cloud if needed
#
# Ornith is a coding model available through Ollama. This provider keeps it as
# a separate council voice so it can run alongside the GLM-backed `ollama`
# member and the other dedicated Ollama members. It resolves the model with
# ollama_ornith_model() (`ornith`, override with OLLAMA_ORNITH_MODEL) and the
# endpoint with ollama_ornith_base_url(), which prefers a local daemon that has
# the model installed before trying Ollama Cloud.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/retry.sh"
source "$SCRIPT_DIR/../lib/verbosity.sh"
source "$SCRIPT_DIR/../lib/providers.sh"

verbosity_prefix VERBOSITY_PREFIX "${COUNCIL_VERBOSITY:-standard}"

DEBUG="${COUNCIL_DEBUG:-}"
PROMPT="${1:-}"

if [[ -z "$PROMPT" ]]; then
    echo "Error: No prompt provided" >&2
    exit 1
fi

load_ollama_env

BASE_TOKENS="${COUNCIL_MAX_TOKENS:-2048}"
SYSTEM="${VERBOSITY_PREFIX:+$VERBOSITY_PREFIX }$BASE_SYSTEM_PROMPT"
BASE_URL=$(ollama_ornith_base_url)
MODEL=$(ollama_ornith_model)
ENDPOINT="${BASE_URL%/}/api/chat"

PAYLOAD=$(jq -n --arg prompt "$PROMPT" --arg model "$MODEL" --argjson tokens "$BASE_TOKENS" --arg system "$SYSTEM" '{
    model: $model,
    messages: [{
        role: "system",
        content: $system
    }, {
        role: "user",
        content: $prompt
    }],
    stream: false,
    options: {
        temperature: 0.7,
        num_predict: $tokens
    }
}')

if [[ -n "$DEBUG" ]]; then
    echo "=== DEBUG: Ollama (Ornith) ===" >&2
    echo "Endpoint: $ENDPOINT" >&2
    echo "Model: $MODEL" >&2
    echo "Max tokens: $BASE_TOKENS" >&2
fi

HEADERS=(-H "Content-Type: application/json")
case "${BASE_URL%/}" in
    https://ollama.com|https://www.ollama.com)
        [[ -n "${OLLAMA_API_KEY:-}" ]] && HEADERS+=(-H "Authorization: Bearer ${OLLAMA_API_KEY}")
        ;;
esac

RESPONSE=$(curl_json_with_retry "$PAYLOAD" -s -X POST "$ENDPOINT" "${HEADERS[@]}")
TEXT=$(echo "$RESPONSE" | jq -r '.message.content // .message.thinking // .response // empty')

if [[ -z "$TEXT" ]]; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error // empty')
    if [[ -z "$ERROR" ]]; then
        echo "Error from Ollama: Unable to parse response" >&2
        echo "Raw response: $RESPONSE" >&2
    else
        echo "Error from Ollama: $ERROR" >&2
    fi
    exit 1
fi

echo "$TEXT"
