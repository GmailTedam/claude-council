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
