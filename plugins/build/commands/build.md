---
description: ATDD の red-green ループでタスクを完走させる。テスト計画 → 失敗するテスト(RED) → 実装(GREEN) → 品質レビュー → PR 更新 を、完了条件を機械判定しながら回す
argument-hint: "タスクの説明 [--max-iterations N]"
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, Task, Skill
---

タスクを ATDD(受け入れテスト駆動開発)の手順で完走させてください。引数: $ARGUMENTS(タスクの説明。`--max-iterations N` で周回上限、既定 10)

## まず状態ファイルを作る

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-build.sh" $ARGUMENTS
```
(`${CLAUDE_PLUGIN_ROOT}` が無ければ `find ~/.claude/plugins -path '*/build/*' -name setup-build.sh | head -1`)

これ以降、あなたが作業を終えようとするたびに Stop フックが **客観条件** を確認し、未達なら次のフェーズを指示して続行させます。条件は 3 つ: (1) run-tests.sh の最終結果が exit 0 で、その後コードが変わっていない (2) /review-loop の合格マーカーが現在の差分と一致 (3) PR があれば push 済みで /pr-docs が HEAD に追随。**「終わりました」と言っても条件を満たすまで終われません。** 条件を偽装しない(テストを弱める・skip する・マーカーを手で書く、は禁止)。

## 手順(この順で。飛ばさない)

### 1. PLAN — テスト計画
- `.claude/specs/<ブランチ名のスラッシュを-に置換>.md` が無ければ、Skill ツールで `test-plan:test-plan` を呼び、タスクをテストケース(TC)一覧にする
- 計画はユーザーの承認が必要。承認を待つときは、質問・確認事項を提示した最後に **`<build>PAUSE</build>`** と書いて止まる(フックはこの印を見て止まることを許す)。ユーザーが答えたら再び /build と打たなくてよい。そのまま続きを進める
- 承認済みの計画には「テスト実行: `<コマンド>`」が書かれていること。無ければ確認して追記する

### 2. RED — 失敗するテストを先に書く
- 各 TC に対応するテストを書く。テスト名または docstring に `TC-n` を含める
- `bash <test-plan の scripts>/run-tests.sh` を実行し、**失敗する(exit ≠ 0)ことを確認する**。全部通ってしまうなら、テストが仕様を検証できていないか、既に実装済み。どちらかを見極めてから進む
- この時点で 1 回コミットしてよい(`test: TC-1..n のテストを追加`)

### 3. GREEN — 最小の実装で通す
- テストを通すのに必要な実装だけを書く。先回りした汎用化はしない
- `run-tests.sh` を実行して exit 0 を確認する。落ちていれば直して再実行
- 既存テストも同じコマンドで走る。既存が壊れたら、それは仕様変更か破壊的変更。テストを直す前にユーザーに確認する(`<build>PAUSE</build>`)

### 4. REVIEW — 品質
- Skill ツールで `review-loop:review-loop` を呼ぶ。Critical / Warning を解消して合格させる
- レビューでコードを直したら **run-tests.sh をもう一度実行**する(合格マーカーはコードが変わると無効になる)

### 5. PR — 出荷準備
- コミットして push する
- PR が無ければ `c-create-pr` スキルでドラフト PR を作る(無ければ `gh pr create --draft`)
- Skill ツールで `pr-docs:pr-docs` を呼び、PR 本文と解説コメントを更新する
- `gh pr ready` にはしない(公開はユーザーが決める)

### 6. 報告
テスト計画の TC 一覧と対応テスト、レビュー結果の要約、PR の URL を簡潔に示す。フックが完了を確認するとループは自動で終わる。

## ルール
- 途中でユーザーの判断が要るときは必ず `<build>PAUSE</build>` で止まる。勝手に仕様を決めない
- テスト → 実装 の順を守る。実装を先に書いてからテストを後付けしない
- 最大周回に達したらフックが止める。そのとき未達の条件と残件を正直に報告する
- やめるときは `/cancel-build`
