#!/usr/bin/env bash
# setup-build.sh — /build の状態ファイルを作る(このファイルがある間だけ Stop フックがループを回す)
# 使い方: setup-build.sh [--max-iterations N] [タスクの説明...]
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
  echo "幹ブランチ($BRANCH)では /build を始められません。先に作業ブランチを切ってください" >&2; exit 1 ;;
esac

STATE="$ROOT/.claude/build.local.md"
mkdir -p "$ROOT/.claude"
if [ -f "$STATE" ]; then
  echo "既に /build が進行中です($STATE)。続きから再開します。やり直すなら /cancel-build を先に実行してください"
  exit 0
fi

SESSION="${CLAUDE_SESSION_ID:-}"
cat > "$STATE" <<EOF
---
branch: $BRANCH
session_id: $SESSION
iteration: 0
max_iterations: $MAX
started: $(date -u +%Y-%m-%dT%H:%M:%SZ)
---
${TASK_PARTS[*]:-}
EOF

# 状態ファイルを誤ってコミットしないようにする
if ! git check-ignore -q "$STATE" 2>/dev/null; then
  echo ".claude/build.local.md" >> "$ROOT/.git/info/exclude"
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/events-log.sh" build.start max_iterations="$MAX" >/dev/null 2>&1 || true
echo "/build を開始しました(最大 $MAX 周)。状態: $STATE"
