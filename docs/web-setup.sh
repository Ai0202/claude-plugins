#!/usr/bin/env bash
# Claude Code on the Web の「環境設定 → セットアップスクリプト」に貼る内容。
# リポジトリには何も足さず、サンドボックスの ~/.claude/ に個人設定だけを書いて dev-tools を有効にする。
# 公開リポジトリ(Ai0202/claude-plugins)だけを参照するのでトークンは不要。
set -euo pipefail

mkdir -p "$HOME/.claude"
S="$HOME/.claude/settings.json"
[ -f "$S" ] || echo '{}' > "$S"

# マーケットプレイスの参照と有効化するプラグインを user 設定に合成する(既存の設定は残す)
if command -v jq >/dev/null 2>&1; then
  jq '.extraKnownMarketplaces["dev-tools"] = {source:{source:"github", repo:"Ai0202/claude-plugins"}}
      | .enabledPlugins["review-loop@dev-tools"] = true
      | .enabledPlugins["test-plan@dev-tools"]   = true
      | .enabledPlugins["pr-docs@dev-tools"]     = true
      | .enabledPlugins["atdd@dev-tools"]        = true' "$S" > "$S.tmp" && mv "$S.tmp" "$S"
else
  cat > "$S" <<'JSON'
{
  "extraKnownMarketplaces": { "dev-tools": { "source": { "source": "github", "repo": "Ai0202/claude-plugins" } } },
  "enabledPlugins": { "review-loop@dev-tools": true, "test-plan@dev-tools": true, "pr-docs@dev-tools": true, "atdd@dev-tools": true }
}
JSON
fi

# 開発作業の入口ルール(ローカルの ~/.claude/CLAUDE.md と同じ内容。公開して困らない部分だけ)
cat >> "$HOME/.claude/CLAUDE.md" <<'MD'

## 開発作業の入口（dev-tools）
- コード変更を伴う依頼（機能追加・改修・バグ修正・「実装して」「直して」、チケット / PR / Notion タスクの URL）は `atdd:atdd` スキル（`/atdd`）を入口にする。test-plan / review-loop / pr-docs は /atdd の中から呼ばれる。
- 小さな修正は /atdd がサイズ S と判定して手順を薄くする。
- 「atdd なしで」「さっと直して」と言われたときだけ /atdd を使わない。
MD

echo "dev-tools: user settings written to $S"
