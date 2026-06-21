# MedGemma council member (opt-in, medical)

`scripts/providers/medgemma.sh` adds Google's **MedGemma** (Health AI Developer
Foundations) to the council as an **opt-in** member. It is deliberately **never
auto-discovered** into the default council set, so a medical model never answers
general software-engineering queries. Query it explicitly:

```bash
bash scripts/query-council.sh --providers=medgemma -- "clinical question"
```

It speaks the OpenAI-compatible `/chat/completions` contract, so it works with a
self-hosted server, a Hugging Face Inference Endpoint, or Vertex AI.

> **MedSigLIP is intentionally not a council member.** It is a 400M image/text
> *encoder* (zero-shot classification, semantic image retrieval) with **no text
> generation**, so it cannot produce a council response. Use it as a
> task-specific medical-imaging tool, not a deliberation voice.

## Models

| Model id | Size | Notes |
|----------|------|-------|
| `medgemma-4b-it` | 4B | Text + image in, text out. ~16–24 GB GPU to self-host. |
| `medgemma-27b-text-it` | 27B | Text only. **Default.** ~1×80 GB GPU (or quantized). |
| `medgemma-27b-it` | 27B | Multimodal. This provider's text path sends text only. |

Set the served id with `MEDGEMMA_MODEL`. For self-hosted vLLM it must match what
the server advertises (the full repo id, e.g. `google/medgemma-27b-text-it`,
unless you pass `--served-model-name`).

## Data residency (PHI) — read first

Each call leaves this machine to `MEDGEMMA_BASE_URL`. For patient data under UK
GDPR / DPA 2018 (NHS context), point it **only** at an endpoint in an approved
jurisdiction:

1. **Self-hosted vLLM/TGI in your own UK/EU VPC — strongest.** PHI never leaves
   your tenancy; no third-party processor.
2. **Single-tenant HF Inference Endpoint pinned to a UK/EU region**
   (e.g. AWS `eu-west-2` London) with a DPA — acceptable, lighter ops.
3. **Vertex AI Model Garden (`europe-west2`)** — viable; Google is a processor.

Do **not** route PHI through multi-tenant / US-default inference, the HF
serverless router, or Ollama Cloud.

## Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `MEDGEMMA_BASE_URL` | yes | OpenAI-compatible base (see per-path examples below). |
| `MEDGEMMA_AUTH` | no | `bearer` (default) or `gcloud` (Vertex AI). |
| `MEDGEMMA_API_KEY` | path-dependent | Static bearer token (self-hosted / static Vertex). Wins over HF tokens. |
| `HF_TOKEN` | path-dependent | Used as-is for an HF endpoint when `MEDGEMMA_API_KEY` is unset. Also `HUGGINGFACEHUB_API_TOKEN`, `HF_ACCESS_TOKEN`. |
| `MEDGEMMA_MODEL` | no | Served model id (default `medgemma-27b-text-it`). |
| `MEDGEMMA_SYSTEM` | no | Override the default medical system prompt. |

**Token resolution** (default `MEDGEMMA_AUTH=bearer`):
`MEDGEMMA_API_KEY` → `HF_TOKEN` → `HUGGINGFACEHUB_API_TOKEN` →
`HUGGING_FACE_HUB_TOKEN` → `HF_ACCESS_TOKEN`.
With `MEDGEMMA_AUTH=gcloud`, the token is minted via `gcloud auth print-access-token`.

## Path A — Self-hosted vLLM (strongest residency)

This workstation cannot host MedGemma (even 4B-class strains it). Use a GPU VM in
a UK/EU region.

1. Accept the model licence on its Hugging Face page.
2. Mint a shared secret (the "self-hosted key") — keep it out of shell history:
   ```bash
   openssl rand -hex 32        # or: python -c "import secrets; print(secrets.token_hex(32))"
   ```
3. On the VM:
   ```bash
   export KEY="<that value>"
   huggingface-cli login --token "$HF_TOKEN"     # download gated weights
   pip install vllm
   vllm serve google/medgemma-27b-text-it \
     --api-key "$KEY" --host 0.0.0.0 --port 8000
   ```
4. Wire the council:
   ```bash
   export MEDGEMMA_BASE_URL="https://<your-uk-host>:8000/v1"
   export MEDGEMMA_API_KEY="$KEY"
   export MEDGEMMA_MODEL="google/medgemma-27b-text-it"
   bash scripts/query-council.sh --providers=medgemma -- "clinical question"
   ```

## Path B — Hugging Face Inference Endpoint (fastest; HF_TOKEN already wired)

1. Create a **dedicated** endpoint for `google/medgemma-27b-text-it`, **region
   pinned to AWS `eu-west-2` (London)**, TGI container.
2. Wire the council — no `MEDGEMMA_API_KEY` needed; your existing `HF_TOKEN`
   authenticates automatically:
   ```bash
   export MEDGEMMA_BASE_URL="https://<id>.eu-west-2.aws.endpoints.huggingface.cloud/v1"
   export MEDGEMMA_MODEL="google/medgemma-27b-text-it"
   bash scripts/query-council.sh --providers=medgemma -- "clinical question"
   ```

## Path C — Vertex AI Model Garden

1. `gcloud auth login` (and select the project/region, e.g. `europe-west2`).
2. Wire the council with `MEDGEMMA_AUTH=gcloud` (mints a short-lived OAuth token):
   ```bash
   export MEDGEMMA_AUTH=gcloud
   export MEDGEMMA_BASE_URL="https://europe-west2-aiplatform.googleapis.com/v1beta1/projects/<PROJECT>/locations/europe-west2/endpoints/openapi"
   export MEDGEMMA_MODEL="google/medgemma-27b-text-it"
   bash scripts/query-council.sh --providers=medgemma -- "clinical question"
   ```
   The OAuth token is short-lived; the provider re-mints it on each run.

## Verify

- `bash scripts/providers/medgemma.sh "Summarise the WHO definition of sepsis."`
  prints the model's answer, or a clear error naming the missing setting.
- It will **not** appear in `bash scripts/check-status.sh` or default queries —
  that is by design (opt-in). Confirm it runs only via `--providers=medgemma`.

## References

- MedGemma model card: https://developers.google.com/health-ai-developer-foundations/medgemma/model-card
- MedGemma on Hugging Face: https://huggingface.co/google/medgemma-1.5-4b-it
- MedSigLIP model card (encoder; not a council member): https://developers.google.com/health-ai-developer-foundations/medsiglip/model-card
