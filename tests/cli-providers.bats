#!/usr/bin/env bats
# ABOUTME: Tests for codex/gemini-cli/ollama provider integration and CLI-prefers-API policy
# ABOUTME: Covers lib/providers.sh discovery + filter, plus query-council.sh wiring

load test_helper

SCRIPT="${SCRIPTS_DIR}/query-council.sh"
PROVIDERS_LIB="${LIB_DIR}/providers.sh"
PROVIDERS_DIR_REAL="${SCRIPTS_DIR}/providers"

setup() {
    mkdir -p "$TEST_CACHE_DIR"
    unset GEMINI_API_KEY OPENAI_API_KEY GROK_API_KEY PERPLEXITY_API_KEY NVIDIA_API_KEY NVIDIA_BUILD_API_KEY
    unset OLLAMA_API_KEY OLLAMA_BASE_URL OLLAMA_MODEL COUNCIL_DISABLE_CLI_DISCOVERY
}

teardown() {
    rm -rf "$TEST_CACHE_DIR"
}

# Source the lib in a subshell with PROVIDERS_DIR pointing at the real
# providers directory. Returns the function output to the bats `run` capture.
source_lib_and_call() {
    bash -c "
        set -euo pipefail
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        source '${PROVIDERS_LIB}'
        $*
    "
}

# ============================================================================
# discover_providers — binary-gated CLI providers
# ============================================================================

@test "discover_providers: includes codex when binary is on PATH" {
    if ! command_exists codex; then skip "codex CLI not installed"; fi
    run source_lib_and_call 'discover_providers'
    [ "$status" -eq 0 ]
    [[ "$output" == *"codex"* ]]
}

@test "discover_providers: includes gemini-cli when gemini binary is on PATH" {
    if ! command_exists gemini; then skip "gemini CLI not installed"; fi
    run source_lib_and_call 'discover_providers'
    [ "$status" -eq 0 ]
    [[ "$output" == *"gemini-cli"* ]]
}

@test "discover_providers: includes ollama when binary is on PATH" {
    if ! command_exists ollama; then skip "ollama CLI not installed"; fi
    run source_lib_and_call 'discover_providers'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ollama"* ]]
}

@test "discover_providers: excludes local providers when binaries are missing" {
    # Strip local provider binaries from PATH by running with a minimal PATH
    run bash -c "
        set -euo pipefail
        export PATH=/usr/bin:/bin
        unset OLLAMA_BASE_URL
        export COUNCIL_DISABLE_OLLAMA_HTTP_DISCOVERY=1
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        source '${PROVIDERS_LIB}'
        discover_providers
    "
    [ "$status" -eq 0 ]
    [[ "$output" != *"codex"* ]]
    [[ "$output" != *"gemini-cli"* ]]
    [[ "$output" != *"ollama"* ]]
}

@test "discover_providers: includes ollama when OLLAMA_BASE_URL is set" {
    run bash -c "
        set -euo pipefail
        export PATH=/usr/bin:/bin
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        export OLLAMA_BASE_URL='http://127.0.0.1:11434'
        source '${PROVIDERS_LIB}'
        discover_providers
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ollama"* ]]
}

@test "discover_providers: includes ollama when OLLAMA_API_KEY is set" {
    run bash -c "
        set -euo pipefail
        export PATH=/usr/bin:/bin
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        export OLLAMA_API_KEY='test-key'
        export COUNCIL_DISABLE_OLLAMA_HTTP_DISCOVERY=1
        source '${PROVIDERS_LIB}'
        discover_providers
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ollama"* ]]
}

@test "discover_providers: includes ollama-gemma4 when OLLAMA_API_KEY is set" {
    run bash -c "
        set -euo pipefail
        export PATH=/usr/bin:/bin
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        export OLLAMA_API_KEY='test-key'
        export COUNCIL_DISABLE_OLLAMA_HTTP_DISCOVERY=1
        source '${PROVIDERS_LIB}'
        discover_providers
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ollama-gemma4"* ]]
}

@test "discover_providers: includes ollama-kimi when OLLAMA_API_KEY is set" {
    run bash -c "
        set -euo pipefail
        export PATH=/usr/bin:/bin
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        export OLLAMA_API_KEY='test-key'
        export COUNCIL_DISABLE_OLLAMA_HTTP_DISCOVERY=1
        source '${PROVIDERS_LIB}'
        discover_providers
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ollama-kimi"* ]]
}

@test "discover_providers: excludes medgemma even when MEDGEMMA_API_KEY is set (opt-in only)" {
    run bash -c "
        set -euo pipefail
        export PATH=/usr/bin:/bin
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        export MEDGEMMA_API_KEY='test-key'
        export MEDGEMMA_BASE_URL='https://example.invalid/v1'
        export COUNCIL_DISABLE_OLLAMA_HTTP_DISCOVERY=1
        source '${PROVIDERS_LIB}'
        discover_providers
    "
    [ "$status" -eq 0 ]
    [[ "$output" != *"medgemma"* ]]
}

@test "discover_providers: includes ollama from Windows user env fallback" {
    local fake_bin="${TEST_TMP_DIR}/fake-bin"
    mkdir -p "$fake_bin"
    cat > "${fake_bin}/powershell.exe" <<'EOF'
#!/bin/sh
printf "test-key"
EOF
    chmod +x "${fake_bin}/powershell.exe"

    run bash -c "
        set -euo pipefail
        export PATH='${fake_bin}:/usr/bin:/bin'
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        unset OLLAMA_API_KEY OLLAMA_BASE_URL COUNCIL_DISABLE_WINDOWS_ENV_FALLBACK
        export COUNCIL_DISABLE_CLI_DISCOVERY=1
        export COUNCIL_DISABLE_OLLAMA_HTTP_DISCOVERY=1
        source '${PROVIDERS_LIB}'
        discover_providers
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ollama"* ]]
}

@test "ollama.sh: sends Authorization header from Windows env fallback" {
    local fake_bin="${TEST_TMP_DIR}/fake-bin"
    local curl_log="${TEST_TMP_DIR}/curl.args"
    mkdir -p "$fake_bin"
    cat > "${fake_bin}/powershell.exe" <<'EOF'
#!/bin/sh
printf "test-key"
EOF
    cat > "${fake_bin}/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CURL_ARGS_LOG"
out_file=
body='{"models":[]}'
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o)
            shift
            out_file="$1"
            ;;
        */api/chat)
            body='{"message":{"content":"OK"}}'
            ;;
    esac
    shift
done
if [ -n "$out_file" ]; then
    printf '%s' "$body" > "$out_file"
fi
printf '200'
EOF
    chmod +x "${fake_bin}/powershell.exe" "${fake_bin}/curl"

    run bash -c "
        set -euo pipefail
        export PATH='${fake_bin}:${PATH}'
        export CURL_ARGS_LOG='${curl_log}'
        unset OLLAMA_API_KEY OLLAMA_PUBKEY COUNCIL_DISABLE_WINDOWS_ENV_FALLBACK
        export OLLAMA_BASE_URL='https://ollama.com'
        '${PROVIDERS_DIR_REAL}/ollama.sh' 'Reply exactly: OK'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
    grep -q 'Authorization: Bearer test-key' "$curl_log"
}

@test "query-council: can query ollama cloud provider" {
    local fake_bin="${TEST_TMP_DIR}/fake-bin"
    local curl_log="${TEST_TMP_DIR}/curl.args"
    local prompt="In one short sentence, name one benefit of indexes."
    mkdir -p "$fake_bin"
    cat > "${fake_bin}/powershell.exe" <<'EOF'
#!/bin/sh
printf "test-key"
EOF
    cat > "${fake_bin}/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CURL_ARGS_LOG"
out_file=
body='{"models":[]}'
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o)
            shift
            out_file="$1"
            ;;
        */api/chat)
            body='{"message":{"content":"OK"}}'
            ;;
    esac
    shift
done
if [ -n "$out_file" ]; then
    printf '%s' "$body" > "$out_file"
fi
printf '200'
EOF
    chmod +x "${fake_bin}/powershell.exe" "${fake_bin}/curl"

    run bash -c "
        set -euo pipefail
        export PATH='${fake_bin}:${PATH}'
        export CURL_ARGS_LOG='${curl_log}'
        unset OLLAMA_API_KEY OLLAMA_PUBKEY COUNCIL_DISABLE_WINDOWS_ENV_FALLBACK
        export OLLAMA_BASE_URL='https://ollama.com'
        '${SCRIPT}' --providers ollama --no-cache --verbosity brief --no-pane --prompt '${prompt}' 2>/dev/null
    "
    [ "$status" -eq 0 ]
    [[ "$(echo "$output" | jq -r '.metadata.prompt')" == "$prompt" ]]
    [[ "$(echo "$output" | jq -r '.round1.ollama.status')" == "success" ]]
    [[ "$(echo "$output" | jq -r '.round1.ollama.model')" == "glm-5.2" ]]
    [[ "$(echo "$output" | jq -r '.round1.ollama.response')" == "OK" ]]
    grep -q 'Authorization: Bearer test-key' "$curl_log"
}

@test "discover_providers: excludes API providers when keys unset" {
    run source_lib_and_call 'discover_providers'
    [ "$status" -eq 0 ]
    [[ "$output" != *"openai"* ]]
    [[ "$output" != *"nvidia"* ]]
    [[ "$output" != *"perplexity"* ]]
}

@test "discover_providers: includes openai when OPENAI_API_KEY is set" {
    export OPENAI_API_KEY="test-key"
    run bash -c "
        set -euo pipefail
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        export OPENAI_API_KEY='test-key'
        source '${PROVIDERS_LIB}'
        discover_providers
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"openai"* ]]
}

@test "discover_providers: includes nvidia when NVIDIA_API_KEY is set" {
    export NVIDIA_API_KEY="test-key"
    run bash -c "
        set -euo pipefail
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        export NVIDIA_API_KEY='test-key'
        source '${PROVIDERS_LIB}'
        discover_providers
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"nvidia"* ]]
}

@test "discover_providers: includes nvidia when only NVIDIA_BUILD_API_KEY is set" {
    export NVIDIA_BUILD_API_KEY="test-key"
    run bash -c "
        set -euo pipefail
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        export NVIDIA_BUILD_API_KEY='test-key'
        source '${PROVIDERS_LIB}'
        discover_providers
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"nvidia"* ]]
}

@test "get_model: ollama defaults to GLM cloud model and respects override" {
    run source_lib_and_call 'get_model ollama'
    [ "$status" -eq 0 ]
    [[ "$output" == "glm-5.2:cloud" ]]

    run bash -c "
        set -euo pipefail
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        export OLLAMA_BASE_URL='https://ollama.com'
        source '${PROVIDERS_LIB}'
        get_model ollama
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "glm-5.2" ]]

    run bash -c "
        set -euo pipefail
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        export OLLAMA_MODEL='devstral-small-2:24b'
        source '${PROVIDERS_LIB}'
        get_model ollama
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "devstral-small-2:24b" ]]
}

@test "get_model: ollama-gemma4 defaults to gemma4:31b and respects override" {
    run source_lib_and_call 'get_model ollama-gemma4'
    [ "$status" -eq 0 ]
    [[ "$output" == "gemma4:31b" ]]

    run bash -c "
        set -euo pipefail
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        export OLLAMA_GEMMA4_MODEL='gemma4:custom'
        source '${PROVIDERS_LIB}'
        get_model ollama-gemma4
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "gemma4:custom" ]]
}

@test "get_model: ollama-kimi defaults to kimi-k2.7-code and respects override" {
    run source_lib_and_call 'get_model ollama-kimi'
    [ "$status" -eq 0 ]
    [[ "$output" == "kimi-k2.7-code" ]]

    run bash -c "
        set -euo pipefail
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        export OLLAMA_KIMI_MODEL='kimi-custom'
        source '${PROVIDERS_LIB}'
        get_model ollama-kimi
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "kimi-custom" ]]
}

@test "get_model: medgemma defaults to medgemma-27b-text-it and respects MEDGEMMA_MODEL" {
    run bash -c "
        set -euo pipefail
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        unset MEDGEMMA_MODEL
        source '${PROVIDERS_LIB}'
        get_model medgemma
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "medgemma-27b-text-it" ]]

    run bash -c "
        set -euo pipefail
        export PROVIDERS_DIR='${PROVIDERS_DIR_REAL}'
        export MEDGEMMA_MODEL='medgemma-4b-it'
        source '${PROVIDERS_LIB}'
        get_model medgemma
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "medgemma-4b-it" ]]
}

@test "medgemma.sh: errors clearly when no token is configured" {
    run bash -c "
        set -euo pipefail
        unset MEDGEMMA_API_KEY MEDGEMMA_BASE_URL HF_TOKEN HUGGINGFACEHUB_API_TOKEN HUGGING_FACE_HUB_TOKEN HF_ACCESS_TOKEN
        '${PROVIDERS_DIR_REAL}/medgemma.sh' 'test prompt'
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"no endpoint token found"* ]]
}

@test "medgemma.sh: falls back to HF_TOKEN when MEDGEMMA_API_KEY is unset" {
    run bash -c "
        set -euo pipefail
        unset MEDGEMMA_API_KEY MEDGEMMA_BASE_URL HUGGINGFACEHUB_API_TOKEN HUGGING_FACE_HUB_TOKEN HF_ACCESS_TOKEN
        export HF_TOKEN='hf-test-token'
        '${PROVIDERS_DIR_REAL}/medgemma.sh' 'test prompt'
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"MEDGEMMA_BASE_URL not set"* ]]
    [[ "$output" != *"no endpoint token found"* ]]
}

@test "medgemma.sh: MEDGEMMA_AUTH=gcloud mints a Vertex token via gcloud" {
    local fake_bin="${TEST_TMP_DIR}/fake-bin"
    mkdir -p "$fake_bin"
    cat > "${fake_bin}/gcloud" <<'EOF'
#!/bin/sh
printf 'vertex-access-token'
EOF
    chmod +x "${fake_bin}/gcloud"

    run bash -c "
        set -euo pipefail
        export PATH='${fake_bin}:${PATH}'
        export MEDGEMMA_AUTH=gcloud
        unset MEDGEMMA_API_KEY MEDGEMMA_BASE_URL
        '${PROVIDERS_DIR_REAL}/medgemma.sh' 'test prompt'
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"MEDGEMMA_BASE_URL not set"* ]]
    [[ "$output" != *"gcloud"* ]]
}

# ============================================================================
# prefer_cli_over_api — CLI-prefers-API policy
#
# These tests intentionally fail against the identity stub at lib/providers.sh.
# Alex's implementation of the policy turns them green. Per TDD: write the
# spec first, then the code.
# ============================================================================

@test "prefer_cli_over_api: identity when input is empty" {
    run source_lib_and_call 'prefer_cli_over_api'
    [ "$status" -eq 0 ]
    [[ -z "$(echo -n "$output" | tr -d '[:space:]')" ]]
}

@test "prefer_cli_over_api: identity when neither CLI is in input" {
    run source_lib_and_call 'prefer_cli_over_api openai gemini perplexity'
    [ "$status" -eq 0 ]
    [[ "$output" == *"openai"* ]]
    [[ "$output" == *"gemini"* ]]
    [[ "$output" == *"perplexity"* ]]
}

@test "prefer_cli_over_api: drops openai when codex is present" {
    run source_lib_and_call 'prefer_cli_over_api codex openai grok'
    [ "$status" -eq 0 ]
    [[ "$output" == *"codex"* ]]
    [[ "$output" == *"grok"* ]]
    [[ "$output" != *"openai"* ]]
}

@test "prefer_cli_over_api: drops gemini when gemini-cli is present" {
    run source_lib_and_call 'prefer_cli_over_api gemini-cli gemini perplexity'
    [ "$status" -eq 0 ]
    [[ "$output" == *"gemini-cli"* ]]
    [[ "$output" == *"perplexity"* ]]
    # The policy drops the API "gemini" but keeps "gemini-cli". A loose
    # substring match would falsely succeed (gemini-cli contains "gemini"),
    # so check word boundaries.
    [[ ! "$output" =~ (^|[[:space:]])gemini([[:space:]]|$) ]]
}

@test "prefer_cli_over_api: drops both API siblings when both CLIs present" {
    run source_lib_and_call 'prefer_cli_over_api codex gemini-cli openai gemini grok'
    [ "$status" -eq 0 ]
    [[ "$output" == *"codex"* ]]
    [[ "$output" == *"gemini-cli"* ]]
    [[ "$output" == *"grok"* ]]
    [[ "$output" != *"openai"* ]]
    [[ ! "$output" =~ (^|[[:space:]])gemini([[:space:]]|$) ]]
}

@test "prefer_cli_over_api: preserves input order" {
    run source_lib_and_call 'prefer_cli_over_api perplexity codex grok'
    [ "$status" -eq 0 ]
    # Expect "perplexity codex grok" — order preserved, nothing dropped
    [[ "$output" =~ perplexity[[:space:]]+codex[[:space:]]+grok ]]
}

# ============================================================================
# query-council.sh integration
# ============================================================================

@test "query-council: --list-available shows CLI providers when binaries present" {
    if ! command_exists codex && ! command_exists gemini; then
        skip "no CLI providers installed on this machine"
    fi
    run bash "$SCRIPT" --list-available
    [ "$status" -eq 0 ]
    if command_exists codex; then
        [[ "$output" == *"codex"* ]]
    fi
    if command_exists gemini; then
        [[ "$output" == *"gemini-cli"* ]]
    fi
}

@test "query-council: --list-available annotates shadowed API providers" {
    # When both OPENAI_API_KEY and codex are present, the human-readable
    # listing must show codex in the default set AND openai in the shadowed
    # section so the user can see both exist.
    if ! command_exists codex; then skip "codex CLI not installed"; fi
    export OPENAI_API_KEY="test-key"
    run bash "$SCRIPT" --list-available
    [ "$status" -eq 0 ]
    [[ "$output" == *"Default query set"* ]]
    [[ "$output" == *"codex"* ]]
    [[ "$output" == *"Shadowed"* ]]
    [[ "$output" == *"openai"* ]]
}

@test "query-council: --list-default returns post-policy set, machine-readable" {
    # Single space-separated line; CLI siblings drop their API counterparts.
    if ! command_exists codex; then skip "codex CLI not installed"; fi
    export OPENAI_API_KEY="test-key"
    run bash "$SCRIPT" --list-default
    [ "$status" -eq 0 ]
    # Exactly one line of output
    [[ $(echo "$output" | wc -l | tr -d ' ') == "1" ]]
    [[ "$output" == *"codex"* ]]
    # openai is shadowed, must not appear
    [[ ! "$output" =~ (^|[[:space:]])openai([[:space:]]|$) ]]
}

@test "query-council: --providers codex flag is accepted" {
    run bash "$SCRIPT" --providers=codex "test prompt" 2>&1
    [[ "$output" != *"Unknown flag"* ]]
}

@test "query-council: --providers gemini-cli flag is accepted" {
    run bash "$SCRIPT" --providers=gemini-cli "test prompt" 2>&1
    [[ "$output" != *"Unknown flag"* ]]
}

# ============================================================================
# End-to-end CLI provider invocation (gated — set COUNCIL_E2E=1 to run)
# ============================================================================

@test "codex.sh: returns response for trivial prompt (E2E)" {
    [[ "${COUNCIL_E2E:-}" == "1" ]] || skip "set COUNCIL_E2E=1 to run real CLI calls"
    if ! command_exists codex; then skip "codex CLI not installed"; fi
    run "${PROVIDERS_DIR_REAL}/codex.sh" "Reply with exactly the word: OK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "gemini-cli.sh: returns response for trivial prompt (E2E)" {
    [[ "${COUNCIL_E2E:-}" == "1" ]] || skip "set COUNCIL_E2E=1 to run real CLI calls"
    if ! command_exists gemini; then skip "gemini CLI not installed"; fi
    run "${PROVIDERS_DIR_REAL}/gemini-cli.sh" "Reply with exactly the word: OK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "ollama.sh: returns response for trivial prompt (E2E)" {
    [[ "${COUNCIL_E2E:-}" == "1" ]] || skip "set COUNCIL_E2E=1 to run real local calls"
    if ! command_exists ollama; then skip "ollama CLI not installed"; fi
    export OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.2:1b}"
    run "${PROVIDERS_DIR_REAL}/ollama.sh" "Reply briefly with any non-empty answer."
    [ "$status" -eq 0 ]
    [[ -n "$output" ]]
}
