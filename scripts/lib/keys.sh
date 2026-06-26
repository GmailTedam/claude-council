#!/bin/bash
# ABOUTME: Resolves provider API keys with vendor-name fallbacks
# ABOUTME: Source before any consumer reads a *_API_KEY variable

# Populates GROK_API_KEY from XAI_API_KEY when present.
# XAI_API_KEY (vendor-canonical) wins over GROK_API_KEY (legacy) when both are set,
# and conflicts are coalesced silently — see provider-integration SKILL for rationale.
resolve_grok_key() {
    if [[ -n "${XAI_API_KEY:-}" ]]; then
        export GROK_API_KEY="$XAI_API_KEY"
    fi
}

# Populates NVIDIA_API_KEY from NVIDIA_BUILD_API_KEY when present.
# NVIDIA_API_KEY wins because it is the provider-canonical name used by scripts.
resolve_nvidia_key() {
    if [[ -z "${NVIDIA_API_KEY:-}" && -n "${NVIDIA_BUILD_API_KEY:-}" ]]; then
        export NVIDIA_API_KEY="$NVIDIA_BUILD_API_KEY"
    fi
}

# Populates ZAI_API_KEY (script-canonical) from Z_AI_API_KEY (the name the user
# sets in the environment — an env var name cannot contain a dot, so the vendor
# "z.ai" becomes Z_AI). When the key is only set at Windows User/Machine scope
# (not exported into this already-running process), fall back to reading it via
# PowerShell — mirrors providers.sh's windows_env_value rescue for OLLAMA_*.
resolve_zai_key() {
    if [[ -z "${Z_AI_API_KEY:-}" && -z "${ZAI_API_KEY:-}" \
          && "${COUNCIL_DISABLE_WINDOWS_ENV_FALLBACK:-}" != "1" ]]; then
        local ps="" candidate val
        for candidate in powershell.exe powershell pwsh.exe pwsh; do
            if command -v "$candidate" >/dev/null 2>&1; then
                ps="$candidate"
                break
            fi
        done
        if [[ -n "$ps" ]]; then
            val=$("$ps" -NoProfile -NonInteractive -Command "\$v=[Environment]::GetEnvironmentVariable('Z_AI_API_KEY','Process'); if([string]::IsNullOrEmpty(\$v)){\$v=[Environment]::GetEnvironmentVariable('Z_AI_API_KEY','User')}; if([string]::IsNullOrEmpty(\$v)){\$v=[Environment]::GetEnvironmentVariable('Z_AI_API_KEY','Machine')}; [Console]::Out.Write(\$v)" 2>/dev/null | tr -d '\r' || true)
            [[ -n "$val" ]] && export Z_AI_API_KEY="$val"
        fi
    fi
    if [[ -n "${Z_AI_API_KEY:-}" ]]; then
        export ZAI_API_KEY="$Z_AI_API_KEY"
    fi
}
