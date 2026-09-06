#!/usr/bin/env bash
# mark-tests-passed.sh — 現在の差分がテスト計画の確認(/test-check)に合格したことを記録する
# (review-loop の pr-ready-gate.sh と同一ロジックで差分ハッシュを計算し、.git/ 内にマーカーを書く)
# 使い方: mark-tests-passed.sh [ベースブランチ]
set -euo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "gitリポジトリ内で実行してください" >&2; exit 1; }

DIR="$(cd "$(dirname "$0")" && pwd)"
DIFF=$("$DIR/review-diff.sh" "${1:-}")
BASE_LINE=$(printf '%s\n' "$DIFF" | head -1)
BODY=$(printf '%s\n' "$DIFF" | tail -n +2)
HASH=$(printf '%s\n' "$BODY" | sha256sum | cut -d' ' -f1)

MARKER="$(git rev-parse --git-dir)/claude-tests-passed"
echo "$HASH" > "$MARKER"
echo "テスト確認の合格を記録しました(${BASE_LINE#\# }): $MARKER"
