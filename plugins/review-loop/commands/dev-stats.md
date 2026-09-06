---
description: dev-tools(review-loop / test-plan)の利用状況を集計し、「うまく使えているか」を指標で示す
allowed-tools: Bash, Read, Glob
---

dev-tools の利用状況を集計して報告してください。引数: $ARGUMENTS(日数。省略時は全期間、変更障害率は 30 日。`-f <ログ>` で追加のログを合算、`-r owner/repo` でその期間のマージ済み PR に対するカバー率を出す。複数可)

## 手順

1. スクリプトの場所を特定する: `${CLAUDE_PLUGIN_ROOT}/scripts/dev-tools-stats.sh`。無ければ `find ~/.claude/plugins -path '*review-loop*' -name dev-tools-stats.sh 2>/dev/null | head -1`
2. `bash <script> $ARGUMENTS` を実行する。既定で `~/.claude/dev-tools.log.jsonl`(ローカルの全リポジトリ分)と、カレントリポジトリの `.claude/dev-tools.log.jsonl`(あれば)を合算する
3. 他のリポジトリのログ(Web/リポジトリモードでコミットされているもの)も見たい場合は、`find ~/workspace -maxdepth 4 -name dev-tools.log.jsonl -path '*/.claude/*'` で探し、`-f` で追加して再実行する
4. 結果を以下の観点で **1画面に収まる要約** にして報告する。数字はスクリプトの出力をそのまま使い、計算し直さない:
   - **習慣化**: ゲートのブロック率(下がっていれば良い)、ドラフト作成時にレビュー済みだった割合
   - **品質**: /review-loop の 1周目平均指摘数(下がっていれば良い)、即合格率、未収束回数
   - **仕様担保**: テスト計画のカバー率、計画外の変更が見つかった回数、test-check 合格率
   - **デザイン一致**: /design-check の合格率・平均指摘数・レベル別(L1 静的ばかりならブラウザ MCP の整備を促す)
   - **カバー率**(`-r` 指定時): マージ済み PR のうち review / atdd / pr-docs を通った割合。これが「どれくらい活用されているか」の主指標
   - **気になる点**: 数字から読み取れる改善余地を 1〜3 行(例: ティア 3 の 1 周目指摘が多い → 実装前の /test-plan を徹底)
5. `-r` が指定されていれば、続けて変更障害率も取り、推移に記録する(gh の認証アカウントがそのリポジトリに権限を持つことが前提。権限エラーならその旨を伝えて省略):
   ```bash
   bash <scripts-dir>/change-failure-rate.sh -d <日数> --record -p '^(revert|hotfix)|障害|不具合|緊急|取り消し' <repo...>
   bash <scripts-dir>/change-failure-rate.sh --history
   ```
   報告では「failed(原因 PR が期間内)」と「原因未記載」を分けて示し、原因未記載が多ければ「修正 PR の本文に Caused-by: #n を書く」運用を促す

## ルール

- ログが無い場合はその旨と、記録先(`~/.claude/dev-tools.log.jsonl` またはリポジトリの `.claude/dev-tools.log.jsonl`)を伝える
- 日数を変えて比較したいと言われたら、同じスクリプトを日数違いで 2 回実行して並べる
