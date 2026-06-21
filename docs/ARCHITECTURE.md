# Architecture

## System Overview

```
                           USER REQUEST
                                |
                                v
                    +------------------------+
                    |   /claude-council:ask  |
                    |     (commands/ask.md)  |
                    +------------------------+
                                |
                                v
+------------------------------------------------------------------------+
|                        query-council.sh                                 |
|------------------------------------------------------------------------|
|  1. Parse Arguments (--providers, --roles, --debate, --file, etc.)     |
|  2. Discover Available Providers (API key OR CLI binary on PATH)       |
|  3. Apply CLI-prefers-API policy (codex shadows openai, etc.)          |
|  4. Resolve Roles (expand presets, assign to providers)                |
|  5. Build Context (--file content, auto-context detection)             |
+------------------------------------------------------------------------+
                                |
                                v
                    +------------------------+
                    |     ROUND 1: Query     |
                    +------------------------+
                                |
        +-------+-------+-------+-------+-------+-------+
        |       |       |       |       |       |       |
        v       v       v       v       v       v       v
   +--------+ +-----+ +------+ +-----+ +------+ +-----------+
   | gemini | |open | | grok | |perp | |codex | | gemini-cli|
   |  .sh   | | .sh | |  .sh | |.sh  | |  .sh | |    .sh    |
   +--------+ +-----+ +------+ +-----+ +------+ +-----------+
   (API)      (API)   (API)    (API)   (CLI)    (CLI)
        |               |               |               |
        |    +----------+----------+----------+        |
        +--->|      lib/cache.sh   |<---------+--------+
             | (check/store cache) |
             +---------------------+
                      |
        +-------------+-------------+
        |             |             |
        v             v             v
   [CACHE HIT]   [CACHE MISS]   [ERROR]
        |             |             |
        |             v             |
        |      +-------------+      |
        |      | lib/retry.sh|      |
        |      | (exp backoff|      |
        |      |  429/5xx)   |      |
        |      +-------------+      |
        |             |             |
        +------+------+------+------+
               |
               v
    +---------------------+
    | Collect R1 Results  |
    | {provider: {status, |
    |   response, cached, |
    |   role, model}}     |
    +---------------------+
               |
               +------ [if --debate] ------+
               |                           |
               v                           v
    +-------------------+       +------------------------+
    | Output R1 Results |       |   ROUND 2: Rebuttals   |
    +-------------------+       +------------------------+
                                           |
                        +------------------+------------------+
                        |                  |                  |
                        v                  v                  v
                  +-----------+      +-----------+      +-----------+
                  | Provider A|      | Provider B|      | Provider C|
                  | sees B,C  |      | sees A,C  |      | sees A,B  |
                  | responses |      | responses |      | responses |
                  +-----------+      +-----------+      +-----------+
                        |                  |                  |
                        +--------+---------+--------+---------+
                                 |
                                 v
                      +---------------------+
                      | Collect R2 Results  |
                      +---------------------+
                                 |
               +-----------------+
               |
               v
    +---------------------+
    |   Build JSON Output |
    |---------------------|
    | {                   |
    |   metadata: {...},  |
    |   round1: {...},    |
    |   round2: {...}     |  <-- only if debate
    | }                   |
    +---------------------+
               |
               v
    +---------------------+
    | format-output.sh    |
    | (terminal display)  |
    +---------------------+
               |
               v
    +---------------------+
    | lib/export.sh       |  <-- if --output
    | (markdown file)     |
    +---------------------+
```

## Component Details

### Provider Scripts (`scripts/providers/*.sh`)

Each provider follows a consistent interface:

```
INPUT:  $1 = prompt (with role prefix if assigned)
OUTPUT: stdout = AI response text
EXIT:   0 = success, non-zero = failure (error to stderr)
```

Three flavors share the interface:

- **API providers** (`gemini`, `openai`, `grok`, `perplexity`) — gated on
  `{PROVIDER}_API_KEY`, talk to vendor APIs over HTTPS, charge per call.
- **CLI providers** (`codex`, `gemini-cli`) — gated on the binary being on
  `PATH`, use the user's existing CLI subscription auth, no per-call cost.
  When both an API and CLI sibling exist (codex+openai, gemini-cli+gemini),
  the orchestrator prefers the CLI by default; explicit `--providers` wins
  over the policy.
- **Local/cloud providers** (`ollama`, `ollama-gemma4`, `ollama-kimi`) - gated on
  `OLLAMA_API_KEY`, the
  `ollama` binary, or `OLLAMA_BASE_URL`, talk to direct Ollama Cloud or a local
  or remote Ollama-compatible endpoint. On Windows-hosted shells, the Ollama
  provider can read `OLLAMA_API_KEY` and `OLLAMA_PUBKEY` from Windows
  process/user/machine environment scopes when Bash did not inherit them.

Environment-based configuration:
- `{PROVIDER}_API_KEY` - Required authentication for API providers
- `{PROVIDER}_MODEL` - Model override (also applies to CLI/local providers via
  `CODEX_MODEL`, `GEMINI_CLI_MODEL`, and `OLLAMA_MODEL`)
- `COUNCIL_MAX_TOKENS` - Response length limit for API providers and Ollama
- `COUNCIL_DEBUG` - Enable verbose logging

### Cache Layer (`scripts/lib/cache.sh`)

```
Cache Key = SHA256("provider:model:prompt")

cache_get(key) -> response | empty
cache_set(key, provider, model, prompt, response)
cache_clear()

Storage: $COUNCIL_CACHE_DIR/{key}.json
TTL: $COUNCIL_CACHE_TTL seconds (default 3600)
```

### Retry Logic (`scripts/lib/retry.sh`)

```
curl_with_retry():
  - Retries on: 429 (rate limit), 5xx (server error)
  - Fails fast on: timeout, other 4xx (client error)
  - Backoff: exponential (1s, 2s, 4s...)
  - Max retries: $COUNCIL_MAX_RETRIES (default 3)
```

### Role System (`scripts/lib/roles.sh`)

```
config/roles.json defines:
  - Individual roles (security, performance, etc.)
  - Role presets (balanced, security-focused, etc.)

Role injection prepends instructions to prompt:
  "As a [ROLE], focus on [CONCERNS]..."
```

## Data Flow

### Standard Query

```
User -> parse args -> discover providers -> check cache
                                               |
                    +-----------+--------------+
                    |           |
               [HIT]         [MISS]
                 |              |
                 |         query provider -> store cache
                 |              |
                 +------+-------+
                        |
                    format output -> display
```

### Debate Mode

```
User -> Round 1 (parallel queries)
             |
        collect responses
             |
        Round 2 (each sees others' R1)
             |
        collect rebuttals
             |
        combined output with debate insights
```

### Agent-Enhanced Mode (--agents)

```
User -> ask.md detects --agents flag (or NL trigger)
             |
        spawn N parallel Claude subagents (background)
             |
    +--------+--------+--------+--------+
    |        |        |        |        |
    v        v        v        v        v
 Agent:   Agent:   Agent:   Agent:   ...
 Gemini   OpenAI   Grok     Perplexity
    |        |        |        |
    | Each agent independently:
    | 1. Runs provider script
    | 2. Evaluates response quality
    | 3. Retries with reformulated prompt if poor
    | 4. Asks follow-up questions for depth
    | 5. Returns structured analysis:
    |    - Key recommendations
    |    - Confidence level
    |    - Unique perspective
    |    - Blind spots
    |        |        |        |
    +--------+--------+--------+
             |
        orchestrator collects all analyses
             |
        enhanced synthesis:
        - confidence-weighted consensus
        - cross-provider blind spot analysis
        - divergence with context
             |
        save to council-cache
```

Key difference from standard mode: subagents do meaningful analytical
work beyond the API call, pre-digesting each response before synthesis.

## File Structure

```
claude-council/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── agents/
│   └── council-advisor.md       # Proactive suggestions
├── commands/
│   ├── ask.md                   # Main /ask command
│   └── status.md                # /status command
├── config/
│   └── roles.json               # Role definitions
├── docs/
│   └── ARCHITECTURE.md          # This file
├── scripts/
│   ├── query-council.sh         # Main orchestrator
│   ├── run-council.sh           # Query + format pipeline
│   ├── format-output.sh         # Terminal formatter
│   ├── check-status.sh          # Provider health check
│   ├── release.sh               # Version bump and tagging
│   ├── dev/
│   │   └── demo-pane.sh         # Visual test harness for the streaming pane
│   ├── providers/
│   │   ├── gemini.sh            # API
│   │   ├── openai.sh            # API
│   │   ├── grok.sh              # API
│   │   ├── perplexity.sh        # API
│   │   ├── codex.sh             # CLI (subscription auth, shadows openai)
│   │   ├── gemini-cli.sh        # CLI (subscription auth, shadows gemini)
│   │   ├── ollama.sh            # Local/remote Ollama HTTP provider (GLM-5.2)
│   │   ├── ollama-gemma4.sh     # Ollama Cloud Gemma 4 member (gemma4:31b)
│   │   ├── ollama-kimi.sh       # Ollama Cloud Kimi K2.7 Code member (kimi-k2.7-code)
│   │   └── medgemma.sh          # Opt-in medical member (OpenAI-compatible cloud endpoint)
│   └── lib/
│       ├── cache.sh             # Caching utilities
│       ├── display.sh           # Streaming tmux pane + iTerm2 lifecycle
│       ├── export.sh            # Markdown export
│       ├── keys.sh              # API key resolution (XAI_API_KEY ↔ GROK_API_KEY)
│       ├── providers.sh         # Discovery + CLI-prefers-API policy + vendor display
│       ├── retry.sh             # Retry with backoff
│       ├── roles.sh             # Role management
│       ├── tokens.sh            # Reasoning-model token-cap bumping
│       └── verbosity.sh         # Response verbosity directives
├── skills/
│   ├── council-execution/
│   │   └── SKILL.md             # Standard query execution
│   ├── deep-execution/
│   │   ├── SKILL.md             # Agent-enhanced execution (--agents)
│   │   └── agent-prompt-template.md  # Subagent prompt template
│   └── provider-integration/
│       ├── SKILL.md             # Adding providers guide
│       └── api-patterns.md      # API integration patterns
├── tests/
│   ├── run_tests.sh             # Test runner
│   ├── test_helper.bash         # Shared test utilities
│   ├── cache.bats
│   ├── cli-providers.bats       # CLI/local providers (codex, gemini-cli, ollama)
│   ├── display.bats
│   ├── keys.bats
│   ├── roles.bats
│   ├── tokens.bats
│   ├── verbosity.bats
│   └── query-council.bats
├── LICENSE
├── README.md
└── TESTING.md
```

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `GEMINI_API_KEY` | - | Google AI Studio key |
| `OPENAI_API_KEY` | - | OpenAI API key |
| `XAI_API_KEY` | - | xAI API key (preferred) |
| `GROK_API_KEY` | - | xAI API key (legacy alias; `XAI_API_KEY` wins if both set) |
| `PERPLEXITY_API_KEY` | - | Perplexity API key |
| `{PROVIDER}_MODEL` | varies | Model override (API providers) |
| `CODEX_MODEL` | gpt-5.5 | Model passed to `codex exec -m` |
| `GEMINI_CLI_MODEL` | gemini-3-flash-preview | Model passed to `gemini -m` |
| `OLLAMA_MODEL` | glm-5.2 / glm-5.2:cloud | Model passed to Ollama `/api/chat` (ollama member) |
| `OLLAMA_GEMMA4_MODEL` | gemma4:31b | Model for the `ollama-gemma4` member |
| `OLLAMA_KIMI_MODEL` | kimi-k2.7-code | Model for the `ollama-kimi` member |
| `OLLAMA_BASE_URL` | https://ollama.com with `OLLAMA_API_KEY`; otherwise http://127.0.0.1:11434 | Ollama-compatible endpoint |
| `MEDGEMMA_BASE_URL` | - | OpenAI-compatible endpoint for the opt-in `medgemma` member (see `docs/MEDGEMMA.md`) |
| `MEDGEMMA_AUTH` | bearer | `bearer` (static token / HF_TOKEN fallback) or `gcloud` (Vertex AI OAuth) |
| `MEDGEMMA_API_KEY` | - | Bearer token for the MedGemma endpoint (falls back to `HF_TOKEN`) |
| `MEDGEMMA_MODEL` | medgemma-27b-text-it | Model id for the `medgemma` member |
| `OLLAMA_PUBKEY` | - | Optional Ollama public key loaded from Windows env for account parity; not sent as API auth |
| `COUNCIL_MAX_TOKENS` | 2048 | Max response tokens |
| `COUNCIL_MAX_RETRIES` | 3 | Retry attempts |
| `COUNCIL_RETRY_DELAY` | 1 | Initial retry delay (s) |
| `COUNCIL_TIMEOUT` | 300 | Request timeout (s) |
| `COUNCIL_CACHE_DIR` | .claude/council-cache | Cache location |
| `COUNCIL_CACHE_TTL` | 3600 | Cache lifetime (s) |
| `COUNCIL_DEBUG` | - | Enable debug output |
| `COUNCIL_NO_PANE` | - | Set to `1` to disable the streaming tmux pane globally |
| `COUNCIL_AUTO_CLOSE` | - | Set to `1` to auto-close the pane on completion (skip the keypress wait); used by tests/demos |
| `COUNCIL_ATTENTION_THRESHOLD` | 2000 | iTerm2 dock-bounce threshold in ms (only triggers if total elapsed >= this) |
| `COUNCIL_VERBOSITY` | standard | Response style: `brief` / `standard` / `detailed` (prepended to all providers' system prompts) |
| `OPENAI_REASONING_EFFORT` | medium | Reasoning model effort |
| `PERPLEXITY_RECENCY` | - | Search recency filter |
