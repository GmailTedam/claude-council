#!/bin/bash
# ABOUTME: Queries Google's MedGemma (medical) via an OpenAI-compatible cloud endpoint
# ABOUTME: Opt-in only (use --providers=medgemma); needs MEDGEMMA_BASE_URL + MEDGEMMA_API_KEY
#
# MedGemma 4B / 27B (text and multimodal) are Google Health AI Developer
# Foundations models. They are NOT on Ollama Cloud — they are served from
# Hugging Face Inference Endpoints, Google Cloud Vertex AI Model Garden, or any
# OpenAI-compatible server (vLLM / TGI). This provider targets that
# OpenAI-compatible `/chat/completions` contract.
#
# It is a domain-specific (medical) member and is deliberately opt-in: it is NOT
# auto-discovered into the default council set (see lib/providers.sh), so it
# never answers general software-engineering queries. Query it explicitly:
#   bash scripts/query-council.sh --providers=medgemma -- "clinical question"
#
# DATA RESIDENCY (read before sending any patient data):
# This member calls whatever MEDGEMMA_BASE_URL points at, and that call leaves
# this machine. For PHI / patient data under UK GDPR / DPA 2018 (NHS context),
# point it ONLY at an endpoint in an approved jurisdiction:
#   * Preferred: a self-hosted vLLM/TGI endpoint inside your own UK/EU VPC, so
#     data never leaves your tenancy (no third-party processor).
#   * Acceptable: a single-tenant Hugging Face Inference Endpoint pinned to a
#     UK/EU region (e.g. AWS eu-west-2 London) with a DPA in place.
# Do NOT route PHI through multi-tenant or US-default inference, or through
# Ollama Cloud. If your data policy does not approve the configured endpoint for
# the content being sent, do not use this member for that content.
#
# Required env:
#   MEDGEMMA_BASE_URL  OpenAI-compatible base. Examples:
#                        HF endpoint : https://<id>.<region>.aws.endpoints.huggingface.cloud/v1
#                        self-host   : https://<your-uk-host>:8000/v1   (vLLM/TGI)
#                        Vertex AI   : https://<loc>-aiplatform.googleapis.com/v1beta1/projects/<proj>/locations/<loc>/endpoints/openapi
#   <a bearer token>   resolved by MEDGEMMA_AUTH:
#                        bearer (default): MEDGEMMA_API_KEY (self-hosted/static token),
#                          else HF_TOKEN / HUGGINGFACEHUB_API_TOKEN / HF_ACCESS_TOKEN
#                          (an existing HF token is used as-is for an HF endpoint).
#                        gcloud: mint a short-lived Vertex AI OAuth token via the
#                          gcloud CLI (`gcloud auth print-access-token`).
# Optional env:
#   MEDGEMMA_AUTH      `bearer` (default) or `gcloud` (Vertex AI).
#   MEDGEMMA_MODEL     Model id (default: medgemma-27b-text-it). Point at your
#                      deployed variant: medgemma-4b-it / medgemma-27b-text-it /
#                      medgemma-27b-it (multimodal; this text path sends text only).
#                      For self-hosted vLLM this must match the served id
#                      (e.g. google/medgemma-27b-text-it) unless --served-model-name.
#   MEDGEMMA_SYSTEM    Override the default medical system prompt.
#
# See docs/MEDGEMMA.md for full deployment + data-residency guidance.
#
# NOTE: MedSigLIP is intentionally NOT a council member — it is a 400M image/text
# ENCODER (zero-shot classification, image retrieval) with no text generation, so
# it cannot produce a council response. Use it as a task-specific imaging tool.

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

# Bearer token for the endpoint, resolved by auth mode (MEDGEMMA_AUTH):
#   gcloud  -> Vertex AI: mint a short-lived OAuth token via the gcloud CLI.
#   bearer  -> (default) static token: MEDGEMMA_API_KEY wins (self-hosted vLLM/TGI
#              token), else a Hugging Face token (HF_TOKEN and friends) used as-is.
if [[ "${MEDGEMMA_AUTH:-bearer}" == "gcloud" ]]; then
    if ! command -v gcloud >/dev/null 2>&1; then
        echo "Error: MEDGEMMA_AUTH=gcloud but gcloud is not on PATH (install the Google Cloud CLI, then: gcloud auth login)" >&2
        exit 1
    fi
    API_KEY=$(gcloud auth print-access-token 2>/dev/null || true)
    if [[ -z "$API_KEY" ]]; then
        echo "Error: gcloud auth print-access-token returned no token (run: gcloud auth login)" >&2
        exit 1
    fi
else
    API_KEY="${MEDGEMMA_API_KEY:-${HF_TOKEN:-${HUGGINGFACEHUB_API_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-${HF_ACCESS_TOKEN:-}}}}}"
    if [[ -z "$API_KEY" ]]; then
        echo "Error: no endpoint token found. Set MEDGEMMA_API_KEY (self-hosted static token) or HF_TOKEN (Hugging Face endpoint), or MEDGEMMA_AUTH=gcloud for Vertex AI." >&2
        exit 1
    fi
fi

BASE_URL="${MEDGEMMA_BASE_URL:-}"
if [[ -z "$BASE_URL" ]]; then
    echo "Error: MEDGEMMA_BASE_URL not set (OpenAI-compatible endpoint base, e.g. https://<id>.endpoints.huggingface.cloud/v1)" >&2
    exit 1
fi

MODEL="${MEDGEMMA_MODEL:-medgemma-27b-text-it}"
BASE_TOKENS="${COUNCIL_MAX_TOKENS:-2048}"

# MedGemma is a medical model; do not prime it with the council's software
# persona. Default to a clinical-domain system prompt (override with MEDGEMMA_SYSTEM).
MED_SYSTEM_DEFAULT="You are MedGemma, a medical domain assistant. Provide accurate, evidence-based clinical information and reasoning. State uncertainty and cite guideline-level sources where relevant. This is decision support for qualified professionals, not a substitute for professional medical judgement or a diagnosis."
MED_SYSTEM="${MEDGEMMA_SYSTEM:-$MED_SYSTEM_DEFAULT}"
SYSTEM="${VERBOSITY_PREFIX:+$VERBOSITY_PREFIX }$MED_SYSTEM"
ENDPOINT="${BASE_URL%/}/chat/completions"

PAYLOAD=$(jq -n --arg prompt "$PROMPT" --arg model "$MODEL" --argjson tokens "$BASE_TOKENS" --arg system "$SYSTEM" '{
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
    echo "=== DEBUG: MedGemma ===" >&2
    echo "Endpoint: $ENDPOINT" >&2
    echo "Model: $MODEL" >&2
    echo "Max tokens: $BASE_TOKENS" >&2
fi

RESPONSE=$(curl_with_retry -s -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d "$PAYLOAD")

TEXT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // .message.content // empty')

if [[ -z "$TEXT" ]]; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error.message // .error // .detail // empty')
    if [[ -z "$ERROR" ]]; then
        echo "Error from MedGemma: Unable to parse response" >&2
        echo "Raw response: $RESPONSE" >&2
    else
        echo "Error from MedGemma: $ERROR" >&2
    fi
    exit 1
fi

echo "$TEXT"
