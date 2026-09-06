#!/usr/bin/env bash
# Claude Code on the Web の「環境設定 → セットアップスクリプト」に貼る内容。
# リポジトリには何も足さず、サンドボックスの ~/.claude/ に個人設定だけを書いて dev-tools を有効にする。
# dev-tools は公開リポジトリ(Ai0202/claude-plugins)だけを参照するのでトークン不要。
# 個人スキル(private の Ai0202/dotfiles)も入れたい場合だけ、環境変数 DOTFILES_TOKEN を設定する。
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

# --- 個人スキル・CLAUDE.md(private の dotfiles リポジトリから) ---
# Web の環境設定で環境変数 DOTFILES_TOKEN に、Ai0202/dotfiles の Contents: Read だけを許可した
# fine-grained PAT を入れておく。無ければこの部分は飛ばし、dev-tools だけ有効になる。
if [ -n "${DOTFILES_TOKEN:-}" ]; then
  rm -rf /tmp/dotfiles
  if git clone -q --depth 1 "https://x-access-token:${DOTFILES_TOKEN}@github.com/Ai0202/dotfiles.git" /tmp/dotfiles 2>/dev/null; then
    for d in skills commands templates; do
      [ -d "/tmp/dotfiles/.claude/$d" ] && rm -rf "$HOME/.claude/$d" && cp -R "/tmp/dotfiles/.claude/$d" "$HOME/.claude/$d"
    done
    [ -f /tmp/dotfiles/.claude/CLAUDE.md ] && cp /tmp/dotfiles/.claude/CLAUDE.md "$HOME/.claude/CLAUDE.md"
    rm -rf /tmp/dotfiles
    echo "dotfiles: skills/commands/templates/CLAUDE.md copied"
  else
    echo "dotfiles: clone failed (token?) — 個人スキルは無しで続行" >&2
  fi
fi

# 開発作業の入口ルール(dotfiles の CLAUDE.md に既に入っていれば重複させない)
grep -q '開発作業の入口' "$HOME/.claude/CLAUDE.md" 2>/dev/null || cat >> "$HOME/.claude/CLAUDE.md" <<'MD'

## 開発作業の入口（dev-tools）
- コード変更を伴う依頼（機能追加・改修・バグ修正・「実装して」「直して」、チケット / PR / Notion タスクの URL）は `atdd:atdd` スキル（`/atdd`）を入口にする。test-plan / review-loop / pr-docs は /atdd の中から呼ばれる。
- 小さな修正は /atdd がサイズ S と判定して手順を薄くする。
- 「atdd なしで」「さっと直して」と言われたときだけ /atdd を使わない。
MD

echo "dev-tools: user settings written to $S"
