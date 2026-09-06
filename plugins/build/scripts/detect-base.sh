#!/usr/bin/env bash
# detect-base.sh — レビュー差分の比較元(ベースブランチ)を決めて標準出力に出す
#
# 使い方: detect-base.sh [明示ブランチ]
# 決定順:
#   1. 引数で明示されたブランチ
#   2. git config review-loop.base(リポジトリごとの固定設定)
#   3. 現在のブランチに開いている PR のベースブランチ(gh が使える場合)
#   4. develop / main / master のうち、HEAD に最も近い(HEAD までのコミット数が最少の)もの
#   5. 現在のブランチ自体が develop / main / master のときは HEAD(未コミット変更だけが対象)
# 出力はリモート追跡ブランチ(origin/xxx)があればそれを優先する。
set -uo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 1

# ブランチ名を、存在する ref(origin/xxx 優先)に解決する
resolve() {
  local name="$1"
  name="${name#origin/}"
  if git show-ref --verify --quiet "refs/remotes/origin/$name"; then
    echo "origin/$name"
  elif git show-ref --verify --quiet "refs/heads/$name"; then
    echo "$name"
  else
    return 1
  fi
}

CURRENT=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# 1. 明示引数
if [ -n "${1:-}" ]; then
  resolve "$1" && exit 0
  echo "指定されたブランチが見つかりません: $1" >&2
  exit 1
fi

# 2. git config
CFG=$(git config --get review-loop.base 2>/dev/null || true)
if [ -n "$CFG" ]; then
  resolve "$CFG" && exit 0
fi

# 3. 開いている PR のベース
if command -v gh >/dev/null 2>&1 && [ -n "$CURRENT" ] && [ "$CURRENT" != "HEAD" ]; then
  PR_BASE=$(gh pr view "$CURRENT" --json baseRefName -q .baseRefName 2>/dev/null || true)
  if [ -n "$PR_BASE" ]; then
    resolve "$PR_BASE" && exit 0
  fi
fi

# 4. 現在のブランチがトランク自体なら、未コミット変更だけを対象にする
case "$CURRENT" in
  develop|main|master) echo "HEAD"; exit 0 ;;
esac

# 5. HEAD に最も近い候補
BEST=""
BEST_COUNT=""
for b in develop main master; do
  [ "$b" = "$CURRENT" ] && continue
  REF=$(resolve "$b" 2>/dev/null) || continue
  COUNT=$(git rev-list --count "$REF..HEAD" 2>/dev/null) || continue
  if [ -z "$BEST_COUNT" ] || [ "$COUNT" -lt "$BEST_COUNT" ]; then
    BEST="$REF"
    BEST_COUNT="$COUNT"
  fi
done

[ -n "$BEST" ] && { echo "$BEST"; exit 0; }
exit 1
