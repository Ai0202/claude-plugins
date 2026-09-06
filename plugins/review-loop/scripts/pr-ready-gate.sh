#!/usr/bin/env bash
# pr-ready-gate.sh — PreToolUse(Bash) フック用ゲート
# PR を「レビュー可能な状態」にするコマンドだけを止める:
#   - gh pr create(--draft / -d が付いていないもの)
#   - gh pr ready
#   - gh pr create --draft は git config review-loop.gate-draft=true のときだけ
# git push・その他のコマンドは素通し。ドラフト作成は止めなくても「レビュー済みだったか」を記録する。
#
# 通す条件: 現在の差分ハッシュがレビュー合格マーカーと一致していること。
# さらに .claude/specs/<branch>.md(テスト計画)があるブランチでは、テスト合格マーカーの一致も必要。
set -uo pipefail

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
else
  CMD=$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')
fi
[ -n "$CMD" ] || exit 0

# --- 対象コマンドの判定 ---
ACTION=""
if echo "$CMD" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+ready([[:space:]]|$)'; then
  ACTION="pr.ready"
elif echo "$CMD" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'; then
  if echo "$CMD" | grep -Eq '(^|[[:space:]])(--draft|-d)([[:space:]=]|$)'; then
    ACTION="pr.draft"
  else
    ACTION="pr.create"
  fi
fi
[ -n "$ACTION" ] || exit 0

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DIR/events-log.sh"

DIFF=$("$DIR/review-diff.sh" 2>/dev/null) || exit 0
BASE_LINE=$(printf '%s\n' "$DIFF" | head -1)
BODY=$(printf '%s\n' "$DIFF" | tail -n +2)
[ -z "$BODY" ] && exit 0
HASH=$(printf '%s\n' "$BODY" | sha256sum | cut -d' ' -f1)

GIT_DIR=$(git rev-parse --git-dir)
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
SPEC=".claude/specs/${BRANCH//\//-}.md"
REVIEW_MARKER="$GIT_DIR/claude-review-passed"
REVIEWED=false
[ -f "$REVIEW_MARKER" ] && [ "$(cat "$REVIEW_MARKER")" = "$HASH" ] && REVIEWED=true

# --- ドラフト作成: 既定では止めない(レビュー済みかどうかだけ記録)。
#     git config review-loop.gate-draft true のリポジトリではドラフトもゲートする ---
if [ "$ACTION" = "pr.draft" ] && [ "$(git config --get review-loop.gate-draft 2>/dev/null || echo false)" != "true" ]; then
  "$LOG" gate.pass action="$ACTION" reviewed="$REVIEWED" has_test_plan="$([ -f "$SPEC" ] && echo true || echo false)" >/dev/null 2>&1 || true
  exit 0
fi

# --- レビュー合格 ---
if [ "$REVIEWED" != "true" ]; then
  "$LOG" gate.block action="$ACTION" reason=review >/dev/null 2>&1 || true
  echo "PR をレビュー可能にする前に品質レビューが必要です(${BASE_LINE#\# })。/review-loop を実行して Critical と Warning を解消し、合格してから再度 '$CMD' を実行してください。" >&2
  exit 2
fi

# --- テスト計画があるブランチはテスト合格も必要 ---
if [ -f "$SPEC" ]; then
  TEST_MARKER="$GIT_DIR/claude-tests-passed"
  if [ ! -f "$TEST_MARKER" ] || [ "$(cat "$TEST_MARKER")" != "$HASH" ]; then
    "$LOG" gate.block action="$ACTION" reason=tests >/dev/null 2>&1 || true
    echo "テスト計画 ($SPEC) があるブランチです。/test-check を実行して計画どおりのテストが通ることを確認してから再度 '$CMD' を実行してください。" >&2
    exit 2
  fi
fi

"$LOG" gate.pass action="$ACTION" reviewed=true has_test_plan="$([ -f "$SPEC" ] && echo true || echo false)" >/dev/null 2>&1 || true
exit 0
