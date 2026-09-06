---
description: ATDD(受け入れテスト駆動開発)でタスクを完走させる。チケット/タスク説明/PR を入力に、仕様の詰め → テスト計画 → 失敗するテスト(RED) → 実装(GREEN) → 品質レビュー → PR 更新 を、完了条件を機械判定しながら回す
argument-hint: "<チケットURL | PR番号/URL | タスクの説明> [--max-iterations N]"
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, Task, Skill
---

タスクを ATDD の手順で完走させてください。引数: $ARGUMENTS

## 0. 入力を読む

引数の種類で入口が変わる。どれも「何を作るか」の一次情報として扱い、会話の記憶で補わない。

| 引数 | 読み方 |
|---|---|
| PR 番号 / PR の URL | `gh pr view <n> --json title,body,baseRefName,headRefName,url` と `gh pr diff <n>`。そのブランチに checkout していなければ `gh pr checkout <n>` |
| Notion / Slack / GitHub Issue の URL | 使える MCP(Notion, Slack)や `gh issue view` で本文と要件を取得する |
| 文章 | そのままタスクの説明として使う |
| 無し | `.claude/atdd.local.md` があれば **再開**(下の「再開」)。無ければユーザーに何を作るか聞く |

## 1. 状態ファイル(作業リスト)を作る

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-atdd.sh" $ARGUMENTS
```
(`${CLAUDE_PLUGIN_ROOT}` が無ければ `find ~/.claude/plugins -path '*/atdd/*' -name setup-atdd.sh | head -1`)

作成される `.claude/atdd.local.md` の本文が **作業リスト** になる。ここに以下を書き、**各ステップを終えるたびに更新する**(チェックを付ける、TC を足す、決めたことを 1 行残す)。セッションが途中で切れても、次のセッションが `/atdd` と打つだけでここから再開できるようにするため。

```markdown
# 作業リスト: <タスク名>
入力: <チケット URL / PR / 説明の要約 1 行>

## 進行
- [ ] PLAN: 仕様の詰め(grill-me)
- [ ] PLAN: テスト計画の承認 → .claude/specs/<branch>.md
- [ ] RED: TC ごとの失敗するテスト
- [ ] GREEN: 実装
- [ ] REVIEW: /review-loop 合格
- [ ] PR: push → ドラフト PR → /pr-docs

## TC 状況
- [ ] TC-1 <内容> — テスト: <ファイル> / 状態: red|green
...

## 決めたこと・メモ(1 行ずつ、日時つき)
- 2026-09-06 16:40 CSV の文字コードは UTF-8 BOM 付きにする(ユーザー確認済み)
```

これ以降、あなたが作業を終えようとするたびに Stop フックが **客観条件** を確認し、未達なら次のフェーズを指示して続行させます。条件は 3 つ: (1) run-tests.sh の最終結果が exit 0 で、その後コードが変わっていない (2) /review-loop の合格マーカーが現在の差分と一致 (3) PR があれば push 済みで /pr-docs が HEAD に追随。**「終わりました」と言っても条件を満たすまで終われません。** 条件を偽装しない(テストを弱める・skip する・マーカーを手で書く、は禁止)。

## 2. PLAN — 仕様を詰めてテスト計画にする

1. **仕様の詰め**: `grill-me` 系のスキル(例: `mattpocock-skills:grill-me`)が使えるなら Skill ツールで呼び、入力に対して「曖昧な点・境界・やらないこと」をユーザーに問い詰めて固める。無ければ test-plan の質問ルール(成否に関わる不明点だけ、最大 3 問)で代用する
2. **テスト計画**: Skill ツールで `test-plan:test-plan` を呼び、`.claude/specs/<branch>.md` を作る。**テストの配分はトロフィー型**(test-plan 側のルールに従う): 結合テストを主力、純粋ロジックだけ単体、E2E は happy path 1〜2 本
3. 承認を待つときは、質問・確認事項を提示した最後に **`<atdd>PAUSE</atdd>`** と書いて止まる。ユーザーが答えたら再び /atdd と打たなくてよい。そのまま続ける
4. 作業リストの PLAN にチェックを付け、TC 状況を埋める

## 3. RED — 失敗するテストを先に書く

- 各 TC に対応するテストを書く。テスト名または docstring に `TC-n` を含める
- `bash <test-plan の scripts>/run-tests.sh` を実行し、**失敗する(exit ≠ 0)ことを確認する**。全部通ってしまうなら、テストが仕様を検証できていないか、既に実装済み。どちらかを見極めてから進む
- この時点で 1 回コミットしてよい(`test: TC-1..n のテストを追加`)。作業リストの TC 状況を red に更新

## 4. GREEN — 最小の実装で通す

- テストを通すのに必要な実装だけを書く。先回りした汎用化はしない
- `run-tests.sh` を実行して exit 0 を確認する。落ちていれば直して再実行。TC ごとに green になったら作業リストを更新
- 既存テストも同じコマンドで走る。既存が壊れたら、それは仕様変更か破壊的変更。テストを直す前にユーザーに確認する(`<atdd>PAUSE</atdd>`)
- E2E(happy path)を Playwright で書いた場合、Playwright MCP が使えるなら実際にブラウザで通し、その様子を GIF に残す(`.claude/e2e/<branch>/<TC>.gif`。パスを作業リストに書く。PR には画像を API で添付できないので、ユーザーが必要なら手で貼る)

## 5. REVIEW — 品質

- Skill ツールで `review-loop:review-loop` を呼ぶ。Critical / Warning を解消して合格させる
- レビューでコードを直したら **run-tests.sh をもう一度実行**する(合格マーカーはコードが変わると無効になる)

## 6. PR — 出荷準備

- コミットして push する
- PR が無ければ `c-create-pr` スキルでドラフト PR を作る(無ければ `gh pr create --draft`)
- Skill ツールで `pr-docs:pr-docs` を呼び、PR 本文と解説コメントを更新する
- `gh pr ready` にはしない(公開はユーザーが決める)

## 7. 報告

作業リストの最終状態(TC 一覧と対応テスト)、レビュー結果の要約、PR の URL、E2E の GIF があればそのパスを簡潔に示す。フックが完了を確認するとループは自動で終わる。

## 再開(引数なしで /atdd、または新しいセッション)

1. `.claude/atdd.local.md` を読み、作業リストの未チェック項目と「決めたこと」を把握する
2. `.git/` のマーカーで現状を確かめる: `run-tests.sh` を 1 回実行(テストの現状)、`git status` / `git log <base>..HEAD --oneline`(コードの現状)
3. 作業リストの最初の未チェック項目から続ける。記憶に頼らず、ファイルとマーカーを信じる

## ルール

- 途中でユーザーの判断が要るときは必ず `<atdd>PAUSE</atdd>` で止まる。勝手に仕様を決めない
- テスト → 実装 の順を守る。実装を先に書いてからテストを後付けしない
- 作業リストはステップごとに更新する。まとめて最後に書かない
- 最大周回に達したらフックが止める。そのとき未達の条件と残件を正直に報告する
- やめるときは `/cancel-atdd`
