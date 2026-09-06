#!/usr/bin/env bash
# dev-tools-stats.sh — dev-tools(review-loop / test-plan)の利用状況を集計する
# 使い方: dev-tools-stats.sh [-f ログファイル] [日数(省略時は全期間)]
# デフォルトでは ~/.claude/dev-tools.log.jsonl と、カレントのリポジトリ内
# .claude/dev-tools.log.jsonl の両方をマージして集計する
set -euo pipefail

LOGS=()
if [ "${1:-}" = "-f" ]; then
  LOGS=("$2"); shift 2
else
  [ -f "${HOME}/.claude/dev-tools.log.jsonl" ] && LOGS+=("${HOME}/.claude/dev-tools.log.jsonl")
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/.claude/dev-tools.log.jsonl" ] && LOGS+=("$REPO_ROOT/.claude/dev-tools.log.jsonl")
fi
[ ${#LOGS[@]} -gt 0 ] || { echo "ログがまだありません"; exit 0; }

DAYS="${1:-}"
if [ -n "$DAYS" ]; then
  SINCE=$(date -u -d "-${DAYS} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"${DAYS}"d +%Y-%m-%dT%H:%M:%SZ)
  DATA=$(cat "${LOGS[@]}" | jq -c --arg since "$SINCE" 'select(.ts >= $since)')
  echo "== dev-tools 利用状況(過去 ${DAYS} 日)=="
else
  DATA=$(cat "${LOGS[@]}")
  echo "== dev-tools 利用状況(全期間)=="
fi
[ -n "$DATA" ] || { echo "対象期間のログがありません"; exit 0; }

r1() { jq -n --argjson v "$1" '$v * 10 | round / 10'; }

echo ""
echo "== 1. ゲート(PR をレビュー可能にする瞬間)=="
echo "  ブロック率が下がる = 「レビューしてから PR」が習慣化している"
echo "$DATA" | jq -s '
  [.[] | select(.event | startswith("gate."))] as $g |
  ($g | length) as $n |
  {
    "試行回数": $n,
    "通過": ([$g[] | select(.event=="gate.pass")] | length),
    "ブロック(レビュー未合格)": ([$g[] | select(.event=="gate.block" and .reason=="review")] | length),
    "ブロック(テスト未確認)": ([$g[] | select(.event=="gate.block" and .reason=="tests")] | length),
    "ブロック率(%)": (if $n>0 then (([$g[] | select(.event=="gate.block")] | length) / $n * 100 | round) else null end),
    "通過時にテスト計画があった割合(%)": (([$g[] | select(.event=="gate.pass")] | length) as $p |
      if $p>0 then (([$g[] | select(.event=="gate.pass" and .has_test_plan==true)] | length) / $p * 100 | round) else null end)
  }'

echo ""
echo "== 2. 品質レビュー(/review-loop)=="
echo "  1 周目の指摘数が減る = 最初から品質の高いコードを書けている"
echo "$DATA" | jq -s '
  [.[] | select(.event=="review.round")] | group_by(.run_id) | map({
    run_id: .[0].run_id, repo: .[0].repo, tier: (.[0].tier // "-"), rounds: length,
    first_issues: (sort_by(.round) | .[0] | (.critical + .warning)),
    final_issues: (sort_by(.round) | .[-1] | (.critical + .warning)),
    final_verdict: (sort_by(.round) | .[-1].verdict)
  }) as $runs | ($runs | length) as $n |
  if $n == 0 then "実行なし" else {
    "ループ実行回数": $n,
    "総ラウンド数": ([$runs[].rounds] | add),
    "平均ラウンド数/実行": (([$runs[].rounds] | add) / $n * 10 | round / 10),
    "1ラウンドで即合格した割合(%)": (([$runs[] | select(.rounds == 1 and .final_verdict == "pass")] | length) / $n * 100 | round),
    "最大ラウンドでも未収束の回数": ([$runs[] | select(.final_verdict == "max-rounds-reached")] | length),
    "平均指摘数(1周目, Critical+Warning)": (([$runs[].first_issues] | add) / $n * 10 | round / 10),
    "平均指摘数(最終, Critical+Warning)": (([$runs[].final_issues] | add) / $n * 10 | round / 10)
  } end'

echo ""
echo "== ティア別 =="
echo "$DATA" | jq -s -r '
  [.[] | select(.event=="review.round")] | group_by(.run_id) | map({tier: (.[0].tier // "-"), rounds: length,
    first: (sort_by(.round) | .[0] | (.critical + .warning))}) |
  if length == 0 then "  (なし)" else
  group_by(.tier) | map("  tier \(.[0].tier): 実行 \(length) 回 / 平均 \((([.[].rounds] | add) / length * 10 | round / 10)) ラウンド / 1周目平均指摘 \((([.[].first] | add) / length * 10 | round / 10)) 件") | .[] end'

echo ""
echo "== 3. テスト計画(/test-plan → /test-check)=="
echo "  カバー率が高く、計画外の変更が少ない = 仕様どおりに作れている"
echo "$DATA" | jq -s '
  ([.[] | select(.event=="test_plan.created")]) as $p |
  ([.[] | select(.event=="test_check.result")]) as $c |
  {
    "計画作成数": ($p | length),
    "平均テストケース数/計画": (if ($p|length)>0 then (([$p[].cases] | add) / ($p|length) * 10 | round / 10) else null end),
    "test-check 実行数": ($c | length),
    "合格率(%)": (if ($c|length)>0 then (([$c[] | select(.verdict=="pass")] | length) / ($c|length) * 100 | round) else null end),
    "平均カバー率(%)": (if ($c|length)>0 then (([$c[] | select(.planned>0) | .covered / .planned] | if length>0 then add/length*100|round else null end)) else null end),
    "計画外の振る舞い変更が見つかった回数": (if ($c|length)>0 then ([$c[] | select((.unplanned // 0) > 0)] | length) else null end)
  }'

echo ""
echo "== リポジトリ別(レビュー実行数 / ゲート通過数)=="
echo "$DATA" | jq -s -r '
  group_by(.repo) | map(
    "  \(.[0].repo): review \([.[] | select(.event=="review.pass")] | length) 回 / gate 通過 \([.[] | select(.event=="gate.pass")] | length) 回 / gate ブロック \([.[] | select(.event=="gate.block")] | length) 回"
  ) | .[]'

echo ""
echo "== 直近 15 イベント(古い順)=="
echo "$DATA" | jq -s -r '
  sort_by(.ts) | .[-15:] | .[] |
  "  \(.ts) [\(.repo)/\(.branch)] \(.event)" +
  (if .event=="review.round" then " round=\(.round) tier=\(.tier) c=\(.critical) w=\(.warning) i=\(.info) \(.verdict)"
   elif .event=="gate.block" then " action=\(.action) reason=\(.reason)"
   elif .event=="gate.pass" then " action=\(.action) test_plan=\(.has_test_plan)"
   elif .event=="test_check.result" then " covered=\(.covered)/\(.planned) unplanned=\(.unplanned // 0) \(.verdict)"
   elif .event=="test_plan.created" then " cases=\(.cases)"
   else "" end)'
