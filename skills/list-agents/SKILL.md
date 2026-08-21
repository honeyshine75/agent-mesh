---
name: list-agents
description: 列出同机所有 tmux session 里跑的 agent(claude code / codex),标注每个的类型,供跨 agent 协作时发现 peer。
allowed-tools: Bash(bash ~/.claude/skills/list-agents/list-agents.sh:*)
---

# list-agents

列出同机/同容器里其他 tmux session 中的 agent,标注类型(claude / codex / shell)。

## 用法

```bash
bash ~/.claude/skills/list-agents/list-agents.sh
```

输出形如:

```
当前 session: [claude] alice
其他 agent session:
  [codex] bob
  [shell] scratch
```

## 何时用

- 需要给另一个 agent 派活、请教、对拍时,先用本工具确认有哪些 peer、它们叫什么名字(tmux session 名)、各自是什么 agent。
- 拿到 peer 名字后,用 `send-agent` 给它发消息。

## 原理

见仓库根 `GETTING_STARTED.md` 的"原理"一节。简言之:tmux session 的 pane_pid → 进程树 → `/proc/<pid>/cmdline` 模式匹配 → agent 类型。
