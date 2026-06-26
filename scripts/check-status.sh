#!/bin/bash
# ABOUTME: Checks connectivity and configuration status of all council providers
# ABOUTME: Outputs status table with connection times and model info

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/keys.sh"
source "$SCRIPT_DIR/lib/providers.sh"
resolve_grok_key
resolve_nvidia_key
resolve_zai_key

# Colors
BLUE='\033[34m'
WHITE='\033[37m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
MAGENTA='\033[35m'
CYAN='\033[36m'
DIM='\033[2m'
RESET='\033[0m'

# Check a single provider
# Usage: check_provider <name> <api_key_var> <model_var> <default_model> <test_endpoint> <test_payload>
check_provider() {
    local name="$1"
    local api_key="${!2:-}"
    local model_var="$3"
    local default_model="$4"
    local model="${!model_var:-$default_model}"

    if [[ -z "$api_key" ]]; then
        echo "no_key"
        return
    fi

    # Measure response time with a minimal request
    local start_time end_time duration
    start_time=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || date +%s)

    local http_code
    case "$name" in
        gemini)
            http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
                "https://generativelanguage.googleapis.com/v1beta/models/${model}?key=${api_key}" 2>/dev/null || echo "000")
            ;;
        openai)
            http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
                -H "Authorization: Bearer ${api_key}" \
                "https://api.openai.com/v1/models" 2>/dev/null || echo "000")
            ;;
        grok)
            http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
                -H "Authorization: Bearer ${api_key}" \
                "https://api.x.ai/v1/models" 2>/dev/null || echo "000")
            ;;
        nvidia)
            local base_url="${NVIDIA_BASE_URL:-https://integrate.api.nvidia.com/v1}"
            http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
                -H "Authorization: Bearer ${api_key}" \
                "${base_url%/}/models" 2>/dev/null || echo "000")
            ;;
        anthropic)
            http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
                -X POST \
                -H "x-api-key: ${api_key}" \
                -H "anthropic-version: 2023-06-01" \
                -H "Content-Type: application/json" \
                -d '{"model":"'${model}'","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' \
                "https://api.anthropic.com/v1/messages" 2>/dev/null || echo "000")
            ;;
        deepseek)
            http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
                -H "Authorization: Bearer ${api_key}" \
                "https://api.deepseek.com/models" 2>/dev/null || echo "000")
            ;;
        zai)
            local base_url="${ZAI_BASE_URL:-https://api.z.ai/api/paas/v4}"
            http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
                -H "Authorization: Bearer ${api_key}" \
                "${base_url%/}/models" 2>/dev/null || echo "000")
            ;;
        perplexity)
            # Perplexity has no /models endpoint; use minimal chat request
            http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
                -X POST \
                -H "Authorization: Bearer ${api_key}" \
                -H "Content-Type: application/json" \
                -d '{"model":"sonar","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' \
                "https://api.perplexity.ai/chat/completions" 2>/dev/null || echo "000")
            ;;
    esac

    end_time=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || date +%s)

    # Calculate duration
    duration=$((end_time - start_time))

    if [[ "$http_code" == "200" ]]; then
        echo "ok:${duration}:${model}"
    elif [[ "$http_code" == "000" ]]; then
        echo "timeout"
    elif [[ "$http_code" == "401" ]] || [[ "$http_code" == "403" ]]; then
        echo "auth_error:${http_code}"
    else
        echo "error:${http_code}"
    fi
}

# Check a CLI-based provider by binary presence + --version
# Usage: check_cli_provider <name> <binary>
check_cli_provider() {
    local name="$1"
    local binary="$2"

    if ! command -v "$binary" >/dev/null 2>&1; then
        echo "no_binary"
        return
    fi

    local start_time end_time duration version
    start_time=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || date +%s)

    if version=$("$binary" --version 2>/dev/null | head -1); then
        end_time=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || date +%s)
        duration=$((end_time - start_time))
        echo "ok:${duration}:${version:-cli}"
    else
        echo "error:exec_failed"
    fi
}

# Check an Ollama provider by asking the local/remote HTTP API for tags.
# Optional $1 overrides the model label (used by the Gemma 4 / Kimi members).
check_ollama_provider() {
    load_ollama_env

    local model_override="${1:-}"
    local base_url
    base_url=$(ollama_base_url)
    local model
    if [[ -n "$model_override" ]]; then
        model="$model_override"
    else
        model=$(ollama_default_model "$base_url")
    fi

    if ! ollama_is_available; then
        echo "no_binary"
        return
    fi

    local start_time end_time duration http_code
    start_time=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || date +%s)

    local headers=()
    if [[ -n "${OLLAMA_API_KEY:-}" ]]; then
        headers=(-H "Authorization: Bearer ${OLLAMA_API_KEY}")
    fi

    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        "${headers[@]}" \
        "${base_url%/}/api/tags" 2>/dev/null || echo "000")

    end_time=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || date +%s)
    duration=$((end_time - start_time))

    if [[ "$http_code" == "200" ]]; then
        echo "ok:${duration}:${model}"
    elif [[ "$http_code" == "000" ]]; then
        echo "timeout"
    elif [[ "$http_code" == "401" ]] || [[ "$http_code" == "403" ]]; then
        echo "auth_error:${http_code}"
    else
        echo "error:${http_code}"
    fi
}

# Main output
echo ""
echo -e "${DIM}Provider Status:${RESET}"
echo ""

# Check each provider
anthropic_status=$(check_provider "anthropic" "ANTHROPIC_API_KEY" "ANTHROPIC_MODEL" "claude-3-7-sonnet-20250219")
deepseek_status=$(check_provider "deepseek" "DEEPSEEK_API_KEY" "DEEPSEEK_MODEL" "deepseek-chat")
gemini_status=$(check_provider "gemini" "GEMINI_API_KEY" "GEMINI_MODEL" "gemini-3.1-pro-preview")
openai_status=$(check_provider "openai" "OPENAI_API_KEY" "OPENAI_MODEL" "gpt-5.5-pro")
grok_status=$(check_provider "grok" "GROK_API_KEY" "GROK_MODEL" "grok-4.20-reasoning")
nvidia_status=$(check_provider "nvidia" "NVIDIA_API_KEY" "NVIDIA_MODEL" "nvidia/llama-3.3-nemotron-super-49b-v1.5")
zai_status=$(check_provider "zai" "ZAI_API_KEY" "ZAI_MODEL" "glm-4.6")
ollama_status=$(check_ollama_provider)
ollama_gemma4_status=$(check_ollama_provider "$(ollama_gemma4_model)")
ollama_kimi_status=$(check_ollama_provider "$(ollama_kimi_model)")
perplexity_status=$(check_provider "perplexity" "PERPLEXITY_API_KEY" "PERPLEXITY_MODEL" "sonar-reasoning-pro")
codex_status=$(check_cli_provider "codex" "codex")
gemini_cli_status=$(check_cli_provider "gemini-cli" "gemini")

# Format output
format_status() {
    local emoji="$1"
    local color="$2"
    local name="$3"
    local status="$4"

    local status_icon status_text model_text=""

    case "$status" in
        no_key)
            status_icon="${DIM}--${RESET}"
            status_text="${DIM}API key not set${RESET}"
            ;;
        no_binary)
            status_icon="${DIM}--${RESET}"
            status_text="${DIM}CLI not installed${RESET}"
            ;;
        timeout)
            status_icon="${RED}x${RESET}"
            status_text="${RED}Connection timeout${RESET}"
            ;;
        auth_error:*)
            local code="${status#auth_error:}"
            status_icon="${RED}x${RESET}"
            status_text="${RED}Auth failed (HTTP ${code})${RESET}"
            ;;
        error:*)
            local code="${status#error:}"
            status_icon="${RED}x${RESET}"
            status_text="${RED}Error (HTTP ${code})${RESET}"
            ;;
        ok:*)
            local rest="${status#ok:}"
            local duration="${rest%%:*}"
            local model="${rest#*:}"
            status_icon="${GREEN}✓${RESET}"
            status_text="${GREEN}Connected${RESET} ${DIM}(${duration}ms)${RESET}"
            model_text="${DIM}${model}${RESET}"
            ;;
    esac

    echo -e "  ${emoji} ${color}${name}${RESET}\t${status_icon} ${status_text}  ${model_text}"
}

format_status "$(provider_emoji anthropic)"  "$(provider_color anthropic)"  "Anthropic"  "$anthropic_status"
format_status "$(provider_emoji deepseek)"   "$(provider_color deepseek)"   "DeepSeek"   "$deepseek_status"
format_status "$(provider_emoji gemini)"     "$(provider_color gemini)"     "Gemini"     "$gemini_status"
format_status "$(provider_emoji openai)"     "$(provider_color openai)"     "OpenAI"     "$openai_status"
format_status "$(provider_emoji grok)"       "$(provider_color grok)"       "Grok"       "$grok_status"
format_status "$(provider_emoji nvidia)"     "$(provider_color nvidia)"     "NVIDIA"     "$nvidia_status"
format_status "$(provider_emoji zai)"        "$(provider_color zai)"        "z.ai (GLM)" "$zai_status"
format_status "$(provider_emoji ollama)"     "$(provider_color ollama)"     "Ollama"     "$ollama_status"
format_status "$(provider_emoji ollama-gemma4)" "$(provider_color ollama-gemma4)" "Ollama Gemma4" "$ollama_gemma4_status"
format_status "$(provider_emoji ollama-kimi)" "$(provider_color ollama-kimi)" "Ollama Kimi" "$ollama_kimi_status"
format_status "$(provider_emoji perplexity)" "$(provider_color perplexity)" "Perplexity" "$perplexity_status"
format_status "$(provider_emoji codex)"      "$(provider_color codex)"      "Codex CLI"  "$codex_status"
format_status "$(provider_emoji gemini-cli)" "$(provider_color gemini-cli)" "Gemini CLI" "$gemini_cli_status"

echo ""

# Summary
available=0
[[ "$anthropic_status" == ok:* ]] && available=$((available + 1))
[[ "$deepseek_status" == ok:* ]] && available=$((available + 1))
[[ "$gemini_status" == ok:* ]] && available=$((available + 1))
[[ "$openai_status" == ok:* ]] && available=$((available + 1))
[[ "$grok_status" == ok:* ]] && available=$((available + 1))
[[ "$nvidia_status" == ok:* ]] && available=$((available + 1))
[[ "$zai_status" == ok:* ]] && available=$((available + 1))
[[ "$ollama_status" == ok:* ]] && available=$((available + 1))
[[ "$ollama_gemma4_status" == ok:* ]] && available=$((available + 1))
[[ "$ollama_kimi_status" == ok:* ]] && available=$((available + 1))
[[ "$perplexity_status" == ok:* ]] && available=$((available + 1))
[[ "$codex_status" == ok:* ]] && available=$((available + 1))
[[ "$gemini_cli_status" == ok:* ]] && available=$((available + 1))

echo -e "${DIM}${available}/13 providers available${RESET}"
echo ""
