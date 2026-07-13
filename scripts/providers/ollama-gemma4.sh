#!/bin/bash
# ABOUTME: Queries Google's Gemma 4 on Ollama Cloud as a dedicated council member
# ABOUTME: Pins gemma4:31b (the working cloud tag) instead of the GLM default
#
# This is a sibling of ollama.sh that runs Gemma 4 as its own council voice so it
# can be queried alongside the GLM-backed `ollama` member. Ollama Cloud serves
# Gemma 4 only as the colon-tagged `gemma4:31b` (bare `gemma4` 404s and there is
# no `gemma4:cloud` pointer). Because ollama_default_model() deliberately discards
# colon-tagged OLLAMA_MODEL values on direct cloud (the "ignore stale local pins"
# guard), this provider resolves its model via ollama_gemma4_model() to bypass
# that guard. Override the tag with OLLAMA_GEMMA4_MODEL. The local 31B build OOMs
# on typical workstations, so this member is cloud-first: it needs OLLAMA_API_KEY
# (direct cloud) or an OLLAMA_BASE_URL daemon that can actually serve Gemma 4.

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
BASE_URL=$(ollama_base_url)
MODEL=$(ollama_gemma4_model)
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
    echo "=== DEBUG: Ollama (Gemma 4) ===" >&2
    echo "Endpoint: $ENDPOINT" >&2
    echo "Model: $MODEL" >&2
    echo "Max tokens: $BASE_TOKENS" >&2
fi

HEADERS=(-H "Content-Type: application/json")
if [[ -n "${OLLAMA_API_KEY:-}" ]]; then
    HEADERS+=(-H "Authorization: Bearer ${OLLAMA_API_KEY}")
fi

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
