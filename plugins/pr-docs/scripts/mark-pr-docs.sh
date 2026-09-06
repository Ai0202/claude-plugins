#!/usr/bin/env bash
# mark-pr-docs.sh — 「この PR の説明と解説コメントは HEAD の内容に追随済み」を記録する
# 使い方: mark-pr-docs.sh <PR番号> [解説コメント数]
set -euo pipefail

[ $# -ge 1 ] || { echo "Usage: $0 <pr-number> [comments]" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "gitリポジトリ内で実行してください" >&2; exit 1; }

HEAD_SHA=$(git rev-parse HEAD)
MARKER="$(git rev-parse --git-dir)/claude-pr-docs"
echo "$1 $HEAD_SHA" > "$MARKER"

DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/events-log.sh" pr_docs.done pr="$1" comments="${2:-0}" >/dev/null 2>&1 || true
echo "PR #$1 の説明更新を記録しました(${HEAD_SHA:0:7}): $MARKER"
