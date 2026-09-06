#!/usr/bin/env bash
# add-to-repo.sh — このマーケットプレイスへの「ポインタ」を対象リポジトリに書き込む
# (Claude Code on the Web 対応。ルール本体はコピーしない)
#
# 使い方: 対象リポジトリのルートで
#   /path/to/claude-plugins/add-to-repo.sh [--only-me] <owner/marketplace-repo>
# 例:
#   add-to-repo.sh --only-me myname/claude-plugins
# --only-me: .claude/dev-tools.json に自分(gh ログイン名・git のメール・名前)だけを書き、
#            フックとゲートを自分限定にする。同僚の Claude Code にはプラグインが入るが、フックは素通りになる
set -euo pipefail

ONLY_ME=false
ARGS=()
for a in "$@"; do case "$a" in --only-me) ONLY_ME=true ;; *) ARGS+=("$a") ;; esac; done
[ ${#ARGS[@]} -eq 1 ] || { echo "Usage: $0 [--only-me] <owner/marketplace-repo>" >&2; exit 1; }
MARKETPLACE_REPO="${ARGS[0]}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "リポジトリのルートで実行してください" >&2; exit 1; }
cd "$(git rev-parse --show-toplevel)"
mkdir -p .claude

SNIPPET=$(cat << JSON
{
  "extraKnownMarketplaces": {
    "dev-tools": {
      "source": {
        "source": "github",
        "repo": "${MARKETPLACE_REPO}"
      }
    }
  },
  "enabledPlugins": {
    "review-loop@dev-tools": true,
    "test-plan@dev-tools": true,
    "pr-docs@dev-tools": true,
    "atdd@dev-tools": true
  }
}
JSON
)

if [ ! -f .claude/settings.json ]; then
  echo "$SNIPPET" > .claude/settings.json
  echo "作成: .claude/settings.json"
elif command -v jq >/dev/null 2>&1; then
  TMP=$(mktemp)
  jq -s '.[0] * .[1]' .claude/settings.json <(echo "$SNIPPET") > "$TMP" && mv "$TMP" .claude/settings.json
  echo "マージ: .claude/settings.json"
else
  echo ".claude/settings.json が既に存在します。以下を手動でマージしてください:"
  echo "$SNIPPET"
  exit 0
fi

# Webサンドボックスでのログ永続化先
touch .claude/dev-tools.log.jsonl

# 自分限定
if $ONLY_ME; then
  ME=()
  L=$(gh api user -q .login 2>/dev/null || true); [ -n "$L" ] && ME+=("$L")
  E=$(git config --get user.email 2>/dev/null || true); [ -n "$E" ] && ME+=("$E")
  N=$(git config --get user.name 2>/dev/null || true); [ -n "$N" ] && ME+=("$N")
  [ ${#ME[@]} -gt 0 ] || { echo "自分を特定できません(gh ログインか git config user.email が必要)" >&2; exit 1; }
  printf '%s\n' "${ME[@]}" | jq -R . | jq -s '{users: .}' > .claude/dev-tools.json
  echo "作成: .claude/dev-tools.json(フック・ゲートは次のユーザーだけ有効: ${ME[*]})"
fi

echo ""
echo "次のステップ: git add .claude && git commit -m 'chore: enable dev-tools plugins'"
