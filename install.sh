#!/bin/bash
# 安装 agent-mesh skills:把 list-agents / send-agent 软链到 ~/.claude/skills/。
# claude code 靠 SKILL.md 自动发现 skill;codex 靠指令里写明脚本路径调用。
#
# 用法: bash install.sh
# 可设 CLAUDE_SKILLS_DIR 覆盖默认 ~/.claude/skills。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
SRC_LIST="$SCRIPT_DIR/skills/list-agents"
SRC_SEND="$SCRIPT_DIR/skills/send-agent"

echo "安装目录: $SKILLS_DIR"
mkdir -p "$SKILLS_DIR"

for src in "$SRC_LIST" "$SRC_SEND"; do
    name=$(basename "$src")
    dst="$SKILLS_DIR/$name"
    if [ -L "$dst" ] || [ -e "$dst" ]; then
        echo "  - 已存在 $dst,覆盖软链"
        rm -f "$dst"
    fi
    ln -s "$src" "$dst"
    echo "  ✓ $name → $dst"
done

chmod +x "$SRC_LIST/list-agents.sh" "$SRC_SEND/send-agent.sh" 2>/dev/null || true

cat <<EOF

完成。验证:
  bash $SKILLS_DIR/list-agents/list-agents.sh        # 列出 agent(需在 tmux 里跑)
  bash $SKILLS_DIR/send-agent/send-agent.sh <peer> "<msg>"

claude code 侧:skill 已自动发现(下次会话或 /skills 可见 list-agents / send-agent)。

codex 侧:codex 不读 SKILL.md,需在 ~/.codex/AGENTS.md(或等价指令文件)里写明调用方式,例如:
  列出其他 agent: bash $SKILLS_DIR/list-agents/list-agents.sh
  给某 agent 发消息: bash $SKILLS_DIR/send-agent/send-agent.sh <peer> "<你的消息>"
详见 GETTING_STARTED.md 的"启动 agent"与"原理"章节。
EOF
