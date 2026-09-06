#!/usr/bin/env bash
# atdd-stop-hook.sh — /atdd 用 Stop フック
# .claude/atdd.local.md がある間、Claude が止まろうとするたびに完了条件を「客観的に」確認し、
# 未達なら次にやるべきフェーズを指示して止めない(ralph-loop と同じ decision:block 方式)。
#
# 完了条件(すべて .git/ 内のマーカーで判定。Claude の自己申告は使わない):
#   1. テストが緑: claude-tests-last の exit が 0 で、記録された差分ハッシュが現在の差分と一致
#   2. 品質レビュー合格: claude-review-passed が現在の差分ハッシュと一致
#   3. PR が最新: 追跡ファイルに未コミット変更が無く、push 済みで、claude-pr-docs が HEAD と一致
#      (PR が無い・gh が使えない場合は 3 を免除)
# 打ち切り: iteration >= max_iterations
# 一時停止: 直前の Claude の発言に <atdd>PAUSE</atdd> が含まれる(ユーザーへの質問待ち)。状態は残す
set -uo pipefail

INPUT=$(cat)
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
ROOT=$(git rev-parse --show-toplevel)
STATE="$ROOT/.claude/atdd.local.md"
[ -f "$STATE" ] || exit 0

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DIR/events-log.sh"

FM=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE")
val() { echo "$FM" | grep "^$1:" | head -1 | sed "s/^$1:[[:space:]]*//"; }
ITER=$(val iteration); MAX=$(val max_iterations); SBRANCH=$(val branch); SSESSION=$(val session_id); TASK_URL=$(val task_url)
TASK=$(awk '/^---$/{i++; next} i>=2' "$STATE" | grep -m1 '^# 作業リスト:' | sed 's/^# 作業リスト:[[:space:]]*//')
DONE_N=$(grep -c "^- \[x\]" "$STATE" 2>/dev/null || true)
TODO_N=$(grep -c "^- \[ \]" "$STATE" 2>/dev/null || true)

# 別セッション・別ブランチのループには干渉しない
HSESSION=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")
if [ -n "$SSESSION" ] && [ -n "$HSESSION" ] && [ "$SSESSION" != "$HSESSION" ]; then exit 0; fi
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = "$SBRANCH" ] || exit 0

[[ "$ITER" =~ ^[0-9]+$ && "$MAX" =~ ^[0-9]+$ ]] || { echo "atdd: 状態ファイルが壊れています。/cancel-atdd で消してください" >&2; exit 0; }

# 一時停止(ユーザーへの質問待ち)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  LAST=$(grep '"role":"assistant"' "$TRANSCRIPT" | tail -n 100 | jq -rs 'map(.message.content[]? | select(.type=="text") | .text) | last // ""' 2>/dev/null || echo "")
  if echo "$LAST" | grep -q '<atdd>PAUSE</atdd>'; then
    "$LOG" atdd.pause iteration="$ITER" >/dev/null 2>&1 || true
    exit 0
  fi
fi

# --- 完了条件の判定 ---
GIT_DIR=$(git rev-parse --git-dir)
DIFF=$("$DIR/review-diff.sh" 2>/dev/null || true)
HASH=$(printf '%s\n' "$DIFF" | tail -n +2 | sha256sum | cut -d' ' -f1)
BODY=$(printf '%s\n' "$DIFF" | tail -n +2)

SPEC="$ROOT/.claude/specs/${BRANCH//\//-}.md"
HAS_SPEC=false; [ -f "$SPEC" ] && HAS_SPEC=true

TESTS_GREEN=false
if [ -f "$GIT_DIR/claude-tests-last" ]; then
  read -r T_EXIT T_HASH _ < "$GIT_DIR/claude-tests-last"
  [ "$T_EXIT" = "0" ] && [ "$T_HASH" = "$HASH" ] && TESTS_GREEN=true
fi

REVIEWED=false
[ -f "$GIT_DIR/claude-review-passed" ] && [ "$(cat "$GIT_DIR/claude-review-passed")" = "$HASH" ] && REVIEWED=true

PR_OK=true; PR_NUM=""
if command -v gh >/dev/null 2>&1; then
  PR_NUM=$(gh pr view "$BRANCH" --json number,state -q 'select(.state=="OPEN") | .number' 2>/dev/null || echo "")
fi
if [ -n "$PR_NUM" ]; then
  PR_OK=false
  CLEAN=false; [ -z "$(git status --porcelain --untracked-files=no)" ] && CLEAN=true
  UP=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "")
  PUSHED=false; [ -n "$UP" ] && [ "$(git rev-parse HEAD)" = "$(git rev-parse "$UP" 2>/dev/null)" ] && PUSHED=true
  if $CLEAN && $PUSHED && [ -f "$GIT_DIR/claude-pr-docs" ] && [ "$(cat "$GIT_DIR/claude-pr-docs")" = "$PR_NUM $(git rev-parse HEAD)" ]; then
    PR_OK=true
  fi
fi

if [ -n "$BODY" ] && $TESTS_GREEN && $REVIEWED && $PR_OK; then
  rm -f "$STATE"
  "$LOG" atdd.done iterations="$ITER" >/dev/null 2>&1 || true
  echo "✅ atdd: 完了条件をすべて満たしました(テスト緑・レビュー合格・PR 最新)。ループを終了します。"
  exit 0
fi

# --- 打ち切り ---
if [ "$MAX" -gt 0 ] && [ "$ITER" -ge "$MAX" ]; then
  rm -f "$STATE"
  "$LOG" atdd.abort iterations="$ITER" tests_green="$TESTS_GREEN" reviewed="$REVIEWED" pr_ok="$PR_OK" >/dev/null 2>&1 || true
  echo "🛑 atdd: 最大 ${MAX} 周に達しました。未達: tests_green=${TESTS_GREEN} reviewed=${REVIEWED} pr_ok=${PR_OK} 。残件をユーザーに報告して止まります。" >&2
  exit 0
fi

# --- 次のフェーズを決めて続行 ---
NEXT=$((ITER + 1))
sed "s/^iteration: .*/iteration: $NEXT/" "$STATE" > "$STATE.tmp.$$" && mv "$STATE.tmp.$$" "$STATE"

if [ -z "$BODY" ]; then
  PHASE="plan"
  REASON="まだ差分がありません。/atdd の手順に従い、テスト計画(.claude/specs/${BRANCH//\//-}.md)が無ければ test-plan:test-plan スキルで作って承認を得(承認待ちなら <atdd>PAUSE</atdd> と書いて止まる)、承認済みなら RED: 各 TC に対応する失敗するテストを書いて run-tests.sh で失敗を確認してください。"
elif ! $HAS_SPEC; then
  PHASE="plan"
  REASON="テスト計画がありません。test-plan:test-plan スキルで .claude/specs/${BRANCH//\//-}.md を作り、ユーザーの承認を得てください(承認待ちなら <atdd>PAUSE</atdd> と書いて止まる)。"
elif ! $TESTS_GREEN; then
  PHASE="green"
  REASON="テストがまだ緑ではありません(最後の run-tests の結果が失敗、または実行後にコードが変わっています)。テスト計画の各 TC にテストがあることを確認し、無ければ先に失敗するテストを書き(RED)、実装してから test-plan の run-tests.sh を実行して exit 0 を確認してください(GREEN)。テストを弱めたり skip にして通さないこと。"
elif ! $REVIEWED; then
  PHASE="review"
  REASON="テストは緑です。次は review-loop:review-loop スキルで品質レビュー(セキュリティ/パフォーマンス/シンプルさ)を回し、Critical と Warning を解消して合格マーカーを書いてください。修正でコードが変わったら run-tests.sh をもう一度実行してください。"
else
  PHASE="pr"
  REASON="テスト緑・レビュー合格です。変更をコミットして push し、PR が無ければ c-create-pr でドラフト PR を作り、pr-docs:pr-docs スキルで PR 本文と解説コメントを更新してください。"
fi

REASON="$REASON 進めたら .claude/atdd.local.md の作業リストを更新すること(チェック・TC 状況・決めたこと)。フェーズの区切り(PLAN 承認 / RED / GREEN / REVIEW 合格 / PR)では Notion タスク${TASK_URL:+($TASK_URL)}のチェックリスト・進捗ログも書き戻すこと。"
"$LOG" atdd.iteration iteration="$NEXT" phase="$PHASE" tests_green="$TESTS_GREEN" reviewed="$REVIEWED" pr_ok="$PR_OK" >/dev/null 2>&1 || true

jq -n --arg reason "$REASON" --arg msg "🔄 atdd $NEXT/$MAX [$PHASE] tests=$TESTS_GREEN review=$REVIEWED pr=$PR_OK | 作業リスト ${DONE_N}/$((DONE_N+TODO_N)) 完了 | ${TASK:0:60}${TASK_URL:+ | 📎 $TASK_URL}" \
  '{decision:"block", reason:$reason, systemMessage:$msg}'
exit 0
