#!/bin/bash
# ABOUTME: Shared retry logic for API calls with exponential backoff
# ABOUTME: Source this file and use curl_with_retry instead of curl

# Configuration via environment variables
COUNCIL_MAX_RETRIES="${COUNCIL_MAX_RETRIES:-2}"
COUNCIL_RETRY_DELAY="${COUNCIL_RETRY_DELAY:-1}"
COUNCIL_TIMEOUT="${COUNCIL_TIMEOUT:-120}"  # seconds per request (bounded so 429 backoff fails fast; COUNCIL_JOB_TIMEOUT is the hard cap)

# HTTP status codes that should trigger a retry
is_retryable_status() {
    local status="$1"
    case "$status" in
        429|500|502|503|504) return 0 ;;  # Retryable
        *) return 1 ;;  # Not retryable
    esac
}

# Check if curl exit code indicates timeout
is_timeout_error() {
    local exit_code="$1"
    # curl exit 28 = operation timeout
    [[ "$exit_code" -eq 28 ]]
}

# Perform curl with retry logic
# Usage: curl_with_retry [curl_args...]
# Returns: curl exit code, outputs response to stdout
curl_with_retry() {
    local attempt=0
    local delay="$COUNCIL_RETRY_DELAY"
    local response=""
    local http_code=""
    local curl_exit=""
    local temp_file
    temp_file=$(mktemp)

    while [[ $attempt -le $COUNCIL_MAX_RETRIES ]]; do
        # Make request with timeout, capture HTTP status code separately
        http_code=$(curl -s --max-time "$COUNCIL_TIMEOUT" -w "%{http_code}" -o "$temp_file" "$@")
        curl_exit=$?
        response=$(cat "$temp_file")

        # Check for timeout (curl exit 28) - don't retry, fail fast
        if is_timeout_error "$curl_exit"; then
            [[ -n "$DEBUG" ]] && echo "=== TIMEOUT: Request exceeded ${COUNCIL_TIMEOUT}s ===" >&2
            rm -f "$temp_file"
            echo '{"error": {"message": "Request timed out after '"$COUNCIL_TIMEOUT"' seconds"}}'
            return 28
        fi

        # Check for other curl errors (network issues, DNS)
        if [[ $curl_exit -ne 0 ]]; then
            if [[ $attempt -lt $COUNCIL_MAX_RETRIES ]]; then
                [[ -n "$DEBUG" ]] && echo "=== RETRY: curl failed (exit $curl_exit), attempt $((attempt + 1))/$COUNCIL_MAX_RETRIES, waiting ${delay}s ===" >&2
                sleep "$delay"
                delay=$((delay * 2))
                attempt=$((attempt + 1))
                continue
            else
                rm -f "$temp_file"
                echo "$response"
                return $curl_exit
            fi
        fi

        # Check for retryable HTTP status codes
        if is_retryable_status "$http_code"; then
            if [[ $attempt -lt $COUNCIL_MAX_RETRIES ]]; then
                [[ -n "$DEBUG" ]] && echo "=== RETRY: HTTP $http_code, attempt $((attempt + 1))/$COUNCIL_MAX_RETRIES, waiting ${delay}s ===" >&2
                sleep "$delay"
                delay=$((delay * 2))
                attempt=$((attempt + 1))
                continue
            fi
        fi

        # Success or non-retryable error
        rm -f "$temp_file"
        echo "$response"
        return 0
    done

    rm -f "$temp_file"
    echo "$response"
    return 0
}

# POST a JSON body safely, then retry like curl_with_retry.
# Passing JSON through `-d "$PAYLOAD"` can be corrupted by Windows/MSYS argv
# handling when the payload contains non-ASCII text. Writing the body to a temp
# file and sending it with `--data-binary @file` avoids argv encoding issues and
# keeps retries using the same request body.
# Usage: curl_json_with_retry "$PAYLOAD" [curl_args...]   # do not include -d
curl_json_with_retry() {
    local payload="$1"
    shift
    local body_file
    body_file=$(mktemp)
    printf '%s' "$payload" > "$body_file"
    curl_with_retry "$@" --data-binary @"$body_file"
    local rc=$?
    rm -f "$body_file"
    return $rc
}
