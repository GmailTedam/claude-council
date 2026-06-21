---
name: integrating-providers
description: Adds new AI providers to claude-council, configures provider API settings, troubleshoots provider connections, and documents the provider script interface. Covers creating provider shell scripts, setting API keys, and validating connectivity. Triggers on "add provider", "new AI agent", "provider not working", "API configuration", or "extend council".
---

# Adding AI Providers to Claude Council

## Provider Script Interface

Each provider is a shell script in `scripts/providers/` that:
1. Accepts a prompt as the first argument
2. Outputs the AI response to stdout
3. Exits 0 on success, non-zero on failure

## Quick Start

1. Create `scripts/providers/{name}.sh` (see `api-patterns.md` for templates)
2. `chmod +x scripts/providers/{name}.sh`
3. Set `{NAME}_API_KEY` environment variable
4. Test: `./scripts/providers/{name}.sh "Hello"`

## Current Providers

| Provider | API Key Variable | Default Model |
|----------|------------------|---------------|
| Anthropic | `ANTHROPIC_API_KEY` | claude-3-7-sonnet-20250219 |
| DeepSeek | `DEEPSEEK_API_KEY` | deepseek-chat |
| Gemini | `GEMINI_API_KEY` | gemini-3.1-pro-preview |
| OpenAI | `OPENAI_API_KEY` | gpt-5.5-pro |
| Grok | `XAI_API_KEY` (or `GROK_API_KEY`) | grok-4.20-reasoning |
| NVIDIA NIM | `NVIDIA_API_KEY` (or `NVIDIA_BUILD_API_KEY`) | nvidia/llama-3.3-nemotron-super-49b-v1.5 |
| Ollama | none for local; optional `OLLAMA_API_KEY` for authenticated endpoints | glm-5.2 / glm-5.2:cloud |
| Ollama (Gemma 4) | same discovery as Ollama; `OLLAMA_GEMMA4_MODEL` overrides the tag | gemma4:31b |
| Ollama (Kimi) | same discovery as Ollama; `OLLAMA_KIMI_MODEL` overrides the tag | kimi-k2.7-code |
| MedGemma (medical, opt-in) | `MEDGEMMA_API_KEY` or `HF_TOKEN` + `MEDGEMMA_BASE_URL`; query with `--providers=medgemma` | medgemma-27b-text-it |
| Perplexity | `PERPLEXITY_API_KEY` | sonar-reasoning-pro |

## NVIDIA NIM Notes

NVIDIA hosted NIM uses an OpenAI-compatible endpoint:
`https://integrate.api.nvidia.com/v1/chat/completions`.

Use `NVIDIA_API_KEY` as the canonical key name. Keep `NVIDIA_BUILD_API_KEY`
as a fallback for keys generated through NVIDIA Build. Set `NVIDIA_BASE_URL`
to a private or local NIM `/v1` endpoint when one is available. Good council
defaults:

- `nvidia/llama-3.3-nemotron-super-49b-v1.5` for broad architecture and implementation review
- `nvidia/nvidia-nemotron-nano-9b-v2` when latency matters more than depth
- `nvidia/nemotron-content-safety-reasoning-4b` only for explicit safety-classification checks

Hosted provider calls leave the local machine. Do not send PHI, patient data,
or other restricted clinical content unless the caller's data policy allows that
specific hosted provider path.

## Ollama / AirLLM Local Notes

Ollama is the local/cloud-provider route for AirLLM-enabled models on this
workspace. Discover it when `OLLAMA_API_KEY` is set, `ollama` is on `PATH`, or
`OLLAMA_BASE_URL` points at a remote Ollama-compatible endpoint. With
`OLLAMA_API_KEY` and no explicit `OLLAMA_BASE_URL`, use direct Ollama Cloud at
`https://ollama.com`. In WSL/Git Bash on Windows, the provider also reads
`OLLAMA_API_KEY` and `OLLAMA_PUBKEY` from the Windows process/user/machine
environment if Bash did not inherit them. `OLLAMA_PUBKEY` is not sent as
HTTP auth; direct cloud calls still use `OLLAMA_API_KEY` as the Bearer token.
In WSL, the provider also probes the Windows host gateway and
`host.docker.internal` because Windows Ollama is not always exposed on WSL's
`127.0.0.1`. Use `OLLAMA_MODEL` to switch models.

Suitable council models from Ollama:

- `glm-5.2` as the default direct Ollama Cloud coding reviewer.
- `glm-5.2:cloud` for the same model through a local Ollama daemon.
- `gemma4:31b` (Google Gemma 4) on Ollama Cloud for a second, vendor-diverse
  reviewer. Available as the dedicated `ollama-gemma4` council member (see below).
- `kimi-k2.7-code` (Moonshot Kimi K2.7 Code) on Ollama Cloud for a large
  coding-specialized reviewer. Available as the dedicated `ollama-kimi` member.
- `qwen2.5-coder:7b` as a local coding reviewer.
- `devstral-small-2:24b` for slower but stronger agentic coding review.
- `mistral-small3.2:24b` or `gpt-oss:20b` for general architecture tradeoffs.
- `llama3.2:1b` only for smoke tests or very fast sanity checks.

### Cloud-first policy

When a model exists both locally and on Ollama Cloud, prefer the cloud version,
and **always** use cloud when the local environment cannot host the model.
`ollama_base_url()` already puts `https://ollama.com` first whenever
`OLLAMA_API_KEY` is set, so every Ollama member routes to cloud when a key is
present. The large dedicated members (`ollama-gemma4`, `ollama-kimi`) are
cloud-first by necessity — their full builds do not fit on a typical
workstation. If/when local resources are sufficient, point a member at a local
tag via its `OLLAMA_*_MODEL` override; until then, keep them on cloud.

### Dedicated cloud members (`ollama-gemma4`, `ollama-kimi`)

`scripts/providers/ollama-gemma4.sh` and `scripts/providers/ollama-kimi.sh` run
Gemma 4 and Kimi K2.7 Code as their own council voices so they can be queried in
parallel with the GLM-backed `ollama` member (e.g.
`--providers=ollama,ollama-gemma4,ollama-kimi`). They are discovered under the
same conditions as `ollama` and resolve their model via `ollama_gemma4_model()`
(`gemma4:31b`, override `OLLAMA_GEMMA4_MODEL`) and `ollama_kimi_model()`
(`kimi-k2.7-code`, override `OLLAMA_KIMI_MODEL`).

Gemma 4 needs its own resolver because Ollama Cloud serves it only as the
colon-tagged `gemma4:31b` — bare `gemma4` 404s, and there is no `gemma4:cloud`
pointer. `ollama_default_model()` deliberately discards colon-tagged
`OLLAMA_MODEL` values on direct cloud (the "ignore stale local pins" guard), so
setting `OLLAMA_MODEL=gemma4:31b` on the generic `ollama` member would silently
fall back to `glm-5.2`. The dedicated member bypasses that guard. The same caveat
applies to any other colon-tagged *cloud* model (`qwen3-coder:480b`,
`deepseek-v3.1:671b`, `gpt-oss:120b`): select those via a dedicated member, not
`OLLAMA_MODEL` on direct cloud.

Do not add embedding, OCR, vision, safety-classifier, or healthcare-specialized
models as **default** council members. Use those only for explicit task scopes:
`bge-m3`, `nomic-embed-text`, `glm-ocr`, `qwen3-vl`, `llama3.2-vision`,
`llama-guard3`, `medgemma`, `medllama2`, `medsiglip`, and healthcare fine-tunes
are not general software-engineering council defaults. Medical generative models
can still be queried explicitly — see the opt-in MedGemma member below.

### MedGemma (medical, opt-in) — `scripts/providers/medgemma.sh`

MedGemma 4B / 27B (text and multimodal) are Google Health AI Developer
Foundations generative models. They are **not on Ollama Cloud** — serve them from
a Hugging Face Inference Endpoint, Google Cloud Vertex AI Model Garden, or any
OpenAI-compatible server (vLLM / TGI). `medgemma.sh` targets that
`/chat/completions` contract.

It is **opt-in**: deliberately never auto-discovered into the default council set
(`discover_providers` hard-sets it unavailable), so a medical model never answers
general software-engineering queries. Query it explicitly:

```bash
export MEDGEMMA_BASE_URL="https://<id>.endpoints.huggingface.cloud/v1"
# Token resolves as: MEDGEMMA_API_KEY > HF_TOKEN > HUGGINGFACEHUB_API_TOKEN >
# HF_ACCESS_TOKEN. For a Hugging Face endpoint, an existing HF_TOKEN is used
# automatically — no MEDGEMMA_API_KEY needed. For self-hosted / Vertex, set
# MEDGEMMA_API_KEY explicitly (it wins).
export MEDGEMMA_MODEL="medgemma-27b-text-it"   # or medgemma-4b-it
bash scripts/query-council.sh --providers=medgemma -- "clinical question"
```

This text path sends text only; multimodal (image) input is out of scope for the
council's chat contract. It uses a medical system prompt (override with
`MEDGEMMA_SYSTEM`), not the software-engineering persona.

**Data residency (PHI).** The call leaves this machine to `MEDGEMMA_BASE_URL`.
For patient data under UK GDPR / DPA 2018 (NHS context), the recommended
deployment is a **self-hosted vLLM/TGI endpoint in your own UK/EU VPC** so data
never leaves your tenancy; a **single-tenant HF Inference Endpoint pinned to a
UK/EU region** (e.g. AWS `eu-west-2`) with a DPA is an acceptable lighter-ops
fallback. Both speak the OpenAI-compatible `/chat/completions` contract this
provider targets, so no code change is needed — only the env vars. Do **not**
route PHI through multi-tenant or US-default inference, or through Ollama Cloud.

**Vertex AI** is also supported: set `MEDGEMMA_AUTH=gcloud` and the provider mints
a short-lived OAuth token via `gcloud auth print-access-token` (point
`MEDGEMMA_BASE_URL` at the Vertex `/endpoints/openapi` base). It makes Google a
processor, so prefer self-host for sovereignty.

**Full deployment guide (self-host / HF endpoint / Vertex, with commands):** see
[`docs/MEDGEMMA.md`](../../docs/MEDGEMMA.md).

**MedSigLIP is intentionally excluded** as a council member: it is a 400M
image/text *encoder* (zero-shot classification, semantic image retrieval) with
**no text generation**, so it cannot produce a council response. Use it as a
task-specific medical-imaging tool, not a deliberation voice.

## Troubleshooting

- **Not discovered**: Check API key is set, local binary is on `PATH`, or
  provider script is executable
- **API errors**: Verify key, check rate limits, confirm model name
- **Parse fails**: Add `echo "$RESPONSE"` to debug, check response format

## Reference

For API patterns and code templates, see `api-patterns.md` in this directory.
