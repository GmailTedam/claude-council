#!/bin/bash
# ABOUTME: Provider discovery + selection policy shared by query-council.sh
# ABOUTME: Caller must export PROVIDERS_DIR before sourcing for discover_providers

# Discover which provider scripts are available to query.
# API providers are gated on their <NAME>_API_KEY env var; subscription-auth
# CLI/local/cloud providers (codex, gemini-cli, ollama) are gated on their
# binary, endpoint, or cloud API key being available.
discover_providers() {
    local available=()

    for script in "${PROVIDERS_DIR}"/*.sh; do
        [[ -f "$script" ]] || continue
        local name
        name=$(basename "$script" .sh)
        local is_available=false

        case "$name" in
            codex)
                if [[ "${COUNCIL_DISABLE_CLI_DISCOVERY:-}" != "1" ]]; then
                    command -v codex >/dev/null 2>&1 && is_available=true
                fi
                ;;
            gemini-cli)
                if [[ "${COUNCIL_DISABLE_CLI_DISCOVERY:-}" != "1" ]]; then
                    command -v gemini >/dev/null 2>&1 && is_available=true
                fi
                ;;
            ollama)
                ollama_is_available && is_available=true
                ;;
            anthropic)  [[ -n "${ANTHROPIC_API_KEY:-}" ]] && is_available=true ;;
            deepseek)   [[ -n "${DEEPSEEK_API_KEY:-}" ]] && is_available=true ;;
            gemini)     [[ -n "${GEMINI_API_KEY:-}" ]] && is_available=true ;;
            openai)     [[ -n "${OPENAI_API_KEY:-}" ]] && is_available=true ;;
            grok)       [[ -n "${GROK_API_KEY:-}" ]] && is_available=true ;;
            nvidia)     [[ -n "${NVIDIA_API_KEY:-}" || -n "${NVIDIA_BUILD_API_KEY:-}" ]] && is_available=true ;;
            *)
                local up_var
                up_var=$(echo "$name" | tr '[:lower:]' '[:upper:]')_API_KEY
                [[ -n "${!up_var:-}" ]] && is_available=true
                ;;
        esac

        if [[ "$is_available" == true ]]; then
            available+=("$name")
        fi
    done

    echo "${available[@]+"${available[@]}"}"
}

# Single source of truth for the API↔CLI shadowing pairs. Returns the name
# of the CLI provider that shadows the given API provider (or empty if the
# provider has no CLI sibling). Adding a new pair is a one-line change here
# that automatically propagates to prefer_cli_over_api and to the human
# display in query-council.sh's --list-available output.
shadow_origin() {
    case "$1" in
        openai) echo "codex" ;;
        gemini) echo "gemini-cli" ;;
        *)      echo "" ;;
    esac
}

# Apply the CLI-prefers-API policy to a list of provider names.
# When a provider's CLI shadow (per shadow_origin) is also in the input,
# drop that API provider. Explicit --providers always wins over this policy.
#
# Args: provider names (one per arg)
# Stdout: filtered names, space-separated, original order preserved
prefer_cli_over_api() {
    # Space-padded set string for bash 3.2 compat (no associative arrays).
    # Padding ensures word-boundary matches (e.g., "ai" won't match in "openai").
    local available=" $* "
    local p out=() shadow_cli
    for p in "$@"; do
        shadow_cli=$(shadow_origin "$p")
        if [[ -n "$shadow_cli" && "$available" == *" $shadow_cli "* ]]; then
            continue
        fi
        out+=("$p")
    done
    echo "${out[@]+"${out[@]}"}"
}

# Discovery + policy in one step: the providers a default query would run.
default_provider_set() {
    local discovered
    read -ra discovered <<< "$(discover_providers)"
    prefer_cli_over_api "${discovered[@]+"${discovered[@]}"}"
}

windows_env_value() {
    [[ "${COUNCIL_DISABLE_WINDOWS_ENV_FALLBACK:-}" == "1" ]] && return 0

    local name="$1"
    case "$name" in
        OLLAMA_API_KEY|OLLAMA_PUBKEY) ;;
        *) return 0 ;;
    esac

    local ps=""
    local candidate
    for candidate in powershell.exe powershell pwsh.exe pwsh; do
        if command -v "$candidate" >/dev/null 2>&1; then
            ps="$candidate"
            break
        fi
    done
    [[ -n "$ps" ]] || return 0

    "$ps" -NoProfile -NonInteractive -Command "\$v = [Environment]::GetEnvironmentVariable('$name', 'Process'); if ([string]::IsNullOrEmpty(\$v)) { \$v = [Environment]::GetEnvironmentVariable('$name', 'User') }; if ([string]::IsNullOrEmpty(\$v)) { \$v = [Environment]::GetEnvironmentVariable('$name', 'Machine') }; [Console]::Out.Write(\$v)" 2>/dev/null | tr -d '\r'
}

load_ollama_env() {
    if [[ -z "${OLLAMA_API_KEY:-}" ]]; then
        local api_key
        api_key=$(windows_env_value OLLAMA_API_KEY)
        [[ -n "$api_key" ]] && export OLLAMA_API_KEY="$api_key"
    fi

    if [[ -z "${OLLAMA_PUBKEY:-}" ]]; then
        local pubkey
        pubkey=$(windows_env_value OLLAMA_PUBKEY)
        [[ -n "$pubkey" ]] && export OLLAMA_PUBKEY="$pubkey"
    fi

    return 0
}

# Candidate Ollama endpoints. Direct Ollama Cloud uses https://ollama.com when
# OLLAMA_API_KEY is set. The Windows desktop app is reachable from WSL through
# the default gateway or host.docker.internal, not always 127.0.0.1.
ollama_candidate_base_urls() {
    load_ollama_env

    if [[ -n "${OLLAMA_BASE_URL:-}" ]]; then
        echo "${OLLAMA_BASE_URL%/}"
        return
    fi

    if [[ -n "${OLLAMA_API_KEY:-}" ]]; then
        echo "https://ollama.com"
    fi

    echo "http://127.0.0.1:11434"

    local gateway=""
    if command -v ip >/dev/null 2>&1; then
        gateway=$(ip route 2>/dev/null | awk '/^default / { print $3; exit }')
    fi
    [[ -n "$gateway" ]] && echo "http://${gateway}:11434"

    echo "http://host.docker.internal:11434"
}

ollama_base_url() {
    load_ollama_env

    local base
    for base in $(ollama_candidate_base_urls); do
        local curl_args=(-fsS --max-time 1)
        if [[ -n "${OLLAMA_API_KEY:-}" ]]; then
            curl_args+=(-H "Authorization: Bearer ${OLLAMA_API_KEY}")
        fi
        if curl "${curl_args[@]}" "${base%/}/api/tags" >/dev/null 2>&1; then
            echo "${base%/}"
            return
        fi
    done

    if [[ -n "${OLLAMA_BASE_URL:-}" ]]; then
        echo "${OLLAMA_BASE_URL%/}"
    elif [[ -n "${OLLAMA_API_KEY:-}" ]]; then
        echo "https://ollama.com"
    else
        echo "http://127.0.0.1:11434"
    fi
}

ollama_is_available() {
    load_ollama_env

    [[ -n "${OLLAMA_BASE_URL:-}" ]] && return 0
    [[ -n "${OLLAMA_API_KEY:-}" ]] && return 0
    if [[ "${COUNCIL_DISABLE_CLI_DISCOVERY:-}" != "1" ]]; then
        command -v ollama >/dev/null 2>&1 && return 0
        command -v ollama.exe >/dev/null 2>&1 && return 0
    fi
    [[ "${COUNCIL_DISABLE_OLLAMA_HTTP_DISCOVERY:-}" == "1" ]] && return 1

    local base
    for base in $(ollama_candidate_base_urls); do
        local curl_args=(-fsS --max-time 1)
        if [[ -n "${OLLAMA_API_KEY:-}" ]]; then
            curl_args+=(-H "Authorization: Bearer ${OLLAMA_API_KEY}")
        fi
        if curl "${curl_args[@]}" "${base%/}/api/tags" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

ollama_default_model() {
    load_ollama_env

    local base="${1:-${OLLAMA_BASE_URL:-}}"
    if [[ -z "$base" && -n "${OLLAMA_API_KEY:-}" ]]; then
        base="https://ollama.com"
    fi
    local configured_model="${OLLAMA_MODEL:-}"

    case "${base%/}" in
        https://ollama.com|https://www.ollama.com)
            case "$configured_model" in
                ""|qwen*|*:*) echo "glm-5.2" ;;
                *)            echo "$configured_model" ;;
            esac
            ;;
        *)
            if [[ -n "$configured_model" ]]; then
                echo "$configured_model"
            else
                echo "glm-5.2:cloud"
            fi
            ;;
    esac
}

# Default model per provider. CLI defaults mirror what the CLI itself picks
# when invoked without -m, so the cache key and pane header match what's
# actually run. Bump when the CLI ships a new default we want to track.
get_model() {
    case "$1" in
        anthropic)  echo "${ANTHROPIC_MODEL:-claude-3-7-sonnet-20250219}" ;;
        deepseek)   echo "${DEEPSEEK_MODEL:-deepseek-chat}" ;;
        gemini)     echo "${GEMINI_MODEL:-gemini-3.1-pro-preview}" ;;
        openai)     echo "${OPENAI_MODEL:-gpt-5.5-pro}" ;;
        grok)       echo "${GROK_MODEL:-grok-4.20-reasoning}" ;;
        nvidia)     echo "${NVIDIA_MODEL:-nvidia/llama-3.3-nemotron-super-49b-v1.5}" ;;
        ollama)     ollama_default_model ;;
        perplexity) echo "${PERPLEXITY_MODEL:-sonar-reasoning-pro}" ;;
        codex)      echo "${CODEX_MODEL:-gpt-5.5}" ;;
        gemini-cli) echo "${GEMINI_CLI_MODEL:-gemini-3-flash-preview}" ;;
        *)          echo "unknown" ;;
    esac
}

# Vendor color for a provider name. CLI variants share their vendor's color
# (codex with openai, gemini-cli with gemini) since they speak for the same vendor.
# Caller is responsible for defining BLUE/WHITE/RED/GREEN/CYAN globals.
provider_color() {
    case "$1" in
        anthropic)         echo -e "${MAGENTA}" ;;
        deepseek)          echo -e "${YELLOW}" ;;
        gemini|gemini-cli) echo -e "${BLUE}" ;;
        openai|codex)      echo -e "${WHITE}" ;;
        grok)              echo -e "${RED}" ;;
        nvidia)            echo -e "${GREEN}" ;;
        ollama)            echo -e "${CYAN}" ;;
        perplexity)        echo -e "${GREEN}" ;;
        *)                 echo -e "${CYAN}" ;;
    esac
}

# Vendor emoji for a provider name. Same grouping as provider_color.
provider_emoji() {
    if [[ "$1" == "ollama" ]]; then
        echo "[O]"
        return
    fi

    case "$1" in
        anthropic)         echo "🟪" ;;
        deepseek)          echo "🟨" ;;
        gemini|gemini-cli) echo "🟦" ;;
        openai|codex)      echo "🔳" ;;
        grok)              echo "🟥" ;;
        nvidia)            echo "🟩" ;;
        perplexity)        echo "🟩" ;;
        *)                 echo "⬛" ;;
    esac
}
