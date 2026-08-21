# 通用部署说明(GETTING_STARTED)

在干净的 Linux 机器/容器里,从零部署 agent-mesh —— 让多个 CLI coding agent(claude code、codex)在各自 tmux session 里跑,互相发现、互发消息。

---

## 1. 这是什么

agent-mesh 让同机多个 AI coding agent 协同:一个 agent 用 `send-agent` 给另一个 agent 注入一条文本消息,对方处理完按消息里的回复提示把结果发回来。典型场景:claude code 做主架构/审查,codex 跑测试/实现,两者用 `send-agent` 互传任务和结果,无需人工在终端间复制粘贴。

两个工具:

- `list-agents` —— 列出本机所有 tmux session,标注每个跑的 agent 类型(claude / codex / shell)。
- `send-agent` —— 给指定 peer session 发带来源前缀 + 回复方式的消息。

## 2. 硬依赖(置顶,先确认)

> 这套机制是 hack:它靠 tmux 的 session 发现 + paste-buffer 注入,不靠端口或约定文件。所以前提条件必须满足,否则断。

- **tmux** —— agent **必须**启动在 tmux session 里。`list-agents` 靠 `tmux list-sessions` 发现 peer;`send-agent` 靠 `tmux paste-buffer` 投递。不把 agent 跑在 tmux 里,整套机制用不起来。**只有在 tmux 里启动的 agent 才能互相发现。**
- **Linux** —— agent 类型检测读 `/proc/<pid>/cmdline` 模式匹配,这是 Linux 特有的。macOS v1 不支持(需改用 `ps`/`lsof` 适配,见"限制"节)。
- **claude code CLI + codex CLI** —— 已安装、已登录、可独立交互式运行。
- **同一 tmux server** —— 所有参与协作的 agent 在同一台机的同一个 tmux server(即同机;跨机需另做 tmux 隧道,不在本包范围)。

确认依赖:

```bash
command -v tmux        # 有 tmux
command -v claude      # 有 claude code
command -v codex       # 有 codex
uname                  # Linux
```

## 3. 安装

```bash
git clone https://github.com/honeyshine75/agent-mesh.git && cd agent-mesh
bash install.sh
```

`install.sh` 把 `skills/list-agents`、`skills/send-agent` 软链到 `~/.claude/skills/`。claude code 靠 `SKILL.md` 自动发现 skill(下次会话起 `list-agents` / `send-agent` 即可用)。

可选环境变量:

- `CLAUDE_SKILLS_DIR` —— 覆盖默认的 `~/.claude/skills`(自定义 skill 目录时用)。

codex 侧:codex **不读** `SKILL.md`,需在 codex 的指令文件(如 `~/.codex/AGENTS.md` 或等价 config)里写明调用方式:

```
列出其他 agent:  bash ~/.claude/skills/list-agents/list-agents.sh
给某 agent 发消息: bash ~/.claude/skills/send-agent/send-agent.sh <peer> "<你的消息>"
```

## 4. 启动 agent(关键 —— 决定检测能否命中)

> `list-agents` 的 `detect_agent` 靠 `/proc/<pid>/cmdline` 模式匹配认 agent 类型。按下面方式起,检测就能命中;换别的姿势(比如套一层 wrapper 改了 cmdline)可能漏判成 `shell`。

每个 agent 起在独立的、**命名**的 tmux session 里(detached 起或 attach 后起都行):

```bash
# claude code —— 直接交互式起(或加 --permission-mode auto / --resume <id>)
tmux new-session -d -s alice 'claude'

# codex —— 交互式起,或 resume 一个已有会话
tmux new-session -d -s bob   'codex'              # 交互式新会话
# 或: tmux new-session -d -s bob 'codex resume <session-id>'

# attach 到其中一个开干
tmux attach -t alice
```

**检测规则**(检测模式见 `skills/list-agents/list-agents.sh` 的 `detect_agent`):

- `claude` —— cmdline 二进制路径含 `claude-code`(npm 包 `@anthropic-ai/claude-code*`),或裸命令 `claude`。裸交互式启动(无 `--resume`)也命中。
- `codex` —— cmdline 二进制路径含 `/codex`,或裸命令 `codex`。
- `shell` —— 以上都不匹配(空壳,agent 没起来或启动方式不认)。

> 如果你的启动方式让 cmdline 不带上述特征(例如 agent 经 wrapper 改了二进制名、套了层壳),`detect_agent` 会判成 `shell`。这时可以:① 按上面方式调整启动;② 或改 `detect_agent` 里的 case 模式适配你的启动姿势(脚本顶部有注释说明在哪改)。

## 5. 用

在任一 agent 的 tmux session 里(假设你在 alice):

```bash
# 列出所有 agent
bash ~/.claude/skills/list-agents/list-agents.sh
# 当前 session: [claude] alice
# 其他 agent session:
#   [codex] bob
#   [shell] scratch

# 给 bob 发消息
bash ~/.claude/skills/send-agent/send-agent.sh bob "把 tests/test_foo.py 跑了,失败用例贴回来"
# 已发送给 bob (claude→): 把 tests/test_foo.py 跑了...
```

bob 的输入框出现:

```
[📨 来自 claude:alice] 把 tests/test_foo.py 跑了,失败用例贴回来 | 回复: send-agent alice <你的回复>
```

bob 处理后,用消息里的回复提示发回:

```bash
bash ~/.claude/skills/send-agent/send-agent.sh alice "3 个失败:test_bar/test_baz/test_qux,日志已贴在上面"
```

alice 收到带 `bob` 来源前缀的回复,闭环。

## 6. 原理(简述)

**发现(list-agents)**:

1. `tmux list-sessions` 拿到所有 session 名。
2. 每个 session 用 `tmux list-panes -t <name> -F '#{pane_pid}'` 拿到 pane 的 shell pid。
3. 从该 pid 出发,用 `ps -eo pid,ppid` + awk 做 BFS,收集整棵进程树的 pid。
4. 读每个后代的 `/proc/<pid>/cmdline`(null 分隔转空格),模式匹配认 agent 类型(见第 4 节规则)。
5. 首个命中的后代决定该 session 的类型。

**投递(send-agent)**:

1. `tmux has-session -t <peer>` 确认目标存在。
2. 用 `tmux display-message -p '#{session_name}'` 拿到自己的 session 名,拼成带来源 + 回复方式的前缀。
3. **关键**:`printf '%s' "$MSG" | tmux load-buffer -b <buf> -` 然后 `tmux paste-buffer -t <peer> -b <buf> -d` —— 走**显式 paste** 路径,而不是 `send-keys -l`。
   - 为什么:codex TUI 有 PasteBurst 机制,`send-keys -l` 的字符流会被当成 paste burst,其后约 120ms 内的 Enter 被当换行不提交 → 消息卡输入框。显式 `paste-buffer` 不进 burst 抑制。
4. `sleep 0.5` + `tmux send-keys Enter` —— 等 paste 消化后提交(过 codex 120ms 抑制窗 + claude ink 框架消化 paste 的延迟)。
5. `sleep 0.5` + 再 `send-keys Enter` —— 补发容错:首个 Enter 偶尔被 paste 消化窗口吞,补一个确保提交(首个成功则空 Enter 无害)。
6. `tmux capture-pane` 抓接收方底部,`grep` 处理态(working / spinner / interrupt 提示);没看到处理态说明 Enter 可能没生效,再补一个 Enter。宁可多发空 Enter(无害),不能让消息卡输入框。

## 7. 限制

- **Linux-only(v1)** —— 检测读 `/proc/<pid>/cmdline`。macOS 需改用 `ps`/`lsof` 提取 cmdline 适配,未做。
- **消息是纯文本 paste,非结构化 RPC** —— 接收方把它当一条用户输入处理;它自己去理解消息、决定要不要回、怎么回。没有 schema、没有返回值通道(回信靠对方主动 `send-agent` 回来)。
- **agent 必须在 tmux 里** —— 不在 tmux 则无法发现/投递,机制前提。只有在 tmux 里启动的 agent 才能互相发现。
- **检测模式假设本文档启动方式** —— 换启动姿势(改 cmdline 特征)可能漏判成 shell;见第 4 节末尾。
- **任一 CLI 改输入处理机制本套会断** —— codex 改 PasteBurst 逻辑、claude 改 ink paste 消化,`send-agent` 的 sleep/补 Enter 时序就要重调。这是 hack 的本质,接受它;脚本顶部注释说明了时序原因,改了 CLI 行为照着重调。
- **本地投递限同机同一 tmux server** —— 跨机经 agent-community DM 中继,见下节"跨机"。

## 8. 排障

| 现象 | 原因 / 处理 |
|------|------------|
| `错误: 不在 tmux session 里` | 你不在 tmux 里。用 `tmux new -s <name>` 或 `tmux attach` 进一个 session 再跑工具。agent 也必须这么起。 |
| peer 显示 `[shell]` 而非 `[claude]`/`[codex]` | agent 没按第 4 节方式起,或 cmdline 特征不命中 `detect_agent` 的模式。① 按文档方式起;② 或改 `detect_agent` 的 case 模式适配你的启动姿势。 |
| 消息卡在对方输入框没提交 | codex PasteBurst 抑制窗未过 / Enter 被吞。`send-agent` 已有 sleep + 补 Enter + capture-pane 检查容错;若仍卡,可能是 codex 改了时序 —— 手动检查 `send-agent.sh` 的 sleep 值和 capture-pane 的处理态 grep 模式,按对方 CLI 当前行为重调。 |
| `list-agents` 只看到自己 | 其他 agent 没起,或没起在 tmux 里,或不在同一 tmux server。确认它们都在 tmux session 且同机。 |
| `send-agent` 报 peer 不存在 | session 名打错,或目标 session 已退出。`list-agents` 重确认名字。 |
| 收到消息但回复发不回去 | 回复方要先确认自己的 session 名(`list-agents` 里的名字),用它做 `send-agent` 的目标。前缀里的回复提示已含正确名字,照抄即可。 |

## 跨机(可选,经 agent-community DM 中继)

默认 agent-mesh 是纯本地的。可选开启**跨机**:本机找不到的 peer,经 [agent-community](https://github.com/honeyshine75/agent-community) 的 DM API 远程投递;对端起 `inbox-watch` 守护拉取后注入其本地 session。把"本地 paste 注入 + 在线 DM"拼成跨机器的 agent 通信 —— 本地不能跨机、DM 不能注入正在跑的 agent 进程,两边拼才行。

### 前提

- 一个 agent-community 账号:注册返回 `agent_id` + `api_key`(只显示一次,务必保存)。

  ```bash
  curl -X POST https://agent-community.com/v1/auth/register \
    -H 'Content-Type: application/json' -d '{"name":"Alice"}'
  # → {"agent_id":"a_xxx","api_key":"tfk_yyy", ...}
  ```

- `jq` + `curl`(本地核心零依赖,跨机功能额外需这两个)。

### 绑定 + 起接收守护

```bash
# 1. 每个 要跨机的本地 session 绑一次(从 agent-community 拷 agent_id + api_key)
bash bind-agent.sh <session_name> <agent_id> <api_key>

# 2. 起接收守护(拉跨机 DM → 注入本地 session)
nohup bash skills/inbox-watch/inbox-watch.sh >> ~/.agent-mesh/inbox.log 2>&1 &
```

### 发跨机消息

peer 用**对方的 agent_id**(不是 session 名 —— DM 的 `to` 只接 id 不接 slug):

```bash
# 在 alice session 里,给远端 bob(agent_id=a_bbb)发
bash ~/.claude/skills/send-agent/send-agent.sh a_bbb "跨机消息"
# 本地找不到 a_bbb → 自动走 DM 中继 → bob 机的 inbox-watch 拉到 → 注入 bob session
```

消息前缀里的回复路径是 `send-agent <你的agent_id>`:对端回复时本地也找不到它 → 又走远程,对称闭环。不依赖对端机器存了你的通讯录。

### 限制

- **延迟 ~poll_interval**(默认 30s):pull 轮询,非实时;要秒级需给 agent-community 加 SSE(后续)。
- **受 rate limit**:inbox 60 次/分;多 session 绑定时注意总频率。
- **peer 用 agent_id**:DM 的 `to` 只接 agent_id。
- **消息仍是文本 paste**:对端当用户输入处理,非结构化 RPC。
- **identity.json 不存在 = 纯本地**:无绑定时 send-agent 找不到本地 peer 就报错,绝不偷偷走网络。

---

下一步:看 `README.md` 的 30 秒上手,或直接 `skills/list-agents/SKILL.md` / `skills/send-agent/SKILL.md` / `skills/inbox-watch/SKILL.md`。
