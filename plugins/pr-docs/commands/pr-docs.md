---
description: 実装内容から PR のタイトル・本文をテンプレートに沿って書き直し、Before/After の図(ERD・シーケンス・クラス・フロー)つきの新卒向け解説を PR のコメントとして 1 つ付ける(2回目以降は同じコメントを更新)
allowed-tools: Bash, Read, Grep, Glob, Skill
---

現在のブランチの PR を、実際にコミットされた内容に合わせて仕上げてください。引数: $ARGUMENTS(PR 番号。省略時は現在のブランチの PR)

やることは 2 つ。**(1) PR のタイトル・本文の書き直し**、**(2) Before/After の図つき新卒向け解説を PR コメントで 1 つ**。コードは一切変更しない。

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

### 3. 新卒向け解説を PR のコメントとして 1 つ付ける
読者は「このリポジトリに入ったばかりで、この変更の背景を知らない新卒エンジニア」。diff の行に付けるインラインコメントではなく、**PR の会話欄(Conversation)に 1 つのコメント**として書く。ソースコードにも書かない。

**内容(図が主、文は従)**。先頭に `<!-- pr-docs -->` と `## 📘 新卒向け解説` を置く。文章部分は合計 20 行以内、図は必要な種類だけ:

「何をする PR か」の要約は書かない(PR 本文に既にある)。図から始める。

1. **図**(Mermaid、必要な種類だけ。各図に見出しを付ける)。差分を読んで、**構造が変わったもの** を選ぶ:

   | 変更の種類 | 図 | Mermaid |
   |---|---|---|
   | 画面→API→外部サービス→DB の往復や順序が変わった | シーケンス図 | `sequenceDiagram` |
   | テーブル・カラム・リレーションの追加/変更(migration、model) | ERD | `erDiagram` |
   | 分岐・処理の流れが変わった(条件追加、経路変更) | フローチャート | `flowchart LR` |
   | (必要なときだけ)クラス・型・モジュールの関係が主題の変更 | クラス図 | `classDiagram` |

   - 該当する種類が無ければその図は描かない。変更に関係ない図を埋めるために描かない
   - 構造が **変わった** ものは **Before / After を横に並べる**(見出し `Before` `After` の 2 ブロック)。Before が存在しない(新規)なら After だけ
   - 変更した要素は太線や色(`style X stroke-width:3px` / `classDef changed fill:#fde68a`)で強調し、触っていない要素は薄く、または省く
   - 1 図のノード・エンティティは 8 個以内。図の中の文字は短く(1 ノード 10 文字程度)。詳細は「読む順番」に書く
2. **読む順番**(3〜5 行): `ファイルパス — 1 行でこのファイルの役割と、今回どこが変わったか`。入口から出口の順に並べる
3. **注意**(0〜3 行): 壊れやすい前提、外部システムの制約、あわせて見るべき既存コード

書き方のルール:
- 差分に無いことを書かない。分からないことは書かない(埋めない)
- 専門用語は初出で一言添える。ただし幼稚にはしない

**既存のコメントがあれば更新する(増やさない)**:
```bash
# 自分が前回付けたコメントを探す
gh api repos/{owner}/{repo}/issues/<n>/comments --paginate \
  --jq '.[] | select(.body | startswith("<!-- pr-docs -->")) | .id' | head -1
```
- 見つかった → `gh api -X PATCH repos/{owner}/{repo}/issues/comments/<id> -F body=@<tmpfile.md>` で本文を差し替える
- 見つからない → `gh pr comment <n> --body-file <tmpfile.md>` で新規投稿する

本文は必ず一時ファイル経由で渡す(ヒアドキュメントだと Mermaid のバッククォートや特殊文字で壊れる)。

### 4. 記録
`<scripts-dir>/mark-pr-docs.sh <n> 1` を実行する。これで Stop フックが同じコミットに対して再度促さなくなる。

### 5. 報告
PR の URL、書き直した欄、解説コメントの URL(新規 / 更新 のどちらか)を簡潔に示す。

## ルール
- ソースファイルに説明コメントを追加しない(変更の経緯・理由はコードコメントに書かない、というユーザーのルールに従う)
- コードを変更しない。コミットも push もしない
- 差分から確認できないことを本文に書かない。分からない欄は「要確認」と書く
- 人が書いたコメント・レビューには触れない
