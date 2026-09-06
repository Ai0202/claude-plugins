#!/usr/bin/env bash
# review-diff.sh — レビュー対象の差分(ベースとの分岐点以降のコミット + 未コミット変更)を出す
#
# 使い方: review-diff.sh [--stat] [ベースブランチ]
#   --stat  ファイル単位のサマリだけを出す
# 先頭行に "# base: <ref>" を付けるので、比較元をそのまま確認できる。
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
git diff $STAT "$MB"
