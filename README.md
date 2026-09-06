# claude-plugins — Claude Code プラグインマーケットプレイス(dev-tools)

**「品質の低いコード・仕様を満たさないコードが PR に出るのを防ぐ」** ための Claude Code プラグイン集。

| プラグイン | コマンド | 役割 |
|---|---|---|
| **review-loop** | `/review-loop` `/self-review` | コード品質。security / performance / simplicity の3観点で並列レビューし、修正まで自動で回す。PR をレビュー可能にする瞬間をゲートする |
| **test-plan** | `/test-plan` `/test-check` | 仕様担保。実装前にテスト計画を作り、実装後に「計画どおりのテストが存在・実行・合格しているか」を突合する |

2つは独立していて、片方だけ入れても動く。接点は `.claude/specs/<branch>.md`(テスト計画)と `.git/` 内の合格マーカーだけ。

## 推奨ワークフロー

```
/test-plan   … タスクをテストケース一覧に落として承認(任意)
   ↓
実装         … 途中の往復・ドラフト PR(gh pr create --draft)・push は自由
   ↓
/test-check  … 計画の各 TC にテストがあり、実行して通ることを確認(計画があるブランチのみ)
/review-loop … 3観点の品質レビュー → 修正 → 再レビューを自動反復
   ↓
gh pr ready  … ここでゲートがマーカーを確認。未合格なら止めて /review-loop(/test-check)を指示
```

ゲートが止めるのは **`gh pr ready` と `--draft` 無しの `gh pr create`** だけ。合格後に1行でもコードを変えると差分のハッシュが変わり、再度レビューが必要になる。

## アーキテクチャ

```
このリポジトリ(ルール本体・更新はここだけ)
  ├─ ローカル: ユーザースコープでインストール → 手元の全リポジトリで有効
  └─ Web: 各リポジトリの .claude/settings.json に約10行のポインタ
          → クラウドセッション開始時に自動インストール
```

## 初回セットアップ

### 1. ローカル(全リポジトリ・グローバル)

Claude Code内で:

```
/plugin marketplace add Ai0202/claude-plugins
/plugin install review-loop@dev-tools
/plugin install test-plan@dev-tools
```

インストール時に **User scope(全プロジェクト)** を選択。

`/plugin install` が「Plugin not found」になる場合(既知の不具合)は、`~/.claude/settings.json` に手動で追記する:

```json
{
  "extraKnownMarketplaces": {
    "dev-tools": {
      "source": { "source": "github", "repo": "Ai0202/claude-plugins" }
    }
  },
  "enabledPlugins": { "review-loop@dev-tools": true, "test-plan@dev-tools": true }
}
```

### 2. Web(Claude Code on the Web)

対象リポジトリごとに1回だけ:

```bash
/path/to/claude-plugins/add-to-repo.sh Ai0202/claude-plugins
git add .claude && git commit -m "chore: enable dev-tools plugins"
```

書き込まれるのはマーケットプレイスへのポインタ約10行と、空のログファイル `.claude/dev-tools.log.jsonl` だけ。ルール本体はコピーされない。

## レビュー差分の比較元(ベースブランチ)

対象は「比較元ブランチとの分岐点以降のコミット + 未コミット変更」。比較元は次の順で自動判定する:

1. コマンド引数(`/self-review develop` など)
2. `git config review-loop.base <branch>`(リポジトリごとに固定したいとき)
3. 現在ブランチに開いている PR のベースブランチ(`gh` が使える場合)
4. 現在のブランチ自体が develop / main / master なら HEAD(未コミット変更だけが対象)
5. `develop` / `main` / `master` のうち HEAD に最も近いもの

各コマンドは最初に `# base: ...` と変更ファイル一覧を表示する。手元で差分だけ見るとき:

```bash
bash "$(find ~/.claude/plugins -path '*review-loop*' -name review-diff.sh | head -1)" --stat
```

## レビュアーのモデルを変える

`plugins/review-loop/agents/*.md` の frontmatter に `model:` を書くと、その検査員だけ別モデルで動く:

```yaml
---
name: security-reviewer
model: opus        # sonnet / haiku / opus / inherit
tools: Read, Grep, Glob, Bash
---
```

Claude 以外(例: Codex MCP)に任せたい観点は、その agent の本文を「差分を `mcp__codex__codex` に渡して所見をもらい、同じ出力フォーマットに整形する」内容に書き換え、`tools:` に MCP ツール名を追加する。観点ごとに混在できる。

## 利用状況の計測

すべてのコマンドとゲートがイベントを JSONL に1行ずつ記録する。記録先は `DEV_TOOLS_LOG` → リポジトリの `.claude/dev-tools.log.jsonl`(あれば) → `~/.claude/dev-tools.log.jsonl`。

| イベント | いつ | 主なフィールド |
|---|---|---|
| `review.round` | /review-loop の各ラウンド | run_id, round, tier, critical, warning, info, verdict |
| `review.pass` | /review-loop 合格 | diff_lines |
| `self_review.result` | /self-review | critical, warning, info, verdict |
| `test_plan.created` | /test-plan | cases |
| `test_check.result` | /test-check | planned, covered, unplanned, verdict |
| `gate.pass` / `gate.block` | gh pr ready / create | action, reason(review / tests), has_test_plan |

集計:

```bash
# 利用状況(ゲート通過率・レビュー収束・テスト計画カバー率)
bash "$(find ~/.claude/plugins -path '*review-loop*' -name dev-tools-stats.sh | head -1)" [日数]

# 変更障害率(hotfix / revert ラベルの PR 比率)
bash "$(find ~/.claude/plugins -path '*review-loop*' -name change-failure-rate.sh | head -1)" -d 30 owner/repo
```

「うまく使えているか」の読み方:

- **ゲートのブロック率が下がる** → レビューしてから PR に出す習慣がついている
- **1周目の平均指摘数が下がる** → 最初から品質の高いコードを書けている
- **テスト計画のカバー率が高く、計画外の変更が少ない** → 仕様どおりに作れている
- **変更障害率が下がる** → 上の3つが実際の障害減少につながっている(最終的な成果指標)

## ルールの更新方法

1. `plugins/<name>/` 配下を編集する
2. その `plugin.json` の `version` を上げる(プラグインはversionでキャッシュされるため必須)
3. commit & push
4. ローカルは `/plugin marketplace update dev-tools`、Web は次回セッション開始時に新版が取得される

## 中身

| パス | 内容 |
|---|---|
| `.claude-plugin/marketplace.json` | プラグイン一覧(ここに追記していく) |
| `add-to-repo.sh` | Web 用に対象リポジトリへポインタを書き込む |
| `plugins/review-loop/commands/` | /review-loop(ティア判定つき自律ループ)、/self-review(単発・修正なし) |
| `plugins/review-loop/agents/` | security / performance / simplicity の3レビュアー |
| `plugins/review-loop/hooks/hooks.json` | PreToolUse(Bash)フック: PR をレビュー可能にするコマンドをゲート |
| `plugins/review-loop/scripts/` | 比較元判定・差分取得・ゲート・合格マーカー・イベントログ・集計・変更障害率 |
| `plugins/test-plan/commands/` | /test-plan(計画作成)、/test-check(突合・実行確認) |
| `plugins/test-plan/scripts/` | 比較元判定・差分取得・テスト合格マーカー・イベントログ(review-loop と同じものを同梱) |

ティア基準・ループ回数は `plugins/review-loop/commands/review-loop.md` を参照。
