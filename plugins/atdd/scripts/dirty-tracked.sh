#!/usr/bin/env bash
# dirty-tracked.sh — 追跡ファイルのうち未コミットの変更があるものを git status --porcelain 形式で出す
# git config dev-tools.ignoreDirty(複数指定可・リポジトリ直下からの glob)に当たるファイルは数えない。
# 開発サーバーの起動などで毎回書き換わり、コミットしない生成ファイルを外すために使う。
#   例: git config --add dev-tools.ignoreDirty 'frontend/app/vite.config.ts'
set -uo pipefail

EXCLUDES=()
while IFS= read -r pattern; do
  [ -n "$pattern" ] && EXCLUDES+=(":(top,exclude,glob)$pattern")
done < <(git config --get-all dev-tools.ignoreDirty 2>/dev/null)

git status --porcelain --untracked-files=no -- ':/' ${EXCLUDES[@]+"${EXCLUDES[@]}"} 2>/dev/null
