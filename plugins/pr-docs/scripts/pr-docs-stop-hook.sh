#!/usr/bin/env bash
# pr-docs-stop-hook.sh — Stop フック
# 「作業が一区切りついて push 済み、かつ PR が開いている」のに PR の説明が最新コミットに
# 追いついていないとき、一度だけ止めて /pr-docs の実行を指示する。
#
# 一区切りの判定(すべて満たすときだけ動く。作業途中では邪魔しない):
#   - 追跡ファイルに未コミットの変更が無い
#   - HEAD が upstream(origin の同名ブランチ)に push 済み
#   - 現在のブランチに OPEN な PR がある(gh が使えること)
#   - .git/claude-pr-docs に記録された「最後に説明を更新したコミット」が HEAD と違う
set -uo pipefail

INPUT=$(cat)

# 既にブロック済みなら止めない(無限ループ防止)
if command -v jq >/dev/null 2>&1; then
  ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
else
  echo "$INPUT" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && ACTIVE="true" || ACTIVE="false"
fi
[ "$ACTIVE" = "true" ] && exit 0

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0

# 作業途中(未コミットの変更あり)なら何もしない
[ -z "$(git status --porcelain --untracked-files=no 2>/dev/null)" ] || exit 0

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
case "$BRANCH" in ""|HEAD|main|master|develop) exit 0 ;; esac

# push 済みか
UPSTREAM=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "")
[ -n "$UPSTREAM" ] || exit 0
HEAD_SHA=$(git rev-parse HEAD)
[ "$HEAD_SHA" = "$(git rev-parse "$UPSTREAM" 2>/dev/null)" ] || exit 0

# OPEN な PR があるか(gh の認証アカウントにリポジトリ権限が無い場合はここで抜ける)
PR_JSON=$(gh pr view "$BRANCH" --json number,state,url 2>/dev/null) || exit 0
PR_STATE=$(echo "$PR_JSON" | jq -r '.state // ""')
PR_NUM=$(echo "$PR_JSON" | jq -r '.number // ""')
[ "$PR_STATE" = "OPEN" ] && [ -n "$PR_NUM" ] || exit 0

# 最後に説明を更新したコミットと同じなら止めない
MARKER="$(git rev-parse --git-dir)/claude-pr-docs"
if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$PR_NUM $HEAD_SHA" ]; then
  exit 0
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/events-log.sh" pr_docs.prompt pr="$PR_NUM" >/dev/null 2>&1 || true

echo "PR #${PR_NUM} の説明が最新のコミット(${HEAD_SHA:0:7})に追いついていません。タスクを終える前に /pr-docs を実行して、(1) 実装内容から PR のタイトル・本文をテンプレートに沿って書き直し、(2) 主要な変更箇所に新卒向けの解説を PR 上のインラインコメントとして付けてください。ユーザーへの質問で止まる場合は、その質問だけを再提示して止まって構いません。" >&2
exit 2
