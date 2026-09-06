#!/usr/bin/env bash
# design-refs.sh — このブランチで突合すべき Figma の参照(デザイン参照)を集めて出す
#
# 探す順: 1. .claude/specs/<branch>.md の「## デザイン」節にある figma.com の行
#         2. 現在ブランチの PR 本文にある figma.com の URL(gh が使えるとき)
# 出力: 先頭行 "# source: spec|pr|none"、以降は 1 行 1 参照(spec の行はそのまま、PR は URL だけ)
# 終了コード: 参照が 1 つも無ければ 1
set -uo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "gitリポジトリ内で実行してください" >&2; exit 1; }
ROOT=$(git rev-parse --show-toplevel)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
SPEC="$ROOT/.claude/specs/${BRANCH//\//-}.md"

if [ -f "$SPEC" ]; then
  LINES=$(awk '
    /^## /{ in_sec = ($0 ~ /^## デザイン/) }
    in_sec && /figma\.com\// { print }
  ' "$SPEC")
  if [ -n "$LINES" ]; then
    echo "# source: spec ($SPEC)"
    printf '%s\n' "$LINES"
    exit 0
  fi
fi

if command -v gh >/dev/null 2>&1; then
  URLS=$(gh pr view "$BRANCH" --json body -q .body 2>/dev/null | grep -Eo 'https://(www\.)?figma\.com/[^ )>"]+' | sort -u || true)
  if [ -n "$URLS" ]; then
    echo "# source: pr"
    printf '%s\n' "$URLS"
    exit 0
  fi
fi

echo "# source: none"
exit 1
