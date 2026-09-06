#!/usr/bin/env bash
# review-loop-log.sh — レビューループの各ラウンドを JSONL で記録する
# 使い方: review-loop-log.sh <run_id> <round> <critical> <warning> <info> <verdict> [tier]
#
# 記録先の優先順位:
#   1. 環境変数 REVIEW_LOOP_LOG
#   2. リポジトリ内 .claude/ ディレクトリがあれば <repo>/.claude/review-loop.log.jsonl(Web/リポジトリモード)
#   3. ~/.claude/review-loop.log.jsonl(ローカルモード)
set -euo pipefail

if [ $# -lt 6 ]; then
  echo "Usage: $0 <run_id> <round> <critical> <warning> <info> <verdict> [tier]" >&2
  exit 1
fi
TIER="${7:--}"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -n "${REVIEW_LOOP_LOG:-}" ]; then
  LOG="$REVIEW_LOOP_LOG"
elif [ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT/.claude" ]; then
  LOG="$REPO_ROOT/.claude/review-loop.log.jsonl"
else
  LOG="${HOME}/.claude/review-loop.log.jsonl"
fi
mkdir -p "$(dirname "$LOG")"

REPO=$(basename "${REPO_ROOT:-$(pwd)}")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "-")

jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg repo "$REPO" \
  --arg branch "$BRANCH" \
  --arg run_id "$1" \
  --argjson round "$2" \
  --argjson critical "$3" \
  --argjson warning "$4" \
  --argjson info "$5" \
  --arg verdict "$6" \
  --arg tier "$TIER" \
  '{ts:$ts, repo:$repo, branch:$branch, run_id:$run_id, round:$round, critical:$critical, warning:$warning, info:$info, verdict:$verdict, tier:$tier}' \
  >> "$LOG"

echo "logged to $LOG: run=$1 round=$2 tier=$TIER critical=$3 warning=$4 info=$5 verdict=$6"
