#!/usr/bin/env bash
# events-log.sh — dev-tools の利用イベントを JSONL で 1 行追記する(計測用)
#
# 使い方: events-log.sh <event> [key=value ...]
#   例: events-log.sh review.round run_id=20260906 round=1 critical=0 warning=2 info=3 verdict=continue tier=2
#       events-log.sh gate.block command="gh pr ready" reason=review
# 数値に見える値は数値として、それ以外は文字列として記録する。
#
# 記録先の優先順位:
#   1. 環境変数 DEV_TOOLS_LOG
#   2. リポジトリ内に .claude/ があれば <repo>/.claude/dev-tools.log.jsonl(Web/リポジトリモード)
#   3. ~/.claude/dev-tools.log.jsonl(ローカルモード)
set -euo pipefail

[ $# -ge 1 ] || { echo "Usage: $0 <event> [key=value ...]" >&2; exit 1; }
EVENT="$1"; shift

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -n "${DEV_TOOLS_LOG:-}" ]; then
  LOG="$DEV_TOOLS_LOG"
elif [ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT/.claude" ]; then
  LOG="$REPO_ROOT/.claude/dev-tools.log.jsonl"
else
  LOG="${HOME}/.claude/dev-tools.log.jsonl"
fi
mkdir -p "$(dirname "$LOG")"

REPO=$(basename "${REPO_ROOT:-$(pwd)}")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "-")

ARGS=(--arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg event "$EVENT" --arg repo "$REPO" --arg branch "$BRANCH")
FILTER='{ts:$ts, event:$event, repo:$repo, branch:$branch}'
i=0
for kv in "$@"; do
  key="${kv%%=*}"; val="${kv#*=}"
  i=$((i+1))
  if [[ "$val" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || [ "$val" = "true" ] || [ "$val" = "false" ]; then
    ARGS+=(--argjson "v$i" "$val")
  else
    ARGS+=(--arg "v$i" "$val")
  fi
  FILTER="$FILTER + {\"$key\": \$v$i}"
done

jq -cn "${ARGS[@]}" "$FILTER" >> "$LOG"
echo "logged $EVENT to $LOG"
