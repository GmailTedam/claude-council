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
| Ollama | none for local; optional `OLLAMA_API_KEY` for authenticated endpoints | qwen2.5-coder:7b |
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

Ollama is the local-provider route for AirLLM-enabled models on this workspace.
Discover it when `ollama` is on `PATH` or `OLLAMA_BASE_URL` points at a remote
Ollama-compatible endpoint. In WSL, the provider also probes the Windows host
gateway and `host.docker.internal` because Windows Ollama is not always exposed
on WSL's `127.0.0.1`. Use `OLLAMA_MODEL` to switch models.

Suitable council models from the local pull set:

- `qwen2.5-coder:7b` as the default coding reviewer.
- `devstral-small-2:24b` for slower but stronger agentic coding review.
- `mistral-small3.2:24b` or `gpt-oss:20b` for general architecture tradeoffs.
- `llama3.2:1b` only for smoke tests or very fast sanity checks.

Do not add embedding, OCR, vision, safety-classifier, or healthcare-specialized
models as default council members. Use those only for explicit task scopes:
`bge-m3`, `nomic-embed-text`, `glm-ocr`, `qwen3-vl`, `llama3.2-vision`,
`llama-guard3`, `medgemma`, `medllama2`, and healthcare fine-tunes are not
general software-engineering council defaults.

## Troubleshooting

- **Not discovered**: Check API key is set, local binary is on `PATH`, or
  provider script is executable
- **API errors**: Verify key, check rate limits, confirm model name
- **Parse fails**: Add `echo "$RESPONSE"` to debug, check response format

## Reference

For API patterns and code templates, see `api-patterns.md` in this directory.
