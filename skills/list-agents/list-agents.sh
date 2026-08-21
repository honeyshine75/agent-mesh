#!/bin/bash
# 列出本机所有 tmux session,标注每个 session 跑的 agent 类型(claude/codex/shell)。
# 可被 source:暴露 descendants_of / detect_agent / pane_pid_of 函数(send-agent 复用)。
#
# 检测逻辑:从 tmux session 的 pane_pid 出发,BFS 收集进程树,读每个后代的
# /proc/<pid>/cmdline 模式匹配:
#   claude = cmdline 二进制路径含 claude-code(npm 包 @anthropic-ai/claude-code*),或裸命令 claude
#   codex  = cmdline 含 codex 二进制(路径 /codex 或裸命令 codex)
#   shell  = 空壳(只有 bash,agent 没起来)
#
# 检测模式假设 agent 按 GETTING_STARTED.md 的方式启动;启动方式不同需调 detect_agent。

_PS_TREE=""
_ps_tree() { [ -z "$_PS_TREE" ] && _PS_TREE=$(ps -eo pid,ppid --no-headers 2>/dev/null); echo "$_PS_TREE"; }

# 从 root pid 做 BFS 收集所有后代(含 root 自身)
descendants_of() {
    _ps_tree | awk -v root="$1" '
        { children[$2] = children[$2] " " $1 }
        END {
            n = 1; q[1] = root; seen[root] = 1
            for (h = 1; h <= n; h++) {
                pid = q[h]; print pid
                nc = split(children[pid], c, " ")
                for (i = 1; i <= nc; i++)
                    if (c[i] != "" && !(c[i] in seen)) { seen[c[i]]=1; q[++n]=c[i] }
            }
        }'
}

# 给定 pane_pid,判断该 tmux session 跑的 agent 类型:claude/codex/shell
detect_agent() {
    local pane_pid="$1"
    [ -z "$pane_pid" ] && { echo "shell"; return; }
    local pid cmdline
    for pid in $(descendants_of "$pane_pid"); do
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || continue
        [ -z "$cmdline" ] && continue
        # codex: 二进制路径含 /codex,或裸命令 codex(node 包装或直接调用)
        if echo "$cmdline" | grep -qE '(^| )codex( |$)|/codex'; then
            echo "codex"; return
        fi
        # claude code: 二进制路径含 claude-code(npm 包),或裸命令 claude(裸启动无 --resume 也命中)
        if echo "$cmdline" | grep -qE -- 'claude-code|(^|/)claude( |$)'; then
            echo "claude"; return
        fi
    done
    echo "shell"
}

pane_pid_of() { tmux list-panes -t "$1" -F '#{pane_pid}' 2>/dev/null | head -1; }

# 仅直接执行时跑列表(source 时只暴露函数)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SELF=$(tmux display-message -p '#{session_name}' 2>/dev/null)
    [ -z "$SELF" ] && { echo "错误: 不在 tmux session 里(用 tmux 启动 agent,见 GETTING_STARTED.md)" >&2; exit 1; }
    self_agent=$(detect_agent "$(pane_pid_of "$SELF")")
    echo "当前 session: [$self_agent] $SELF"
    echo "其他 agent session:"
    tmux list-sessions -F '#{session_name}' 2>/dev/null | while read -r name; do
        [ "$name" = "$SELF" ] && continue
        agent=$(detect_agent "$(pane_pid_of "$name")")
        echo "  [$agent] $name"
    done
fi
