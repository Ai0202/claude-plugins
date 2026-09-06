#!/usr/bin/env bash
# review-stop-gate.sh — Stopフック用ゲート
# コード変更があるのにレビューループが未合格なら、Claudeのタスク完了をブロックして
# /review-loop の実行を指示する。
#
# 無限ループ防止: stop_hook_active が true のとき(既に一度ブロック済みのとき)は素通しする。
set -uo pipefail

INPUT=$(cat)

# --- ガード1: 既にブロック済みなら止めない(無限ループ防止・必須) ---
# jq がない環境でも確実に動くよう、jq → grep の順でフォールバックする
if command -v jq >/dev/null 2>&1; then
  ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
else
  echo "$INPUT" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && ACTIVE="true" || ACTIVE="false"
fi
[ "$ACTIVE" = "true" ] && exit 0

# --- ガード2: gitリポジトリ外なら何もしない ---
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# --- 差分ハッシュの計算(mark-review-passed.sh と同一ロジック) ---
DIR="$(cd "$(dirname "$0")" && pwd)"
DIFF=$("$DIR/review-diff.sh" 2>/dev/null) || exit 0
BASE_LINE=$(printf '%s\n' "$DIFF" | head -1)
BODY=$(printf '%s\n' "$DIFF" | tail -n +2)

# --- ガード3: 差分がなければ止めない ---
[ -z "$BODY" ] && exit 0

HASH=$(printf '%s\n' "$BODY" | sha256sum | cut -d' ' -f1)

MARKER="$(git rev-parse --git-dir)/claude-review-passed"

# --- 合格マーカーが現在の差分と一致していれば止めない ---
if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$HASH" ]; then
  exit 0
fi

# --- ブロック: レビューループを指示 ---
echo "コード変更(${BASE_LINE#\# })に対してレビューループが未合格です。タスクを完了する前に /review-loop を実行し、Critical と Warning をすべて解消して合格させてください。合格できない指摘が残る場合は、その内容をユーザーに報告してください。" >&2
exit 2
