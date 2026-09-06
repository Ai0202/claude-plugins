---
description: ATDD(受け入れテスト駆動開発)でタスクを完走させる。チケット/タスク説明/PR を入力に、Notion タスクを司令塔として 仕様の詰め → 設計・ADR → テスト計画 → 失敗するテスト(RED) → 実装(GREEN) → 品質レビュー → PR 更新 を、完了条件を機械判定しながら回す
argument-hint: "<NotionタスクURL | PR番号/URL | チケットURL | タスクの説明> [--max-iterations N]"
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, Task, Skill
---

タスクを ATDD の手順で完走させてください。引数: $ARGUMENTS

**正式な記録は Notion のタスクページ**(設計・ADR・テスト計画・チェックリスト・PR リンク・進捗ログ)。ローカルの `.claude/atdd.local.md` はフックが機械判定に使う作業状態で、Notion の写しです。リポジトリをまたぐタスクは同じ Notion タスクを共有し、リポジトリごとに /atdd を回します。

## 0. 入力を読む

| 引数 | 読み方 |
|---|---|
| Notion タスクの URL | そのページが司令塔。本文(設計・チェックリスト・関連 PR)を読み、続きから |
| PR 番号 / PR の URL | `gh pr view <n> --json title,body,baseRefName,headRefName,url` と `gh pr diff <n>`。必要なら `gh pr checkout <n>`。本文に Notion リンクがあればそのタスクを使う |
| Slack / GitHub Issue などの URL | MCP や `gh issue view` で本文と要件を取得 |
| 文章 | そのままタスクの説明 |
| 無し | `.claude/atdd.local.md` があれば **再開**(末尾)。無ければ何を作るか聞く |

## 1. Notion タスクを確保する(register-task)

Notion タスク URL を受け取っていなければ、Skill ツールで `register-task` を呼ぶ(重複チェック → プロジェクトの Tasks DB に作成 → task-hub の start まで含む)。既存タスクが見つかればそれを使う。ステータスを「進行中」にする。

得られた URL で状態ファイルを作る:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-atdd.sh" --task-url <NotionURL> $ARGUMENTS
```
(`${CLAUDE_PLUGIN_ROOT}` が無ければ `find ~/.claude/plugins -path '*/atdd/*' -name setup-atdd.sh | head -1`)

`.claude/atdd.local.md` の本文が作業リスト。**各ステップを終えるたびに更新する**(チェック、TC 状況、決めたこと 1 行)。

これ以降、あなたが作業を終えようとするたびに Stop フックが **客観条件** を確認し、未達なら次のフェーズを指示して続行させます。条件は 3 つ: (1) run-tests.sh の最終結果が exit 0 で、その後コードが変わっていない (2) /review-loop の合格マーカーが現在の差分と一致 (3) PR があれば push 済みで /pr-docs が HEAD に追随。**「終わりました」と言っても条件を満たすまで終われません。** 条件を偽装しない(テストを弱める・skip する・マーカーを手で書く、は禁止)。

## Notion タスクページの構成(本文をこの見出しで揃える)

無い見出しは作り、ある見出しは **中身を置き換える**(進捗ログだけ追記)。Notion MCP の `notion-fetch` で現状を読み、`notion-update-page` で書く。

```
## 概要            入力の要約 1〜3 行、元チケット / 依頼のリンク
## 設計            grill-me で固めた仕様、構成(Mermaid 可)、影響範囲、やらないこと
## ADR             決定ごとに: 日付 / 背景 / 決定 / 却下した案 / 結果・影響(1 決定 5〜10 行)
## テスト計画      .claude/specs の TC 一覧(層・状態 red|green)
## チェックリスト  リポジトリごとに: PLAN / RED / GREEN / REVIEW / PR のチェック
## 関連 PR         リポジトリ: PR URL(ドラフト/レビュー中/マージ済)
## 進捗ログ        日時 + 1 行(フェーズ境界で追記)
```

**書き戻すタイミング**(毎ステップではなく区切りだけ。MCP 呼び出しを抑える):

| 区切り | 書き戻す内容 |
|---|---|
| PLAN 承認後 | 概要・設計・ADR・テスト計画・チェックリスト(このリポジトリの行)、ログ |
| RED 完了 | テスト計画の状態(red)、チェック、ログ |
| GREEN 完了 | テスト計画の状態(green)、チェック、ログ |
| REVIEW 合格 | チェック、ログ(指摘数と対応) |
| PR 作成/更新 | 関連 PR、チェック、ログ |

Notion MCP が使えないときは止まらず続行し、作業リストの「決めたこと」に `Notion 未同期: <区切り>` と残す。次に使えるようになった区切りでまとめて書き戻す。

## 2. PLAN — 仕様を詰め、設計と ADR を書き、テスト計画にする

1. **仕様の詰め**: `grill-me` 系スキル(例: `mattpocock-skills:grill-me`)が使えるなら Skill ツールで呼び、曖昧な点・境界・やらないことをユーザーに問い詰めて固める。無ければ test-plan の質問ルール(成否に関わる不明点だけ、最大 3 問)で代用
2. **設計**: 固まった仕様を「設計」節の形に整理する。構成が変わるなら Mermaid で描く
3. **ADR**: 構造・方針・外部依存・データ形式など後から覆すと高くつく決定があれば、決定ごとに「ADR」節に書く。些細な実装判断は書かない(作業リストの「決めたこと」で足りる)
4. **テスト計画**: Skill ツールで `test-plan:test-plan` を呼び、`.claude/specs/<branch>.md` を作る。配分はトロフィー型(結合が主力、単体は純粋ロジック、E2E は happy path 1〜2 本)
5. 承認を待つときは、質問・確認事項の最後に **`<atdd>PAUSE</atdd>`** と書いて止まる。答えが来たらそのまま続ける
6. 承認後に Notion へ書き戻し(上の表)、作業リストの PLAN にチェック、TC 状況を埋める

## 3. RED — 失敗するテストを先に書く

- 各 TC に対応するテストを書く。テスト名または docstring に `TC-n` を含める
- `bash <test-plan の scripts>/run-tests.sh` で **失敗する(exit ≠ 0)ことを確認**。全部通るなら、テストが仕様を検証できていないか既に実装済み。見極めてから進む
- 1 回コミットしてよい(`test: TC-1..n のテストを追加`)。作業リストと Notion を更新

## 4. GREEN — 最小の実装で通す

- テストを通すのに必要な実装だけ書く。先回りした汎用化はしない
- `run-tests.sh` で exit 0 を確認。落ちていれば直して再実行。TC ごとに green になったら作業リストを更新
- 既存テストが壊れたら仕様変更か破壊的変更。テストを直す前にユーザーに確認(`<atdd>PAUSE</atdd>`)
- E2E(happy path)を Playwright で書いた場合、Playwright MCP が使えるならブラウザで通し、GIF を `.claude/e2e/<branch>/<TC>.gif` に残す(パスを作業リストへ。PR には API で画像を添付できないので、必要ならユーザーが手で貼る)
- 完了時に Notion を更新

## 5. REVIEW — 品質

- Skill ツールで `review-loop:review-loop` を呼び、Critical / Warning を解消して合格させる
- レビューで直したら **run-tests.sh をもう一度実行**(合格マーカーはコードが変わると無効)
- 合格時に Notion を更新(指摘数と対応の要約をログに)

## 6. PR — 出荷準備

- コミットして push
- PR が無ければ `c-create-pr` スキルでドラフト PR を作る(無ければ `gh pr create --draft`)。PR 本文に Notion タスクのリンクを入れる
- Skill ツールで `pr-docs:pr-docs` を呼び、PR 本文と解説コメントを更新
- Notion の「関連 PR」に追加し、チェックとログを更新。`gh pr ready` にはしない(公開はユーザーが決める)。ステータスの「完了」への変更もユーザー(マージ後)

## 7. 報告

Notion タスクの URL、TC 一覧と対応テスト、レビュー結果の要約、PR の URL、E2E の GIF パスを簡潔に示す。フックが完了を確認するとループは自動で終わる。

## 再開

- **引数なし** `/atdd`: `.claude/atdd.local.md` を読み、未チェックの最初の項目から。`run-tests.sh` を 1 回、`git status` / `git log <base>..HEAD` で現状を確かめてから着手
- **Notion URL** `/atdd <URL>`: ローカルの状態ファイルが無い(Web サンドボックスや別マシン)場合、Notion の「チェックリスト」「テスト計画」「関連 PR」から状態ファイルを作り直して続きから
- どちらも記憶に頼らず、ファイル・マーカー・Notion を信じる

## ルール

- ユーザーの判断が要るときは必ず `<atdd>PAUSE</atdd>` で止まる。勝手に仕様を決めない
- テスト → 実装 の順を守る。実装を先に書いてテストを後付けしない
- 作業リストはステップごと、Notion は区切りごとに更新する。まとめて最後に書かない
- 最大周回に達したらフックが止める。未達の条件と残件を正直に報告する
- やめるときは `/cancel-atdd`(Notion は消さない)
