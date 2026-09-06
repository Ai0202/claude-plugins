# claude-plugins — Claude Code プラグインマーケットプレイス(dev-tools)

セルフレビュー体制のための Claude Code プラグイン。**「品質の低いコード・仕様を満たさないコードのデプロイを防ぐ」**を目的に、以下を1パッケージで提供します:

- **/plan** — 実装前に受け入れ基準を作成(`.claude/specs/<branch>.md`)。レビューの仕様ソースになる
- **/review-loop** — リスクティア自動判定 → 4観点並列レビュー → 修正 → 再レビューの自律ループ
- **/self-review** — 単発レビュー(修正なし)
- **Stopフックゲート** — レビュー未合格ならタスク完了をブロック
- **計測** — ループ収束ログ(JSONL)+ 変更障害率(CFR)スクリプト

推奨ワークフロー: `/plan で受け入れ基準を承認 → 実装 → タスク完了時にStopフックが /review-loop を強制 → 合格 → PR`。ルールの更新はこのリポジトリだけで行い、ローカル・Web両方に配布されます。

## アーキテクチャ

```
このリポジトリ(ルール本体・更新はここだけ)
  ├─ ローカル: ユーザースコープでインストール → 手元の全リポジトリで有効
  └─ Web: 各リポジトリの .claude/settings.json に約10行のポインタ
          → クラウドセッション開始時に自動インストール
```

## 初回セットアップ

### 0. このリポジトリをGitHubへpush

```bash
cd claude-plugins
# (初回のみ) marketplace.json の owner.name と LICENSE の名義を確認してから:
git init && git add . && git commit -m "init"
gh repo create claude-plugins --public --source . --push
```

`.claude-plugin/marketplace.json` の `owner.name` を自分の名前に書き換えてください。

### 1. ローカル(全リポジトリ・グローバル)

Claude Code内で:

```
/plugin marketplace add Ai0202/claude-plugins
/plugin install review-loop@dev-tools
```

インストール時に **User scope(全プロジェクト)** を選択。これで手元のすべてのリポジトリで /review-loop・/self-review・Stopフックが有効になります。

もし `/plugin install` が「Plugin not found」になる場合(既知の不具合)は、`~/.claude/settings.json` に手動で追記してください:

```json
{
  "extraKnownMarketplaces": {
    "dev-tools": {
      "source": { "source": "github", "repo": "Ai0202/claude-plugins" }
    }
  },
  "enabledPlugins": { "review-loop@dev-tools": true }
}
```

### 2. Web(Claude Code on the Web)

対象リポジトリごとに1回だけ:

```bash
/path/to/claude-plugins/add-to-repo.sh Ai0202/claude-plugins
git add .claude && git commit -m "chore: enable review-loop plugin"
```

これで書き込まれるのはマーケットプレイスへの**ポインタ約10行だけ**です。ルール本体はコピーされないので、以後の更新でリポジトリ側を触る必要はありません。

クラウドセッションはセッション開始時にマーケットプレイスを取得します。パブリックリポジトリなので認証まわりの詰まりはありません。

## ルールの更新方法

1. このリポジトリの `plugins/review-loop/` 配下を編集(観点の追加、ティア基準の変更など)
2. `plugins/review-loop/.claude-plugin/plugin.json` の `version` を上げる(プラグインはversionでキャッシュされるため必須)
3. commit & push

ローカルは `/plugin marketplace update dev-tools`(または自動更新)、Webは次回セッション開始時に新版が取得されます。

## 中身

| パス | 内容 |
|---|---|
| `plugins/review-loop/commands/` | /plan(受け入れ基準作成)、/review-loop(ティア判定つき自律ループ)、/self-review(単発) |
| `plugins/review-loop/agents/` | security / performance / simplicity / spec-compliance の4レビュアー |
| `plugins/review-loop/hooks/hooks.json` | Stopフック: レビュー未合格ならタスク完了をブロック |
| `plugins/review-loop/scripts/` | ログ記録・統計・合格マーカー・Stopゲート・変更障害率(CFR)計測 |

ティア基準・ループ回数・ログの仕組みは `plugins/review-loop/commands/review-loop.md` を参照。

## 動作確認(初回に一度だけ推奨)

プラグイン経由のStopフック(exit 2でのブロック)は過去に不具合報告があったため、初回に1度だけ確認してください: 適当なリポジトリでコードを1行変更するタスクをClaudeに依頼し、完了時にレビューループが強制されるか見る。もし発火しない場合は、`add-to-repo.sh` 適用済みリポジトリの `.claude/settings.json` にStopフックを直接追記するフォールバックが使えます(スクリプトは `find ~/.claude/plugins -name review-stop-gate.sh` で見つかるパスを指定)。

## 計測

```bash
# レビューループ統計(ローカルログ+リポジトリログをマージ)
bash "$(find ~/.claude/plugins -name review-loop-stats.sh 2>/dev/null | head -1)"

# 変更障害率
bash "$(find ~/.claude/plugins -name change-failure-rate.sh 2>/dev/null | head -1)" -d 30 owner/repo
```

よく使うならエイリアス推奨: `alias review-stats='bash $(find ~/.claude/plugins -name review-loop-stats.sh | head -1)'`
