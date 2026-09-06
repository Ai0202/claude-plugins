---
description: 変更差分を4観点(セキュリティ/パフォーマンス/シンプルさ/仕様・ルール準拠)で並列セルフレビューする
allowed-tools: Bash, Read, Grep, Glob, Task
---

現在の変更差分に対してセルフレビューを実施してください。引数: $ARGUMENTS(比較元ブランチ。省略時は自動判定)

## 手順

1. まずレビュー対象の差分を特定する(スクリプトの探索順: `${CLAUDE_PLUGIN_ROOT}/scripts/` → `find ~/.claude/plugins -name review-diff.sh 2>/dev/null | head -1`):
   - `<scripts-dir>/review-diff.sh --stat $ARGUMENTS` で比較元(先頭行 `# base: ...`)と変更ファイル一覧を取得し、**そのまま最初にユーザーへ提示する**(比較元の取り違えに気づけるように)
   - 比較元は 引数 → `git config review-loop.base` → 現在ブランチの PR のベース → develop / main / master のうち HEAD に最も近いもの の順で決まる
   - `<scripts-dir>/review-diff.sh $ARGUMENTS` で全文差分(分岐点以降のコミット + 未コミット変更)を取得する
   - 差分がゼロならその旨を伝えて終了する

2. 以下の4つのサブエージェントを **並列で** 起動し、それぞれに差分と関連ファイルパスを渡す:
   - security-reviewer(セキュリティ)
   - performance-reviewer(パフォーマンス)
   - simplicity-reviewer(シンプルさ・設計)
   - spec-compliance-reviewer(仕様・プロジェクトルール準拠)

3. 各エージェントの結果を統合し、以下のフォーマットで最終レポートを出力する:

```
# セルフレビュー結果(比較元: <base> / 変更ファイル N 件)

## 🔴 Critical(リリースブロッカー)
- [観点] ファイル:行 — 指摘内容と修正案

## 🟡 Warning(修正推奨)
...

## 🔵 Info(検討事項)
...

## ✅ 確認済みで問題なかった点
(各観点で「見たが問題なし」と判断された主要ポイントを簡潔に)

## 判定: リリース可 / 修正後リリース可 / リリース不可
```

## ルール

- Critical が1件でもあれば判定は「リリース不可」とする
- 指摘には必ずファイル名・該当箇所・具体的な修正案をセットで付ける
- 重複する指摘は統合する
- 差分に含まれないコードへの一般論的な指摘はしない(ただし差分が既存コードに与える影響は指摘対象)
