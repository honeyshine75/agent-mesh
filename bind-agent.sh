#!/bin/bash
# 绑定本地 tmux session 名 ↔ agent-community 身份(agent_id + api_key)。
# 写入 ~/.agent-mesh/identity.json,供 send-agent 远程投递 + inbox-watch 轮询用。
# 绑定前先用 api_key 调一次 inbox 验证 key 有效。
#
# 用法: bash bind-agent.sh <session_name> <agent_id> <api_key>
#
# agent_id 和 api_key 都从 agent-community 注册接口拿:
#   curl -X POST https://agent-community.com/v1/auth/register -H 'Content-Type: application/json' -d '{"name":"Alice"}'
#   → {"agent_id":"a_xxx","api_key":"tfk_yyy", ...}  # api_key 只返回一次,务必保存

set -euo pipefail

SESSION="${1:-}"
AGENT_ID="${2:-}"
API_KEY="${3:-}"
[ -n "$SESSION" ] && [ -n "$AGENT_ID" ] && [ -n "$API_KEY" ] || {
    echo "用法: bind-agent <session_name> <agent_id> <api_key>" >&2
    echo "  session_name: 本机 tmux session 名(list-agents 里看到的)" >&2
    echo "  agent_id/api_key: agent-community 注册返回的值" >&2
    exit 1
}

command -v jq >/dev/null 2>&1 || { echo "错误: 需要 jq(apt install jq / brew install jq)" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "错误: 需要 curl" >&2; exit 1; }

DIR="$HOME/.agent-mesh"
IDENTITY="$DIR/identity.json"
mkdir -p "$DIR"

# 读已有 community_url 或用默认(identity.json 不存在时)
if [ -f "$IDENTITY" ]; then
    COMMUNITY_URL=$(jq -r '.community_url // "https://agent-community.com"' "$IDENTITY")
else
    COMMUNITY_URL="https://agent-community.com"
fi

# 验证 api_key:调 inbox,200=有效
echo "验证 api_key @ $COMMUNITY_URL ..."
code=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' "$COMMUNITY_URL/v1/messages/inbox?limit=1" \
    -H "Authorization: Bearer $API_KEY" 2>/dev/null) || code="000"
case "$code" in
    200) ;;
    401) echo "错误: api_key 无效(401)。重新注册拿新 key。" >&2; exit 1;;
    *) echo "错误: 验证失败(HTTP $code)。检查 community_url($COMMUNITY_URL)和网络。" >&2; exit 1;;
esac

# 创建或更新 identity.json
if [ ! -f "$IDENTITY" ]; then
    echo "创建 $IDENTITY"
    jq -n --arg url "$COMMUNITY_URL" '{community_url:$url, poll_interval:30, sessions:{}}' > "$IDENTITY"
fi
tmp=$(mktemp)
jq --arg s "$SESSION" --arg id "$AGENT_ID" --arg k "$API_KEY" --arg url "$COMMUNITY_URL" \
    '.community_url=$url | .sessions[$s]={agent_id:$id, api_key:$k, last_msg_id:""}' \
    "$IDENTITY" > "$tmp" && mv "$tmp" "$IDENTITY"

echo "✓ 已绑定: $SESSION → agent_id=$AGENT_ID"
echo "  配置: $IDENTITY"
echo ""
echo "现在(在 $SESSION 的 tmux session 里)可跨机发消息:"
echo "  send-agent $AGENT_ID \"跨机消息内容\""
echo "收跨机消息,起轮询守护:"
echo "  nohup bash $(dirname "$0")/skills/inbox-watch/inbox-watch.sh >> $DIR/inbox.log 2>&1 &"
