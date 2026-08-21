<div align="center">

# agent-mesh

**Let your AI coding agents talk to each other.**

Run [claude code](https://docs.anthropic.com/en/docs/claude-code) and [codex](https://github.com/openai/codex) side by side in tmux. They discover each other and exchange messages directly — no more copy-pasting between terminals to relay tasks and results.

[English](README.md) · [中文](README.zh-CN.md)

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Platform: Linux](https://img.shields.io/badge/platform-Linux-blue)
![Shell: Bash](https://img.shields.io/badge/shell-bash-4black)

</div>

---

## The problem

You've got two AI coding agents open — say, a `claude` doing architecture and review, and a `codex` running tests and implementation. You want them to **collaborate**: claude hands codex a task, codex runs it, reports back. But today that means *you* becoming the messenger — reading one terminal, copy-pasting into the other, over and over. Slow, error-prone, and it breaks your flow.

**agent-mesh fixes this.** Two tiny shell skills let the agents find each other and send text messages directly, through tmux.

## Demo

```
$ bash list-agents.sh
当前 session: [claude] alice
其他 agent session:
  [codex] bob

$ bash send-agent.sh bob "把 tests/test_foo.py 跑了,失败用例贴回来"
已发送给 bob (claude→): 把 tests/test_foo.py 跑了...

# → bob's input box receives:
# [📨 来自 claude:alice] 把 tests/test_foo.py 跑了,失败用例贴回来 | 回复: send-agent alice <你的回复>

# bob processes it, then replies using the hint in the prefix:
$ bash send-agent.sh alice "3 个失败:test_bar/test_baz/test_qux"
```

That's the whole loop. No server, no daemon, no port — just tmux + `/proc`.

## Features

- **`list-agents`** — lists every tmux session on the machine and tags each with its agent type (`claude` / `codex` / `shell`), by walking the process tree and pattern-matching `/proc/<pid>/cmdline`.
- **`send-agent`** — injects a message into another agent's tmux pane. The message carries a source prefix (who sent it, from which session) **and a reply hint**, so the receiver knows exactly how to answer.
- **Codex PasteBurst, handled.** `send-keys -l` gets eaten by codex's paste-burst logic (the trailing Enter is swallowed as a newline → message stuck in the input box). `send-agent` uses `tmux load-buffer` + `paste-buffer` to take the explicit-paste path, then paces Enter delivery to dodge the suppression window.
- **Zero runtime deps.** ~100 lines of bash. Needs only `tmux` and a Linux `/proc`. No language runtime, no config server, no broker.

## Quick start

```bash
git clone https://github.com/honeyshine75/agent-mesh.git
cd agent-mesh
bash install.sh          # symlinks skills into ~/.claude/skills/

# launch two agents in named tmux sessions
tmux new-session -d -s alice 'claude'
tmux new-session -d -s bob   'codex'        # or: codex resume <id>
tmux attach -t alice

# inside alice:
bash ~/.claude/skills/list-agents/list-agents.sh
bash ~/.claude/skills/send-agent/send-agent.sh bob "hello from the other side"
```

## How it works

**Discovery (`list-agents`)** — `tmux list-sessions` → each session's `pane_pid` → BFS the process tree (`ps -eo pid,ppid`) → read each descendant's `/proc/<pid>/cmdline` → pattern-match the agent type.

**Delivery (`send-agent`)** — `tmux load-buffer` + `paste-buffer -d` (explicit paste, bypasses codex paste-burst Enter suppression) → paced `send-keys Enter` with a `capture-pane` feedback check that sends a follow-up Enter only if no work indicator is detected.

See [`GETTING_STARTED.md`](GETTING_STARTED.md) for the full deployment guide.

## Requirements & limitations

- **tmux is a hard dependency.** Agents must run inside tmux sessions — discovery and delivery both go through tmux. No tmux, no mesh.
- **Linux-only (v1).** Agent detection reads `/proc/<pid>/cmdline`. macOS would need a `ps`/`lsof` adaptation (not done yet — PRs welcome).
- **All agents on one machine, one tmux server.** Cross-machine needs tmux tunneling (out of scope).
- **Messages are plain-text paste, not structured RPC.** The receiver treats it as a user input; it decides whether/how to reply. The reply channel is the receiver calling `send-agent` back (hint included in every message).
- **Detection assumes the launch patterns in GETTING_STARTED.** If you start agents differently (e.g. a wrapper that rewrites the cmdline), `detect_agent` may tag it as `shell` — adjust the case patterns in `list-agents.sh`.
- **It's a hack, by design.** If either CLI changes its input handling (codex's PasteBurst timing, claude's ink paste handling), the Enter pacing in `send-agent` may need retuning. The script headers explain *why* each sleep exists, so retuning is straightforward.

## Documentation

- [**GETTING_STARTED.md**](GETTING_STARTED.md) — full deployment guide (hard deps, install, how to launch agents so detection hits, troubleshooting).
- [skills/list-agents/SKILL.md](skills/list-agents/SKILL.md)
- [skills/send-agent/SKILL.md](skills/send-agent/SKILL.md)

## Contributing

Contributions welcome — fork, clone, and PR. This is a small, focused tool and we intend to keep it small: bug fixes, macOS support, and new agent-type detection patterns go straight to PR; anything larger (structured RPC, cross-machine) — open an issue first. See [**CONTRIBUTING.md**](CONTRIBUTING.md) for the fork→branch→test→PR flow and where to make common changes.

## License

[MIT](LICENSE)
