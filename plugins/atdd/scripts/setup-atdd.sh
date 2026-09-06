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
if [ -f "$STATE" ]; then
  echo "既に /atdd が進行中です($STATE)。作業リストを読んで続きから再開してください。やり直すなら /cancel-atdd を先に実行してください"
  exit 0
fi

SESSION="${CLAUDE_SESSION_ID:-}"
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
