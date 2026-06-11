<!-- global-workspace-instructions:start -->

## Global workspace instructions

Also read and follow `C:\Users\hgeec\github\CLAUDE.md` and `C:\Users\hgeec\github\AGENTS.md` before working in this repository. These repo-local instructions remain in force. If a repo-local instruction conflicts with global files, prefer the more specific repo-local instruction unless a system, developer, or user instruction says otherwise.

<!-- global-workspace-instructions:end -->

@AGENTS.md

# Claude notes

Use `AGENTS.md` as the canonical instruction source for this repository.

- This is a vendored third-party Claude Code plugin. See `README.md` for the full feature set and `docs/ARCHITECTURE.md` for the data flow.
- The plugin ships its own author-facing skills under `skills/` (council-execution, deep-execution, provider-integration). They are part of the plugin and are separate from the workspace skills Claude Code loads from `~/.claude/skills`.
- After changing provider scripts, verify with `bash scripts/check-status.sh` and a scoped query such as `bash scripts/query-council.sh --providers=openai -- "ping"`.
