#!/usr/bin/env bash
# review-diff.sh — レビュー対象の差分(ベースとの分岐点以降のコミット + 未コミット変更 + 未追跡ファイル)を出す
#
# 使い方: review-diff.sh [--stat] [ベースブランチ]
#   --stat  ファイル単位のサマリだけを出す
# 先頭行に "# base: <ref>" を付けるので、比較元をそのまま確認できる。
# 未追跡(untracked)の新規ファイルも差分に含める(.gitignore 対象は除く)。
set -uo pipefail

STAT=""
BASE_ARG=""
for a in "$@"; do
  case "$a" in
    --stat) STAT="--stat" ;;
    *) BASE_ARG="$a" ;;
  esac
done

DIR="$(cd "$(dirname "$0")" && pwd)"
BASE=$("$DIR/detect-base.sh" "$BASE_ARG") || { echo "ベースブランチを判定できません(develop/main/master が無い)。引数で指定してください" >&2; exit 1; }

MB=$(git merge-base "$BASE" HEAD 2>/dev/null) || { echo "merge-base を計算できません: $BASE" >&2; exit 1; }

echo "# base: $BASE ($(git rev-parse --short "$MB"))"
ROOT=$(git rev-parse --show-toplevel)
# 計測ログとループの状態ファイルは差分に含めない(追記のたびにハッシュが変わるのを防ぐ)
EXCL=(':(exclude,top).claude/dev-tools.log.jsonl' ':(exclude,top).claude/*.local.md')
git diff $STAT "$MB" -- . "${EXCL[@]}"
git -C "$ROOT" ls-files --others --exclude-standard -z -- . "${EXCL[@]}" | while IFS= read -r -d '' f; do
  git -C "$ROOT" diff --no-index $STAT -- /dev/null "$f" 2>/dev/null || true
done
exit 0
