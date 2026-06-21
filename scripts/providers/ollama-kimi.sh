#!/bin/bash
# ABOUTME: Queries Moonshot's Kimi K2.7 Code on Ollama Cloud as a council member
# ABOUTME: Pins kimi-k2.7-code (cloud-only; no viable local build on a workstation)
#
# Sibling of ollama.sh that runs Kimi K2.7 Code as its own council voice, so it
# can be queried in parallel with the other Ollama members
# (e.g. `--providers=ollama,ollama-gemma4,ollama-kimi`). It is discovered under
# the same conditions as `ollama` and resolves its model via ollama_kimi_model()
# (`kimi-k2.7-code`, override with `OLLAMA_KIMI_MODEL`). Kimi K2.7 Code is a
# large coding model served on Ollama Cloud; this member is cloud-first and
# needs OLLAMA_API_KEY (direct cloud) or an OLLAMA_BASE_URL daemon that serves it.

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
MODEL=$(ollama_kimi_model)
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
    echo "=== DEBUG: Ollama (Kimi K2.7 Code) ===" >&2
    echo "Endpoint: $ENDPOINT" >&2
    echo "Model: $MODEL" >&2
    echo "Max tokens: $BASE_TOKENS" >&2
fi

HEADERS=(-H "Content-Type: application/json")
if [[ -n "${OLLAMA_API_KEY:-}" ]]; then
    HEADERS+=(-H "Authorization: Bearer ${OLLAMA_API_KEY}")
fi

RESPONSE=$(curl_with_retry -s -X POST "$ENDPOINT" "${HEADERS[@]}" -d "$PAYLOAD")
TEXT=$(echo "$RESPONSE" | jq -r '.message.content // .response // empty')

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
