#!/bin/bash
# ABOUTME: Queries z.ai (Zhipu) GLM models via the OpenAI-compatible API
# ABOUTME: Availability is gated on Z_AI_API_KEY (canonicalised to ZAI_API_KEY)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/retry.sh"
source "$SCRIPT_DIR/../lib/keys.sh"
source "$SCRIPT_DIR/../lib/tokens.sh"
source "$SCRIPT_DIR/../lib/verbosity.sh"

verbosity_prefix VERBOSITY_PREFIX "${COUNCIL_VERBOSITY:-standard}"

DEBUG="${COUNCIL_DEBUG:-}"
PROMPT="${1:-}"

if [[ -z "$PROMPT" ]]; then
    echo "Error: No prompt provided" >&2
    exit 1
fi

# Z_AI_API_KEY (the env var the user sets) -> ZAI_API_KEY (script-canonical).
resolve_zai_key
API_KEY="${ZAI_API_KEY:-}"
if [[ -z "$API_KEY" ]]; then
    echo "Error: Z_AI_API_KEY (or ZAI_API_KEY) not set" >&2
    exit 1
fi

# z.ai OpenAI-compatible endpoint. Override the base with ZAI_BASE_URL.
BASE_URL="${ZAI_BASE_URL:-https://api.z.ai/api/paas/v4}"
ENDPOINT="${BASE_URL%/}/chat/completions"

# GLM-4.6 is a hybrid-reasoning model: its chain-of-thought shares the output
# token budget, so a 2048 cap can truncate the visible answer. Bump the cap for
# glm-4*/glm-5* and any *reasoning*/*thinking* model. Override with ZAI_MODEL.
MODEL="${ZAI_MODEL:-glm-4.6}"
BASE_TOKENS="${COUNCIL_MAX_TOKENS:-2048}"
bump_for_reasoning TOKENS "$MODEL" "$BASE_TOKENS" 'glm-4*' 'glm-5*' '*reasoning*' '*thinking*'

SYSTEM="${VERBOSITY_PREFIX:+$VERBOSITY_PREFIX }$BASE_SYSTEM_PROMPT"

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
    echo "=== DEBUG: z.ai ===" >&2
    echo "Endpoint: $ENDPOINT" >&2
    echo "Model: $MODEL" >&2
    echo "Max tokens: $TOKENS" >&2
fi

# Send the JSON body via a temp file + --data-binary, never as a curl argv
# (`-d "$PAYLOAD"`): on Windows/MSYS, passing a multibyte-UTF-8 string through
# curl's command line mangles em-dashes / curly quotes into invalid UTF-8 and the
# API rejects it with HTTP 400. Writing the bytes to disk and reading them with
# @file bypasses argv entirely. Uses curl_with_retry, which is present in every
# retry.sh version (curl_json_with_retry exists only in the patched cache copy).
BODY_FILE=$(mktemp)
printf '%s' "$PAYLOAD" > "$BODY_FILE"
RESPONSE=$(curl_with_retry -s -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}" \
    --data-binary @"$BODY_FILE")
rm -f "$BODY_FILE"

# GLM returns chain-of-thought in reasoning_content and the answer in content;
# fall back to reasoning_content only if content is empty (low-cap truncation).
TEXT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')
if [[ -z "$TEXT" ]]; then
    TEXT=$(echo "$RESPONSE" | jq -r '.choices[0].message.reasoning_content // empty')
fi

if [[ -z "$TEXT" ]]; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error.message // .error // empty')
    if [[ -z "$ERROR" ]]; then
        echo "Error from z.ai: Unable to parse response" >&2
        echo "Raw response: $RESPONSE" >&2
    else
        echo "Error from z.ai: $ERROR" >&2
    fi
    exit 1
fi

echo "$TEXT"
