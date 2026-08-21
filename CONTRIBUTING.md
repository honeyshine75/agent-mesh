# Contributing to agent-mesh

Thanks for considering a contribution! agent-mesh is intentionally small (~100 lines of bash) — the goal is to stay small and focused. This guide gets you from clone to PR.

## Project philosophy

- **Stay small.** Two skills, one job: let agents discover and message each other. Resist adding features that grow the surface (structured RPC, cross-machine, a daemon). If you want those, they belong in a *separate* project — open an issue first to discuss scope.
- **Keep it portable.** No hardcoded paths, no language runtime, no config server. Anything that needs a specific machine's layout breaks the "clone and run" promise.
- **Be honest in the docs.** The limitations section exists on purpose — tmux/Linux dependence, paste-timing hacks. Don't paper over them; if you lift a limitation, update the docs.

## Development setup

```bash
git clone https://github.com/<your-username>/agent-mesh.git
cd agent-mesh
bash install.sh        # symlinks skills/ into ~/.claude/skills/
```

You need `tmux` and Linux (see [GETTING_STARTED.md](GETTING_STARTED.md) for the full dependency list). No build step, no dependencies to install.

## Verifying your changes

There's no test suite — verification is a quick manual checklist:

1. **Syntax** — `bash -n` every script you touched:
   ```bash
   bash -n skills/list-agents/list-agents.sh
   bash -n skills/send-agent/send-agent.sh
   bash -n install.sh
   ```
2. **Lint (recommended)** — install [`shellcheck`](https://www.shellcheck.net/) and run it on the scripts. Fix anything new you introduced (existing benign `SC2086` warnings on intended word-splitting of pid lists are acceptable — leave a comment if you keep one).
3. **Smoke test** — launch two agents in tmux and exercise the full loop:
   ```bash
   tmux new-session -d -s alice 'claude'
   tmux new-session -d -s bob   'codex'     # or whatever agent you're testing detection for
   tmux attach -t alice
   # then:
   bash ~/.claude/skills/list-agents/list-agents.sh          # both sessions show correct [type]
   bash ~/.claude/skills/send-agent/send-agent.sh bob "ping"
   # bob receives the prefixed message and can reply via the hint
   ```
4. **No secrets, no internal references.** Before committing, confirm no machine-specific paths, hostnames, usernames, or internal project codenames leaked in. A useful sweep:
   ```bash
   # catches absolute paths into a specific machine's mounts/homes, bare host:port, and obvious internal markers
   grep -rinE '/mnt/|/home/[^/]+/\.|:[0-9]{4,5}\b|yourcompany|internalhost' . --exclude-dir=.git
   # add any internal codename of your own to the pattern; expect: zero hits
   ```

## Where to make common changes

- **Add a new agent type** (e.g. a new CLI): edit `detect_agent()` in `skills/list-agents/list-agents.sh`. Read `/proc/<pid>/cmdline` of the new CLI, find a stable pattern, add a `grep` case *before* the generic fallback. Document the launch pattern it expects in `GETTING_STARTED.md` §4.
- **macOS support**: `detect_agent` reads `/proc/<pid>/cmdline` — Linux-only. The macOS path is to derive cmdline from `ps`/`lsof`. This is the most-wanted port; if you take it on, keep the Linux path intact and branch on `uname`.
- **Tune paste/Enter timing** (if a CLI update breaks delivery): the sleeps and follow-up Enter logic in `send-agent.sh` are tuned against codex PasteBurst (~120ms suppression) + claude ink paste digestion. Read the header comment — it explains *why* each sleep exists — then adjust.
- **Docs**: README.md (English, primary), README.zh-CN.md (Chinese, mirror structure), GETTING_STARTED.md (deployment). Keep all three in sync. The two READMEs must stay structurally parallel.

## Contribution flow

1. **Fork** the repo on GitHub (upper-right Fork button).
2. **Clone your fork** and add upstream:
   ```bash
   git clone https://github.com/<your-username>/agent-mesh.git
   cd agent-mesh
   git remote add upstream https://github.com/honeyshine75/agent-mesh.git
   ```
3. **Branch** off `main`:
   ```bash
   git checkout -b feat/add-aide-agent-detection
   ```
4. **Commit** with a clear message. Conventional-commits style (`feat:`, `fix:`, `docs:`) is appreciated but not enforced; the subject may be in English or Chinese.
5. **Push** to your fork and **open a PR** against `main`:
   ```bash
   git push -u origin feat/add-aide-agent-detection
   ```
   In the PR description, note what changed and how you verified it (the checklist above).

## Scope: open an issue first for

- New top-level tools (beyond `list-agents` / `send-agent`).
- Structured/RPC messaging, cross-machine delivery, a background daemon.
- Anything that adds a runtime dependency.

Small fixes (bugs, doc sync, new agent-type patterns, macOS port) can go straight to PR.

## Code of conduct

Be kind and constructive. Disagreements about scope go in issues, not in review threads. We keep this small on purpose — "not in scope" is not a rejection of you, it's a rejection of the scope.

## License

By contributing, you agree your contributions are licensed under the [MIT license](LICENSE).
