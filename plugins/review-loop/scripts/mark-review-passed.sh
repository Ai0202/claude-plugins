#!/usr/bin/env bash
# mark-review-passed.sh — 現在の差分が /review-loop に合格したことを記録する
# (review-stop-gate.sh と同一ロジックで差分ハッシュを計算し、.git/ 内にマーカーを書く)
set -euo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "gitリポジトリ内で実行してください" >&2; exit 1; }

BASE=""
for b in main master; do
  git show-ref --verify --quiet "refs/heads/$b" && BASE="$b" && break
done

{
  [ -n "$BASE" ] && git diff "${BASE}...HEAD" 2>/dev/null
  git diff HEAD 2>/dev/null
} > /tmp/claude-review-diff.$$ 2>/dev/null

HASH=$(sha256sum /tmp/claude-review-diff.$$ | cut -d' ' -f1)
rm -f /tmp/claude-review-diff.$$

MARKER="$(git rev-parse --git-dir)/claude-review-passed"
echo "$HASH" > "$MARKER"
echo "レビュー合格を記録しました: $MARKER"
