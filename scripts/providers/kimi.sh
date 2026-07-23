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

# Kimi K3 on both routes. It is served as `k3` on the api.kimi.com coding
# endpoint and as `kimi-k3` on the Moonshot API (verified live against
# api.moonshot.ai/v1/models and a real completion). The Moonshot route
# previously pinned kimi-k2.7-code, so a MOONSHOT_API_KEY-only setup silently
# got the older model even though K3 was available to it. Override with
# KIMI_MODEL.
if [[ -n "${KIMI_MODEL:-}" ]]; then
    MODEL="$KIMI_MODEL"
elif [[ -n "${KIMI_CODE_API_KEY:-}" ]]; then
    MODEL="k3"
else
    MODEL="kimi-k3"
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

# Issue one request against a given route. Prints the answer on success;
# on failure prints nothing and leaves the reason in KIMI_LAST_ERROR.
kimi_try_route() {
    local base="$1" model="$2" key="$3" payload response text

    payload=$(jq -n --arg prompt "$PROMPT" --arg model "$model" \
        --argjson tokens "$TOKENS" --arg system "$SYSTEM" '{
        model: $model,
        messages: [
            {role: "system", content: $system},
            {role: "user", content: $prompt}
        ],
        max_tokens: $tokens
    }')

    response=$(curl_json_with_retry "$payload" -s -X POST \
        "${base%/}/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${key}")

    # Kimi K3 is a REASONING model: its chain-of-thought lands in
    # reasoning_content and shares the output token budget, so a tight cap can
    # leave content empty on an otherwise successful call. Fall back to
    # reasoning_content rather than reporting a healthy model as broken.
    text=$(echo "$response" | jq -r '.choices[0].message.content // empty')
    if [[ -z "$text" ]]; then
        text=$(echo "$response" | jq -r '.choices[0].message.reasoning_content // empty')
    fi

    if [[ -z "$text" ]]; then
        KIMI_LAST_ERROR=$(echo "$response" | jq -r '.error.message // .error // empty')
        return 1
    fi
    printf '%s' "$text"
}

# Try the selected route, then the OTHER credentialled route if it fails. Both
# serve Kimi K3, and either can be independently unavailable -- the coding route
# in particular carries its own billing quota that, once exhausted, takes this
# council member offline while the Moonshot route is still perfectly healthy.
# Falling back keeps the voice in the council instead of dropping it for a
# reason nobody sees.
TEXT=$(kimi_try_route "$BASE_URL" "$MODEL" "$API_KEY") || TEXT=""

if [[ -z "$TEXT" ]]; then
    PRIMARY_ERROR="${KIMI_LAST_ERROR:-Unable to parse response}"
    ALT_BASE=""; ALT_MODEL=""; ALT_KEY=""
    if [[ "$BASE_URL" == *"api.kimi.com"* && -n "${MOONSHOT_API_KEY:-}" ]]; then
        ALT_BASE="https://api.moonshot.ai/v1"
        ALT_MODEL="kimi-k3"
        ALT_KEY="$MOONSHOT_API_KEY"
    elif [[ "$BASE_URL" == *"api.moonshot.ai"* && -n "${KIMI_CODE_API_KEY:-}" ]]; then
        ALT_BASE="https://api.kimi.com/coding/v1"
        ALT_MODEL="k3"
        ALT_KEY="$KIMI_CODE_API_KEY"
    fi

    if [[ -n "$ALT_BASE" ]]; then
        [[ -n "$DEBUG" ]] && \
            echo "=== DEBUG: Kimi primary failed ($PRIMARY_ERROR); trying $ALT_BASE ===" >&2
        TEXT=$(kimi_try_route "$ALT_BASE" "$ALT_MODEL" "$ALT_KEY") || TEXT=""
    fi

    if [[ -z "$TEXT" ]]; then
        echo "Error from Kimi: $PRIMARY_ERROR" >&2
        [[ -n "$ALT_BASE" ]] && \
            echo "Fallback route also failed: ${KIMI_LAST_ERROR:-unknown}" >&2
        exit 1
    fi
fi

echo "$TEXT"
