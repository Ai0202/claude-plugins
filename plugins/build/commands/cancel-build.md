---
description: 進行中の /build ループを止める(状態ファイルを消す)
allowed-tools: Bash
---

進行中の /build を止めてください。

```bash
ROOT=$(git rev-parse --show-toplevel) && rm -f "$ROOT/.claude/build.local.md" && echo "build を停止しました"
```

停止後、どこまで進んでいたか(テスト計画の有無、テストの状態、レビュー合格の有無、PR の有無)を 3 行以内で報告する。
