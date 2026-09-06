---
description: 実装内容から PR のタイトル・本文をテンプレートに沿って書き直し、主要な変更箇所に新卒向けの解説を PR 上のインラインコメントとして付ける
allowed-tools: Bash, Read, Grep, Glob, Skill
---

現在のブランチの PR を、実際にコミットされた内容に合わせて仕上げてください。引数: $ARGUMENTS(PR 番号。省略時は現在のブランチの PR)

やることは 2 つ。**(1) PR のタイトル・本文の書き直し**、**(2) 新卒向け解説のインラインコメント**。コードは一切変更しない。

## 手順

### 0. 対象を確定する
- `gh pr view $ARGUMENTS --json number,url,title,body,baseRefName,headRefName,isDraft,state` で PR を取得する。無ければ「PR がありません(ドラフトで作るなら c-create-pr)」と伝えて終了する
- `git branch --show-current` が headRefName と一致することを確認する。違えば作業ツリーが別ブランチなので止めてユーザーに報告する
- スクリプトの場所: `${CLAUDE_PLUGIN_ROOT}/scripts/`。無ければ `find ~/.claude/plugins -path '*pr-docs*' -name mark-pr-docs.sh 2>/dev/null | head -1` の dirname
- 前回の追随位置: `cat "$(git rev-parse --git-dir)/claude-pr-docs"`(`<PR番号> <sha>`)。あればその sha 以降が「今回新しく説明すべき範囲」。無ければ `<base>...HEAD` 全体

### 1. 一次情報を読む
```bash
git log --oneline <base>..HEAD
git diff --stat <base>...HEAD
git diff <base>...HEAD
```
記憶や会話の印象で書かない。**差分に無いことは書かない**。

### 2. PR のタイトル・本文を書き直す
- ユーザー環境に `c-refresh-pr` スキルがあれば、それを Skill ツールで呼ぶ(**コミットの squash はしない**。このコマンドは説明の更新だけが目的)
- 無ければ自前で行う:
  - `.github/PULL_REQUEST_TEMPLATE.md`(または `.github/pull_request_template.md`、`docs/pull_request_template.md`)を読み、その見出し構成を守る
  - 既存本文のうち人が書いた欄(チェックボックスの状態、動作確認の記録、レビュアーへの依頼)は残し、「変更内容」「背景」「影響範囲」など実装から導ける欄だけを書き直す
  - タイトルはリポジトリの慣習(prefix、チケット番号)に合わせる。`git log` の既存 PR タイトルや CLAUDE.md を参考にする
  - `gh pr edit <n> --title "<title>" --body-file <tmpfile>` で反映する(本文はヒアドキュメントではなく一時ファイル経由。特殊文字で壊れないように)

### 3. 新卒向け解説をインラインコメントで付ける
読者は「このリポジトリに入ったばかりで、この変更の背景を知らない新卒エンジニア」。ソースコードにコメントを書き込むのではなく、**PR の diff 上に GitHub のレビューコメントとして**付ける。

- 対象は PR 全体の差分(`<base>...HEAD`)から、**3〜8 箇所**を選ぶ: 入口(ハンドラ・ルート・コマンド)、非自明な分岐やロジック、外部システムの制約が理由の書き方、変更した既存関数。2 回目以降は前回の追随位置以降で変わった箇所を優先する
- 各コメントは 5 行以内。「ここは何をしているか / なぜ必要か / 読むときの注意(壊れやすい前提、関連ファイル)」の順。先頭に `📘 解説:` を付ける

**既存の解説コメントは増やさず更新する**(2 回目以降)。まず自分が付けた解説を取得する:
```bash
gh api repos/{owner}/{repo}/pulls/<n>/comments --paginate \
  --jq '.[] | select(.body | startswith("📘")) | {id, path, line, original_line, body}'
```
取得した各コメントを次のように扱う:
- その `path` の該当箇所が今回の差分にまだあり、内容が変わっていない → そのまま残す(何もしない)
- 該当箇所のコードが変わった、または説明を直したい → 本文を書き直して **同じコメントを更新** する: `gh api -X PATCH repos/{owner}/{repo}/pulls/comments/<id> -f body=@<tmpfile>`
- 該当箇所が差分から消えた(`line` が null になっている = outdated) → **削除** する: `gh api -X DELETE repos/{owner}/{repo}/pulls/comments/<id>`
- 新しく説明が必要になった箇所だけを新規に投稿する

新規分は 1 回の API 呼び出しでまとめて投稿する(通知が 1 通で済む)。`event` は `COMMENT`(承認や修正要求にはしない):

```bash
gh api -X POST repos/{owner}/{repo}/pulls/<n>/reviews --input <tmpfile.json>
# tmpfile.json: {"commit_id":"<HEAD sha>","event":"COMMENT","body":"📘 新卒向けの読み方メモを付けました",
#   "comments":[{"path":"app/foo.py","line":42,"side":"RIGHT","body":"📘 解説: ..."}]}
```
`line` は **変更後ファイルの行番号**(diff の `+` 側)。削除行に付けたい場合は `side` を `LEFT` にする。行が diff に含まれていないと API がエラーになるので、`git diff` のハンク範囲内の行だけを選ぶ。

### 4. 記録
`<scripts-dir>/mark-pr-docs.sh <n> <解説コメントの総数(新規+更新+据え置き)>` を実行する。これで Stop フックが同じコミットに対して再度促さなくなる。

### 5. 報告
PR の URL、書き直した欄、解説の箇所一覧(ファイル:行 と一言。新規 / 更新 / 削除 を区別)を簡潔に示す。

## ルール
- ソースファイルに説明コメントを追加しない(変更の経緯・理由はコードコメントに書かない、というユーザーのルールに従う)
- コードを変更しない。コミットも push もしない
- 差分から確認できないことを本文に書かない。分からない欄は「要確認」と書く
- 既存のインラインコメント(人のレビュー)には触れない
