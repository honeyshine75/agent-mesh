#!/bin/bash
# 轮询守护:拉 agent-community 收件箱,把新 DM 用 send-agent 本地 paste 进对应 tmux session。
# 这是跨机中继的接收端:对端经 DM 投递的消息,本守护拉到后注入本地 agent。
#
# 依赖 ~/.agent-mesh/identity.json(bind-agent 生成):每个绑定的 session 有 api_key + last_msg_id。
# 不跑此守护 = 不收跨机消息;不影响本地 send-agent 投递。
#
# 用法:
#   后台常驻: nohup bash inbox-watch.sh >> ~/.agent-mesh/inbox.log 2>&1 &
#   单次轮询(测试/cron): bash inbox-watch.sh --once
#
# 依赖:jq + curl + tmux(本地 paste 走 send-agent)。轮询间隔由 identity.json 的 poll_interval 定(默认 30s)。

set -euo pipefail

IDENTITY="$HOME/.agent-mesh/identity.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEND_AGENT="$SCRIPT_DIR/../send-agent/send-agent.sh"
[ -f "$SEND_AGENT" ] || SEND_AGENT="$SCRIPT_DIR/send-agent/send-agent.sh"

ONCE=0
[ "${1:-}" = "--once" ] && ONCE=1

[ -f "$IDENTITY" ] || { echo "错误: 无 $IDENTITY。先 bash bind-agent.sh <session> <agent_id> <api_key> 绑定。" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "错误: 需要 jq" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "错误: 需要 curl" >&2; exit 1; }

# 轮询单个 session:拉 inbox → 过滤水位之后的新消息 → 本地 paste → 更新水位
poll_session() {
    local session="$1" api_key="$2" last_id="$3"
    local community_url inbox rows
    community_url=$(jq -r '.community_url // "https://agent-community.com"' "$IDENTITY")
    inbox=$(curl -sS -m 15 "$community_url/v1/messages/inbox?limit=50" \
        -H "Authorization: Bearer $api_key" 2>/dev/null) || { echo "$(date '+%H:%M:%S') [$session] 拉取失败,下轮重试" >&2; return; }

    # ASC(旧→新),tab 分隔 id\tcontent;空收件箱则无输出
    mapfile -t rows < <(echo "$inbox" | jq -r 'if (.messages|length)>0 then (.messages|sort_by(.created_at)|.[]|"\(.id)\t\(.content)") else empty end' 2>/dev/null)
    [ "${#rows[@]}" -eq 0 ] && return

    # 水位 last_id 是否在当前批次:首次(空)视为在(跳过全部只设水位);不在=水位丢失(超50条),全投防漏
    local has_last=0 id content new_last="$last_id" skip=1
    [ -z "$last_id" ] && has_last=1
    for r in "${rows[@]}"; do id="${r%%$'\t'*}"; [ "$id" = "$last_id" ] && has_last=1; done

    for r in "${rows[@]}"; do
        id="${r%%$'\t'*}"; content="${r#*$'\t'}"
        new_last="$id"   # ASC,最后赋值即最新消息 id
        if [ "$skip" = "1" ]; then
            if [ "$has_last" = "1" ]; then
                # 水位在批次内:跳过到水位(含),其后投递;首次(空水位)则跳过全部只设水位
                [ -n "$last_id" ] && [ "$id" = "$last_id" ] && skip=0
                continue
            else
                # 水位丢失(超出 limit 范围):从这里起全投,防漏
                skip=0
            fi
        fi
        # 复用 send-agent 本地 paste 路径(content 已含发送方前缀 + 回复方式)
        if bash "$SEND_AGENT" "$session" "$content" >/dev/null 2>&1; then
            echo "$(date '+%H:%M:%S') [$session] ← $id: ${content:0:60}"
        else
            echo "$(date '+%H:%M:%S') [$session] 投递失败(目标 session 不在 tmux?):$id" >&2
        fi
    done

    # 水位前进才写回(减少 IO)
    if [ "$new_last" != "$last_id" ]; then
        local tmp; tmp=$(mktemp)
        jq --arg s "$session" --arg l "$new_last" '.sessions[$s].last_msg_id=$l' "$IDENTITY" > "$tmp" && mv "$tmp" "$IDENTITY"
    fi
}

echo "$(date '+%H:%M:%S') inbox-watch 启动($([ "$ONCE" = "1" ] && echo '单次' || echo '常驻'))"

while true; do
    # 每轮重读 identity(支持运行中 bind 新 session)
    sessions_json=$(jq -r '.sessions // {} | to_entries | .[] | "\(.key)\t\(.value.api_key)\t\(.value.last_msg_id // "")"' "$IDENTITY" 2>/dev/null)
    if [ -n "$sessions_json" ]; then
        while IFS=$'\t' read -r s key last; do
            [ -n "$s" ] && poll_session "$s" "$key" "$last"
        done <<< "$sessions_json"
    fi

    [ "$ONCE" = "1" ] && break
    poll_interval=$(jq -r '.poll_interval // 30' "$IDENTITY")
    sleep "$poll_interval"
done
