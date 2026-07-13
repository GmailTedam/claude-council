#!/bin/bash
# ABOUTME: Queries a dedicated NVIDIA-hosted coding-specialist model as its own council voice
# ABOUTME: Sibling of nvidia.sh, pinned to Llama 3.1 70B instead of the Nemotron generalist default
#
# NVIDIA's Build API (build.nvidia.com) is free/rate-limited rather than
# per-token billed, so this costs nothing extra beyond the base `nvidia`
# member's quota. The /v1/models catalog lists ~121 models, but most are NOT
# actually invokable on a free-tier account (dedicated coder models tried and
# confirmed 404 here: mistralai/codestral-22b-instruct-v0.1,
# deepseek-ai/deepseek-coder-6.7b-instruct, ibm/granite-34b-code-instruct,
# google/codegemma-7b, meta/codellama-70b, nvidia/llama-3.1-nemotron-70b-instruct).
# Pinned to meta/llama-3.1-70b-instruct (confirmed HTTP 200 live), a strong
# general model with solid code ability, to give the council a distinct
# coding-focused voice alongside the reasoning-tuned `nvidia` (Nemotron)
# member. Override with NVIDIA_CODER_MODEL if your account has a dedicated
# coder function enabled.

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

MODEL="${NVIDIA_CODER_MODEL:-meta/llama-3.1-70b-instruct}"
BASE_TOKENS="${COUNCIL_MAX_TOKENS:-2048}"
bump_for_reasoning TOKENS "$MODEL" "$BASE_TOKENS" '*reasoning*' '*nemotron*'

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
    echo "=== DEBUG: NVIDIA NIM (Coder) ===" >&2
    echo "Endpoint: $ENDPOINT" >&2
    echo "Model: $MODEL" >&2
    echo "Max tokens: $TOKENS" >&2
fi

RESPONSE=$(curl_json_with_retry "$PAYLOAD" -s -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}")

TEXT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // .choices[0].message.reasoning_content // empty')

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
