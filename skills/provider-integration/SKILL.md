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
| Gemini | `GEMINI_API_KEY` | gemini-3.1-pro-preview |
| OpenAI | `OPENAI_API_KEY` | gpt-5.5-pro |
| Grok | `XAI_API_KEY` (or `GROK_API_KEY`) | grok-4.20-reasoning |
| NVIDIA NIM | `NVIDIA_API_KEY` (or `NVIDIA_BUILD_API_KEY`) | nvidia/llama-3.3-nemotron-super-49b-v1.5 |
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

## Troubleshooting

- **Not discovered**: Check API key is set and script is executable
- **API errors**: Verify key, check rate limits, confirm model name
- **Parse fails**: Add `echo "$RESPONSE"` to debug, check response format

## Reference

For API patterns and code templates, see `api-patterns.md` in this directory.
