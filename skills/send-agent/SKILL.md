---
name: send-agent
description: 给另一个 tmux session 中的 agent(claude code / codex)发文本消息,带来源前缀和回复方式提示,绕开 codex PasteBurst 的 Enter 抑制。
allowed-tools: Bash(bash ~/.claude/skills/send-agent/send-agent.sh:*)
---

# send-agent

给另一个 tmux session 里的 agent 发一条文本消息。消息会带前缀标明来源 agent + 自己的 session 名,并附回复方式,方便对方照着回。

## 用法

```bash
bash ~/.claude/skills/send-agent/send-agent.sh <peer_session_name> "<message>"
```

例如自己在 session `alice`,要给 `bob` 发消息:

```bash
bash ~/.claude/skills/send-agent/send-agent.sh bob "看看 core/slam_replay.py 的 metrics 键是不是和 acceptance 对得上,review 完回复我"
```

bob 的输入框会出现:

```
[📨 来自 claude:alice] 看看 core/slam_replay.py ... | 回复: send-agent alice <你的回复>
```

bob 处理完后,用前缀里的回复提示 `send-agent alice "<回复内容>"` 把结果发回来。

## 先 list-agents

不知道 peer 叫什么时,先跑 `list-agents` 拿到名字和类型。

## 原理

见仓库根 `GETTING_STARTED.md` 的"原理"一节。简言之:`tmux load-buffer` + `paste-buffer -d` 显式粘贴(而非 `send-keys -l`),绕开 codex PasteBurst 120ms 的 Enter 抑制;再补 Enter + capture-pane 检查处理态做容错。
