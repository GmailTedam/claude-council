#!/usr/bin/env bats
# ABOUTME: Tests for scripts/lib/providers.sh
# ABOUTME: Covers provider metadata and dedicated Ollama model resolvers

load test_helper

LIB="${LIB_DIR}/providers.sh"

setup() {
    unset OLLAMA_ORNITH_MODEL OLLAMA_ORNITH_BASE_URL
}

@test "providers: ornith model defaults to ornith" {
    source "$LIB"
    run ollama_ornith_model
    [ "$status" -eq 0 ]
    [ "$output" = "ornith" ]
}

@test "providers: ornith model honors override" {
    export OLLAMA_ORNITH_MODEL="ornith:35b"
    source "$LIB"
    run ollama_ornith_model
    [ "$status" -eq 0 ]
    [ "$output" = "ornith:35b" ]
}

@test "providers: ornith provider has model and emoji metadata" {
    source "$LIB"

    run get_model ollama-ornith
    [ "$status" -eq 0 ]
    [ "$output" = "ornith" ]

    run provider_emoji ollama-ornith
    [ "$status" -eq 0 ]
    [ "$output" = "[N]" ]
}
