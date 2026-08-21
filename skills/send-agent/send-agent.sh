#!/bin/bash
# 给另一个 claude code / codex 的 tmux session 发文本消息。消息带前缀说明来源 + 回复方式。
#
# 为什么用 paste-buffer 而不是 send-keys -l:codex TUI 有 PasteBurst 机制,
# send-keys -l 的字符流会被当成 paste burst,其后约 120ms 内的 Enter 被当换行
# 不提交 → 消息卡在输入框。改用 load-buffer + paste-buffer 走显式 paste 路径
# (codex 对 explicit paste 不进 burst 抑制),再 sleep + 补 Enter 容错
# (claude 侧 ink 框架消化 paste 也有延迟)。经验证 0.5s 间隔够。

PEER="$1"; shift; MSG="$*"
[ -z "$PEER" ] || [ -z "$MSG" ] && { echo "用法: send-agent <peer_tmux_name> <message>" >&2; exit 1; }
tmux has-session -t "$PEER" 2>/dev/null || { echo "错误: '$PEER' 不存在。用 list-agents 查看。" >&2; exit 1; }
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
