#!/usr/bin/env bash
# mark-review-passed.sh — 現在の差分が品質レビューに合格したことを記録する
# (pr-ready-gate.sh と同一ロジックで差分ハッシュを計算し、.git/ 内にマーカーを書く)
# 使い方: mark-review-passed.sh [ベースブランチ]
set -euo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "gitリポジトリ内で実行してください" >&2; exit 1; }

DIR="$(cd "$(dirname "$0")" && pwd)"
DIFF=$("$DIR/review-diff.sh" "${1:-}")
BASE_LINE=$(printf '%s\n' "$DIFF" | head -1)
BODY=$(printf '%s\n' "$DIFF" | tail -n +2)
HASH=$(printf '%s\n' "$BODY" | sha256sum | cut -d' ' -f1)
LINES=$(printf '%s\n' "$BODY" | grep -Ec '^[+-][^+-]' || true)

MARKER="$(git rev-parse --git-dir)/claude-review-passed"
echo "$HASH" > "$MARKER"
"$DIR/events-log.sh" review.pass diff_lines="$LINES" >/dev/null 2>&1 || true
echo "レビュー合格を記録しました(${BASE_LINE#\# }): $MARKER"
