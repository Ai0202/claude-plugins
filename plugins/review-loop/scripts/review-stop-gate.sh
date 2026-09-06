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
BASE=""
for b in main master; do
  git show-ref --verify --quiet "refs/heads/$b" && BASE="$b" && break
done

{
  [ -n "$BASE" ] && git diff "${BASE}...HEAD" 2>/dev/null
  git diff HEAD 2>/dev/null
} > /tmp/claude-review-diff.$$ 2>/dev/null

# --- ガード3: 差分がなければ止めない ---
if [ ! -s /tmp/claude-review-diff.$$ ]; then
  rm -f /tmp/claude-review-diff.$$
  exit 0
fi

HASH=$(sha256sum /tmp/claude-review-diff.$$ | cut -d' ' -f1)
rm -f /tmp/claude-review-diff.$$

MARKER="$(git rev-parse --git-dir)/claude-review-passed"

# --- 合格マーカーが現在の差分と一致していれば止めない ---
if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$HASH" ]; then
  exit 0
fi

# --- ブロック: レビューループを指示 ---
echo "コード変更に対してレビューループが未合格です。タスクを完了する前に /review-loop を実行し、Critical と Warning をすべて解消して合格させてください。合格できない指摘が残る場合は、その内容をユーザーに報告してください。" >&2
exit 2
