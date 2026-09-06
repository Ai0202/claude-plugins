#!/usr/bin/env bash
# setup-atdd.sh — /atdd の状態ファイルを作る(このファイルがある間だけ Stop フックがループを回す)
# 使い方: setup-atdd.sh [--max-iterations N] [タスクの説明...]
set -euo pipefail

MAX=10
TASK_PARTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --max-iterations) MAX="$2"; shift 2 ;;
    *) TASK_PARTS+=("$1"); shift ;;
  esac
done
[[ "$MAX" =~ ^[0-9]+$ ]] || { echo "--max-iterations は整数で指定してください" >&2; exit 1; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "gitリポジトリ内で実行してください" >&2; exit 1; }
ROOT=$(git rev-parse --show-toplevel)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
case "$BRANCH" in main|master|develop)
  echo "幹ブランチ($BRANCH)では /atdd を始められません。先に作業ブランチを切ってください" >&2; exit 1 ;;
esac

STATE="$ROOT/.claude/atdd.local.md"
mkdir -p "$ROOT/.claude"
SESSION="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"

# 再開: 状態ファイルがあれば、このセッションに引き継いで作業リストを表示する
if [ -f "$STATE" ]; then
  SBRANCH=$(sed -n '/^---$/,/^---$/{ /^branch:/{ s/^branch:[[:space:]]*//; p; } }' "$STATE" | head -1)
  if [ -n "$SBRANCH" ] && [ "$SBRANCH" != "$BRANCH" ]; then
    echo "進行中の /atdd はブランチ $SBRANCH のものです(現在: $BRANCH)。git checkout $SBRANCH してから再実行するか、/cancel-atdd で破棄してください" >&2
    exit 1
  fi
  if [ -n "$SESSION" ]; then
    sed "s/^session_id: .*/session_id: $SESSION/" "$STATE" > "$STATE.tmp.$$" && mv "$STATE.tmp.$$" "$STATE"
  fi
  DIR="$(cd "$(dirname "$0")" && pwd)"
  "$DIR/events-log.sh" atdd.resume >/dev/null 2>&1 || true
  echo "進行中の /atdd を再開します(状態: $STATE)。作業リスト:"
  awk '/^---$/{i++; next} i>=2' "$STATE"
  echo ""
  echo "未チェックの最初の項目から続けてください。やり直すなら /cancel-atdd"
  exit 0
fi
TASK="${TASK_PARTS[*]:-}"
cat > "$STATE" <<EOF
---
branch: $BRANCH
session_id: $SESSION
iteration: 0
max_iterations: $MAX
started: $(date -u +%Y-%m-%dT%H:%M:%SZ)
---
# 作業リスト: ${TASK:-(未記入)}
入力: ${TASK:-(未記入)}

## 進行
- [ ] PLAN: 仕様の詰め(grill-me)
- [ ] PLAN: テスト計画の承認 → .claude/specs/${BRANCH//\//-}.md
- [ ] RED: TC ごとの失敗するテスト
- [ ] GREEN: 実装
- [ ] REVIEW: /review-loop 合格
- [ ] PR: push → ドラフト PR → /pr-docs

## TC 状況
(テスト計画の承認後に TC-n を列挙する)

## 決めたこと・メモ(1 行ずつ、日時つき)
EOF

# 状態ファイルを誤ってコミットしないようにする
if ! git check-ignore -q "$STATE" 2>/dev/null; then
  echo ".claude/atdd.local.md" >> "$ROOT/.git/info/exclude"
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/events-log.sh" atdd.start max_iterations="$MAX" >/dev/null 2>&1 || true
echo "/atdd を開始しました(最大 $MAX 周)。状態: $STATE"
