#!/usr/bin/env bash
# add-to-repo.sh — このマーケットプレイスへの「ポインタ」を対象リポジトリに書き込む
# (Claude Code on the Web 対応。ルール本体はコピーしない)
#
# 使い方: 対象リポジトリのルートで
#   /path/to/claude-plugins/add-to-repo.sh <owner/marketplace-repo>
# 例:
#   add-to-repo.sh myname/claude-plugins
set -euo pipefail

[ $# -eq 1 ] || { echo "Usage: $0 <owner/marketplace-repo>" >&2; exit 1; }
MARKETPLACE_REPO="$1"

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

echo ""
echo "次のステップ: git add .claude && git commit -m 'chore: enable dev-tools plugins'"
