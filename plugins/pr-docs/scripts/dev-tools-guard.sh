#!/usr/bin/env bash
# dev-tools-guard.sh — フック・ゲートを「許可された人だけ」に限定する
#
# リポジトリに .claude/dev-tools.json があり "users" が書かれていれば、現在のユーザーが
# その一覧に含まれるときだけ exit 0(有効)。含まれなければ exit 1(素通り)。
# ファイルが無ければ全員有効(個人リポジトリなどの既定)。
#
# ユーザーの特定(順に試す。ローカルでも Web サンドボックスでも動くように):
#   1. 環境変数 DEV_TOOLS_USER
#   2. git config user.email / user.name
#   3. gh api user -q .login(結果は /tmp にキャッシュ)
# 一覧には GitHub ログイン名・メールアドレス・git の user.name のどれを書いてもよい。
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
CFG="$ROOT/.claude/dev-tools.json"
[ -f "$CFG" ] || exit 0

if command -v jq >/dev/null 2>&1; then
  USERS=$(jq -r '.users // [] | .[]' "$CFG" 2>/dev/null)
else
  USERS=$(grep -o '"[^"]*"' "$CFG" | tr -d '"' | grep -v '^users$')
fi
[ -n "$USERS" ] || exit 0

CANDIDATES=()
[ -n "${DEV_TOOLS_USER:-}" ] && CANDIDATES+=("$DEV_TOOLS_USER")
E=$(git config --get user.email 2>/dev/null || true); [ -n "$E" ] && CANDIDATES+=("$E")
# GitHub の noreply メール(12345+login@users.noreply.github.com)からログイン名も候補にする
case "$E" in *@users.noreply.github.com) CANDIDATES+=("$(echo "${E%@*}" | sed 's/^[0-9]*+//')") ;; esac
N=$(git config --get user.name 2>/dev/null || true); [ -n "$N" ] && CANDIDATES+=("$N")

match() { while IFS= read -r u; do [ -n "$u" ] && [ "$u" = "$1" ] && return 0; done <<<"$USERS"; return 1; }
for c in "${CANDIDATES[@]:-}"; do [ -n "$c" ] && match "$c" && exit 0; done

# gh のログイン名(遅いのでキャッシュ)
if command -v gh >/dev/null 2>&1; then
  CACHE="/tmp/dev-tools-gh-login.$(id -u)"
  if [ -f "$CACHE" ] && [ -n "$(find "$CACHE" -mmin -60 2>/dev/null)" ]; then
    LOGIN=$(cat "$CACHE")
  else
    LOGIN=$(gh api user -q .login 2>/dev/null || true)
    [ -n "$LOGIN" ] && echo "$LOGIN" > "$CACHE"
  fi
  [ -n "${LOGIN:-}" ] && match "$LOGIN" && exit 0
fi
exit 1
