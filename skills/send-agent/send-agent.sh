#!/bin/bash
# 给另一个 claude code / codex 的 tmux session 发文本消息。消息带前缀说明来源 + 回复方式。
#
# 两种投递路径:
#   本地 —— PEER 是本机 tmux session 名:tmux paste-buffer 注入(默认,零外部依赖)。
#   远程 —— PEER 不在本地 tmux 且 ~/.agent-mesh/identity.json 里 SELF 已绑定
#           agent-community 身份:经 agent-community DM 中继投递(可选,需 jq + curl)。
#           identity.json 不存在或 SELF 未绑定时,回退本地报错,纯本地用户零感知。
#
# 为什么用 paste-buffer 而不是 send-keys -l:codex TUI 有 PasteBurst 机制,
# send-keys -l 的字符流会被当成 paste burst,其后约 120ms 内的 Enter 被当换行
# 不提交 → 消息卡在输入框。改用 load-buffer + paste-buffer 走显式 paste 路径
# (codex 对 explicit paste 不进 burst 抑制),再 sleep + 补 Enter 容错
# (claude 侧 ink 框架消化 paste 也有延迟)。经验证 0.5s 间隔够。

PEER="$1"; shift; MSG="$*"
[ -z "$PEER" ] || [ -z "$MSG" ] && { echo "用法: send-agent <peer_tmux_name|agent_id> <message>" >&2; exit 1; }

SELF=$(tmux display-message -p '#{session_name}' 2>/dev/null)
[ -z "$SELF" ] && { echo "错误: 不在 tmux session 里(用 tmux 启动 agent,见 GETTING_STARTED.md)" >&2; exit 1; }

# 复用 list-agents 的 detect_agent 确定自己的类型,消息前缀标注来源 agent
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
self_agent="agent"
LIST_AGENTS="$SCRIPT_DIR/../list-agents/list-agents.sh"
[ -f "$LIST_AGENTS" ] || LIST_AGENTS="$SCRIPT_DIR/list-agents/list-agents.sh"
if [ -f "$LIST_AGENTS" ]; then
    # shellcheck source=list-agents/list-agents.sh
    # shellcheck disable=SC1091
    source "$LIST_AGENTS"
    type detect_agent >/dev/null 2>&1 && \
        self_agent=$(detect_agent "$(tmux list-panes -t "$SELF" -F '#{pane_pid}' 2>/dev/null | head -1)")
fi

IDENTITY="$HOME/.agent-mesh/identity.json"

# 远程中继投递:PEER 不在本地 tmux 时,经 agent-community DM 投递。
# 返回 0 = 已投递;返回 1 = 未满足远程条件(无 identity / SELF 未绑 / 无 jq),调用方走原报错。
relay_remote() {
    [ -f "$IDENTITY" ] || return 1
    command -v jq >/dev/null 2>&1 || { echo "错误: 跨机投递需 jq(本地投递不用;跨机见 GETTING_STARTED.md)" >&2; exit 1; }
    local my_agent_id my_api_key community_url
    my_agent_id=$(jq -r --arg s "$SELF" '.sessions[$s].agent_id // empty' "$IDENTITY" 2>/dev/null)
    my_api_key=$(jq -r --arg s "$SELF" '.sessions[$s].api_key // empty' "$IDENTITY" 2>/dev/null)
    [ -n "$my_agent_id" ] && [ -n "$my_api_key" ] || return 1
    community_url=$(jq -r '.community_url // "https://agent-community.com"' "$IDENTITY" 2>/dev/null)
    # 回复路径用 sender 的 agent_id:对端回复 send-agent <agent_id> 时本地必找不到 → 又走远程,对称闭环
    local content="[📨 来自 $self_agent:$SELF(远程)] $MSG | 回复: send-agent $my_agent_id <你的回复>"
    local body
    body=$(jq -nc --arg to "$PEER" --arg c "$content" '{to:$to, content:$c}')
    local code
    code=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' -X POST "$community_url/v1/messages" \
        -H "Authorization: Bearer $my_api_key" -H "Content-Type: application/json" \
        -d "$body" 2>/dev/null) || code="000"
    case "$code" in
        201) echo "已远程发送给 $PEER ($self_agent→,经 $community_url): $MSG";;
        404) echo "错误: 对方 agent_id '$PEER' 在 agent-community 不存在(404)。确认 id 是否正确。" >&2; exit 1;;
        401) echo "错误: api_key 无效或已失效(401)。重新 bind-agent $SELF <agent_id> <api_key>。" >&2; exit 1;;
        *) echo "错误: 远程投递失败(HTTP $code)。稍后重试或检查网络/社区地址。" >&2; exit 1;;
    esac
}

if tmux has-session -t "$PEER" 2>/dev/null; then
    # ── 本地投递(现有逻辑,不变)──
    PREFIX="[📨 来自 $self_agent:$SELF] $MSG | 回复: send-agent $SELF <你的回复>"

    # load-buffer + paste-buffer:显式 paste,bypass codex PasteBurst 的 Enter 抑制
    BUF="sendagent_$$"
    printf '%s' "$PREFIX" | tmux load-buffer -b "$BUF" -
    tmux paste-buffer -t "$PEER" -b "$BUF" -d
    sleep 0.5   # 过 codex PasteBurst 120ms 抑制 + 等 claude ink 消化 paste
    tmux send-keys -t "$PEER" Enter
    sleep 0.5   # 等 TUI 处理,首个 Enter 偶被 paste 消化窗口吞
    tmux send-keys -t "$PEER" Enter   # 补发容错(首个被吞则提交;首个成功则空 Enter 无害)
    # 确认提交成功:capture 接收方底部,没看到处理态(Working/spinner/interrupt)说明 Enter 可能被吞,
    # 再补一个 Enter 确保——宁可多发空 Enter(无害),不能让消息卡输入框
    sleep 0.4
    pane=$(tmux capture-pane -t "$PEER" -p -S -8 2>/dev/null)
    echo "$pane" | grep -qiE 'working|esc to interrupt|esc.*interrupt|thinking|⏺|✶' || \
        tmux send-keys -t "$PEER" Enter
    echo "已发送给 $PEER ($self_agent→): $MSG"
else
    # ── 本地找不到 → 尝试远程中继,未满足条件则原报错(纯本地用户零感知)──
    relay_remote || { echo "错误: '$PEER' 不存在。用 list-agents 查看本地 peer;跨机需先 bind-agent 绑定身份(见 GETTING_STARTED.md)。" >&2; exit 1; }
fi
