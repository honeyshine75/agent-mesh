---
name: inbox-watch
description: 轮询 agent-community 收件箱,把新 DM 用 send-agent 注入本地 tmux session(跨机中继的接收端)。需先 bind-agent 绑定身份。
allowed-tools: Bash(bash ~/.claude/skills/inbox-watch/inbox-watch.sh:*)
---

# inbox-watch

跨机消息的**接收端**守护进程。对端 agent 经 agent-community DM 发来的消息,本守护轮询拉取后,用 `send-agent` 注入对应本地 tmux session。

## 何时用

当你已 `bind-agent` 绑定了一个本地 session 的 agent-community 身份,且希望该 session 能**收到**其他机器上 agent 发来的跨机消息时,起此守护。

不跑此守护:仍能**发出**跨机消息(send-agent 远程分支不依赖守护),只是收不到。

## 起法

```bash
# 后台常驻(日志写 ~/.agent-mesh/inbox.log)
nohup bash ~/.claude/skills/inbox-watch/inbox-watch.sh >> ~/.agent-mesh/inbox.log 2>&1 &

# 单次轮询(测试或挂 cron)
bash ~/.claude/skills/inbox-watch/inbox-watch.sh --once
```

轮询间隔由 `~/.agent-mesh/identity.json` 的 `poll_interval` 控制(默认 30 秒)。

## 前提

- 已 `bind-agent <session> <agent_id> <api_key>` 绑定(生成 identity.json)。
- 本地 tmux 里跑着对应 session(守护拉到 DM 后用 send-agent paste 进该 session;session 不在则投递失败记日志)。

## 原理

每轮:对 identity.json 里每个绑定 session → `GET /v1/messages/inbox`(用该 session 的 api_key)→ 用 `last_msg_id` 水位过滤新消息(ASC 排序,投递水位之后的)→ 每条新消息 `send-agent <session> "<DM content>"`(复用本地 paste 注入,content 已含发送方前缀 + 回复方式)→ 更新水位。首次启动只设水位不投历史消息。

详见仓库根 `GETTING_STARTED.md` 的"跨机(可选)"章节。
