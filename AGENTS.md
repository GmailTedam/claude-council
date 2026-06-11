<!-- global-workspace-instructions:start -->

## Global workspace instructions

Also read and follow `C:\Users\hgeec\github\AGENTS.md` before working in this repository. These repo-local instructions remain in force. If a repo-local instruction conflicts with the global file, prefer the more specific repo-local instruction unless a system, developer, or user instruction says otherwise.

<!-- global-workspace-instructions:end -->

# Agent instructions

`claude-council` is a vendored third-party Claude Code plugin (upstream: https://github.com/hex/claude-council). It queries several AI providers in parallel and shows their answers side by side. The contract for the wider workspace lives in the global files referenced above; this file records only what is specific to this clone.

## What this repo is

- A Claude Code plugin. `commands/` holds the `/claude-council:ask` and `/claude-council:status` slash commands, `agents/council-advisor.md` is the proactive advisor agent, `skills/` holds the plugin's own author-facing skills, and `scripts/` holds the bash that calls each provider.
- Manifest: `.claude-plugin/plugin.json`.
- Runtime requirements: `curl` and `jq` on `PATH`, plus at least one configured provider (an API key such as `OPENAI_API_KEY`, or an installed `codex` / `gemini` CLI).

## Local registration

This is a single-plugin repo that also acts as its own marketplace through `.claude-plugin/marketplace.json` (`source: "."`). In a normal Claude Code session, register it with:

    /plugin marketplace add C:\Users\hgeec\github\claude-council
    /plugin install claude-council@claude-council

The `/plugin` command is not available in some non-interactive environments (for example the Agent SDK); register from a normal Claude Code session.

## Vendored-repo discipline

- Upstream is read-only for this workspace's GitHub account. Send genuine bug fixes upstream as a pull request from a fork, and keep each fix in a self-contained commit so it cherry-picks cleanly.
- These files are workspace-local and should not be pushed upstream: `AGENTS.md`, `CLAUDE.md`, and `.claude-plugin/marketplace.json`.
- Keep other local changes minimal so `/plugin update` stays clean.
