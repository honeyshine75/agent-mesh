<div align="center">

# agent-mesh

**让你的 AI coding agent 互相说话。**

在 tmux 里同时跑 [claude code](https://docs.anthropic.com/en/docs/claude-code) 和 [codex](https://github.com/openai/codex),它们互相发现、直接互发消息 —— 不再靠你在两个终端间复制粘贴来传任务和结果。

[English](README.md) · [中文](README.zh-CN.md)

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Platform: Linux](https://img.shields.io/badge/platform-Linux-blue)
![Shell: Bash](https://img.shields.io/badge/shell-bash-4black)

</div>

---

## 痛点

你同时开了两个 AI coding agent —— 比如 `claude` 做架构和审查,`codex` 跑测试和实现。你想让它们**协作**:claude 派活给 codex,codex 跑完报回结果。但现实是你得当"传话筒"——读一个终端、复制粘贴到另一个,反复横跳。又慢又容易错,还打断你的节奏。

**agent-mesh 解决这个。** 两个极小的 shell skill 让 agent 们互相发现、直接发文本消息,走 tmux。

## 演示

```
$ bash list-agents.sh
当前 session: [claude] alice
其他 agent session:
  [codex] bob

$ bash send-agent.sh bob "把 tests/test_foo.py 跑了,失败用例贴回来"
已发送给 bob (claude→): 把 tests/test_foo.py 跑了...

# → bob 的输入框收到:
# [📨 来自 claude:alice] 把 tests/test_foo.py 跑了,失败用例贴回来 | 回复: send-agent alice <你的回复>

# bob 处理完,用前缀里的回复提示发回:
$ bash send-agent.sh alice "3 个失败:test_bar/test_baz/test_qux"
```

这就是完整闭环。无服务、无 daemon、无端口 —— 只要 tmux + `/proc`。

## 特性

- **`list-agents`** —— 列出本机所有 tmux session,标注每个跑的 agent 类型(`claude` / `codex` / `shell`)。靠遍历进程树 + 模式匹配 `/proc/<pid>/cmdline` 实现。
- **`send-agent`** —— 给另一个 agent 的 tmux pane 注入一条消息。消息带来源前缀(谁发的、来自哪个 session)**外加回复提示**,接收方照着提示就知道怎么回。
- **搞定 codex PasteBurst。** `send-keys -l` 会被 codex 的 paste-burst 逻辑吞掉(尾部 Enter 被当换行 → 消息卡输入框)。`send-agent` 改用 `tmux load-buffer` + `paste-buffer` 走显式粘贴路径,再按节奏送 Enter 躲过抑制窗口。
- **零运行时依赖。** ~100 行 bash,仅需 `tmux` + Linux `/proc`。无语言运行时、无配置服务、无消息中间件。

## 快速上手

```bash
git clone https://github.com/honeyshine75/agent-mesh.git
cd agent-mesh
bash install.sh          # 把 skills 软链到 ~/.claude/skills/

# 在命名的 tmux session 里各起一个 agent
tmux new-session -d -s alice 'claude'
tmux new-session -d -s bob   'codex'        # 或:codex resume <id>
tmux attach -t alice

# 在 alice 里:
bash ~/.claude/skills/list-agents/list-agents.sh
bash ~/.claude/skills/send-agent/send-agent.sh bob "hello from the other side"
```

## 原理

**发现(`list-agents`)** —— `tmux list-sessions` → 每个 session 的 `pane_pid` → BFS 进程树(`ps -eo pid,ppid`)→ 读每个后代的 `/proc/<pid>/cmdline` → 模式匹配认 agent 类型。

**投递(`send-agent`)** —— `tmux load-buffer` + `paste-buffer -d`(显式粘贴,绕开 codex paste-burst 的 Enter 抑制)→ 按节奏 `send-keys Enter`,并用 `capture-pane` 反馈检查:只有没看到工作指示符时才补一个 Enter。

完整部署说明见 [`GETTING_STARTED.md`](GETTING_STARTED.md)。

## 跨机(可选)

默认纯本地。可选开启**跨机**:本机找不到的 peer,`send-agent` 经 [agent-community](https://github.com/honeyshine75/agent-community) 的 DM API 远程投递;对端跑 `inbox-watch` 轮询收件箱,把收到的 DM 注入其本地 tmux session。本地 paste 注入 + 在线 DM = 跨机器的 agent 通信 —— 单边都做不到(本地不能跨机,DM 不能注入正在跑的 agent 进程)。

需 `jq` + `curl` + agent-community 账号;`bind-agent.sh <session> <agent_id> <api_key>` 绑定身份。详见 GETTING_STARTED.md "跨机" 节。

## 要求与限制

- **tmux 是硬依赖。** agent 必须跑在 tmux session 里 —— 发现和投递都走 tmux。没 tmux,就没 mesh。
- **v1 仅 Linux。** agent 检测读 `/proc/<pid>/cmdline`。macOS 需改用 `ps`/`lsof` 适配(未做 —— 欢迎 PR)。
- **本地投递:同机、同一 tmux server。** 跨机**可选** —— 经 [agent-community](https://github.com/honeyshine75/agent-community) DM 中继(见 GETTING_STARTED.md)。
- **消息是纯文本粘贴,非结构化 RPC。** 接收方把它当一条用户输入处理,自己决定回不回、怎么回。回复通道是接收方调 `send-agent` 发回来(每条消息都附回复提示)。
- **检测假设按 GETTING_STARTED 的方式启动 agent。** 若启动姿势不同(如套了 wrapper 改了 cmdline),`detect_agent` 可能判成 `shell` —— 调 `list-agents.sh` 里的 case 模式即可。
- **本质是 hack,接受它。** 若任一 CLI 改了输入处理(codex PasteBurst 时序、claude ink paste 消化),`send-agent` 的 Enter 节奏可能要重调。脚本头部注释说明了每个 sleep 存在的*原因*,重调不费劲。

## 文档

- [**GETTING_STARTED.md**](GETTING_STARTED.md) —— 完整部署说明(硬依赖、安装、怎么启动 agent 让检测命中、排障)。
- [skills/list-agents/SKILL.md](skills/list-agents/SKILL.md)
- [skills/send-agent/SKILL.md](skills/send-agent/SKILL.md)
- [skills/inbox-watch/SKILL.md](skills/inbox-watch/SKILL.md) —— 跨机接收守护

## 贡献

欢迎贡献 —— fork、clone、提 PR。这是个聚焦的小工具,我们有意保持小:Bug 修复、macOS 支持、新的 agent 类型检测模式可直接提 PR;更大的改动(结构化 RPC)请先开 issue。fork→分支→测试→PR 流程和常见改动位置见 [**CONTRIBUTING.md**](CONTRIBUTING.md)。

## 许可证

[MIT](LICENSE)
