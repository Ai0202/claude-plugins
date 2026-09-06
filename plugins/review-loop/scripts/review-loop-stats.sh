#!/usr/bin/env bash
# review-loop-stats.sh — レビューループの実行状況を集計する
# 使い方: review-loop-stats.sh [-f ログファイル] [日数(省略時は全期間)]
# デフォルトでは ~/.claude/review-loop.log.jsonl と、カレントのリポジトリ内
# .claude/review-loop.log.jsonl の両方をマージして集計する
set -euo pipefail

LOGS=()
if [ "${1:-}" = "-f" ]; then
  LOGS=("$2"); shift 2
else
  [ -f "${HOME}/.claude/review-loop.log.jsonl" ] && LOGS+=("${HOME}/.claude/review-loop.log.jsonl")
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/.claude/review-loop.log.jsonl" ] && LOGS+=("$REPO_ROOT/.claude/review-loop.log.jsonl")
fi
[ ${#LOGS[@]} -gt 0 ] || { echo "ログがまだありません"; exit 0; }

DAYS="${1:-}"
if [ -n "$DAYS" ]; then
  SINCE=$(date -u -d "-${DAYS} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"${DAYS}"d +%Y-%m-%dT%H:%M:%SZ)
  DATA=$(cat "${LOGS[@]}" | jq -c --arg since "$SINCE" 'select(.ts >= $since)')
  echo "== レビューループ統計(過去 ${DAYS} 日)=="
else
  DATA=$(cat "${LOGS[@]}")
  echo "== レビューループ統計(全期間)=="
fi
[ -n "$DATA" ] || { echo "対象期間のログがありません"; exit 0; }

echo "$DATA" | jq -s '
  group_by(.run_id) | map({
    run_id: .[0].run_id,
    repo: .[0].repo,
    tier: (.[0].tier // "-"),
    rounds: length,
    first_issues: (sort_by(.round) | .[0] | (.critical + .warning)),
    final_issues: (sort_by(.round) | .[-1] | (.critical + .warning)),
    final_verdict: (sort_by(.round) | .[-1].verdict)
  }) as $runs |
  {
    "ループ実行回数": ($runs | length),
    "総ラウンド数": ([$runs[].rounds] | add),
    "平均ラウンド数/実行": (([$runs[].rounds] | add) / ($runs | length) * 10 | round / 10),
    "1ラウンドで即合格した割合(%)": (([$runs[] | select(.rounds == 1 and .final_verdict == "pass")] | length) / ($runs | length) * 100 | round),
    "最大ラウンドでも未収束の回数": ([$runs[] | select(.final_verdict == "max-rounds-reached")] | length),
    "平均指摘数(1周目, Critical+Warning)": (([$runs[].first_issues] | add) / ($runs | length) * 10 | round / 10),
    "平均指摘数(最終, Critical+Warning)": (([$runs[].final_issues] | add) / ($runs | length) * 10 | round / 10)
  }'

echo ""
echo "== ティア別 =="
echo "$DATA" | jq -s -r '
  group_by(.run_id) | map({tier: (.[0].tier // "-"), rounds: length,
    first: (sort_by(.round) | .[0] | (.critical + .warning))}) |
  group_by(.tier) | map("tier \(.[0].tier): 実行 \(length) 回 / 平均 \((([.[].rounds] | add) / length * 10 | round / 10)) ラウンド / 1周目平均指摘 \((([.[].first] | add) / length * 10 | round / 10)) 件") | .[]'

echo ""
echo "== リポジトリ別 =="
echo "$DATA" | jq -s -r '
  group_by(.run_id) | map({repo: .[0].repo, rounds: length}) |
  group_by(.repo) | map("\(.[0].repo): 実行 \(length) 回 / 平均 \((([.[].rounds] | add) / length * 10 | round / 10)) ラウンド") | .[]'

echo ""
echo "== 直近10実行(古い順)=="
echo "$DATA" | jq -s -r '
  group_by(.run_id) | sort_by(.[0].ts) | .[-10:] | map(
    (sort_by(.round)) as $r |
    "\($r[0].ts) [\($r[0].repo)] tier=\($r[0].tier // "-") rounds=\($r | length) issues: \($r | map("\(.critical)+\(.warning)") | join(" → ")) verdict=\($r[-1].verdict)"
  ) | .[]'
