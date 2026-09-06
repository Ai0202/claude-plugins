#!/usr/bin/env bash
# run-tests.sh — テストを実行し、結果(終了コード・そのときの差分ハッシュ)を .git/ に記録する
# /build の Stop フックはこの記録を「テストが緑か」の客観判定に使う。
#
# 使い方: run-tests.sh [テストコマンド...]
#   引数省略時は .claude/specs/<branch>.md の「テスト実行: `<cmd>`」行を使い、
#   それも無ければ package.json の test スクリプト / pytest / go test を推定する。
# 記録先: <git-dir>/claude-tests-last = "<exit> <diff-hash> <ISO時刻> <コマンド>"
set -uo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "gitリポジトリ内で実行してください" >&2; exit 1; }
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT=$(git rev-parse --show-toplevel)
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
SPEC="$ROOT/.claude/specs/${BRANCH//\//-}.md"

CMD="$*"
if [ -z "$CMD" ] && [ -f "$SPEC" ]; then
  CMD=$(grep -E '^テスト実行:' "$SPEC" | head -1 | sed -E 's/^テスト実行:[[:space:]]*`?([^`/]*)`?.*/\1/' | sed -E 's/[[:space:]]+$//')
fi
if [ -z "$CMD" ]; then
  if [ -f "$ROOT/package.json" ] && jq -e '.scripts.test' "$ROOT/package.json" >/dev/null 2>&1; then
    CMD="npm test --silent"
  elif [ -f "$ROOT/pytest.ini" ] || [ -f "$ROOT/pyproject.toml" ] || [ -f "$ROOT/setup.cfg" ] || [ -f "$ROOT/manage.py" ]; then
    CMD="pytest -q"
  elif [ -f "$ROOT/go.mod" ]; then
    CMD="go test ./..."
  else
    echo "テストコマンドを判定できません。引数で指定するか、テスト計画に「テスト実行: \`<cmd>\`」を書いてください" >&2
    exit 1
  fi
fi

echo "# run-tests: $CMD"
( cd "$ROOT" && bash -c "$CMD" )
EXIT=$?

DIFF=$("$DIR/review-diff.sh" 2>/dev/null || true)
HASH=$(printf '%s\n' "$DIFF" | tail -n +2 | sha256sum | cut -d' ' -f1)
echo "$EXIT $HASH $(date -u +%Y-%m-%dT%H:%M:%SZ) $CMD" > "$(git rev-parse --git-dir)/claude-tests-last"
"$DIR/events-log.sh" tests.run exit="$EXIT" >/dev/null 2>&1 || true

if [ "$EXIT" -eq 0 ]; then echo "# run-tests: PASS (exit 0)"; else echo "# run-tests: FAIL (exit $EXIT)"; fi
exit "$EXIT"
