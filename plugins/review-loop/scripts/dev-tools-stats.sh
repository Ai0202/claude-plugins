#!/usr/bin/env bash
# dev-tools-stats.sh — dev-tools(review-loop / test-plan)の利用状況を集計する
# 使い方: dev-tools-stats.sh [-f ログファイル ...] [-r owner/repo ...] [日数(省略時は全期間)]
#   -r を付けると、その期間にマージされた自分の PR のうち dev-tools を通ったものの割合(カバー率)を gh で計算する
# デフォルトでは ~/.claude/dev-tools.log.jsonl と、カレントのリポジトリ内
# .claude/dev-tools.log.jsonl の両方をマージして集計する
set -euo pipefail

LOGS=()
REPOS=()
while [ "${1:-}" = "-f" ] || [ "${1:-}" = "-r" ]; do
  case "$1" in
    -f) LOGS+=("$2") ;;
    -r) REPOS+=("$2") ;;
  esac
  shift 2
done
if [ ${#LOGS[@]} -eq 0 ]; then
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
  ([$g[] | select(.action!="pr.draft")] | length) as $n |
  {
    "試行回数": $n,
    "通過": ([$g[] | select(.event=="gate.pass" and .action!="pr.draft")] | length),
    "ブロック(レビュー未合格)": ([$g[] | select(.event=="gate.block" and .reason=="review")] | length),
    "ブロック(テスト未確認)": ([$g[] | select(.event=="gate.block" and .reason=="tests")] | length),
    "ブロック(デザイン未突合)": ([$g[] | select(.event=="gate.block" and .reason=="design")] | length),
    "ブロック率(%)": (if $n>0 then (([$g[] | select(.event=="gate.block")] | length) / $n * 100 | round) else null end),
    "通過時にテスト計画があった割合(%)": (([$g[] | select(.event=="gate.pass" and .action!="pr.draft")] | length) as $p |
      if $p>0 then (([$g[] | select(.event=="gate.pass" and .action!="pr.draft" and .has_test_plan==true)] | length) / $p * 100 | round) else null end),
    "ドラフト作成数": ([$g[] | select(.action=="pr.draft")] | length),
    "ドラフト作成時にレビュー済みだった割合(%)": (([$g[] | select(.event=="gate.pass" and .action=="pr.draft")] | length) as $d |
      if $d>0 then (([$g[] | select(.event=="gate.pass" and .action=="pr.draft" and .reviewed==true)] | length) / $d * 100 | round) else null end)
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
echo "== 3.5 デザイン突合(/design-check)=="
echo "  1 回目の指摘数が減る = 最初から Figma どおりに作れている。L1(静的)ばかりならブラウザ MCP の整備を"
echo "$DATA" | jq -s '
  ([.[] | select(.event=="design_check.result")]) as $d | ($d | length) as $n |
  if $n == 0 then "実行なし" else {
    "実行数": $n,
    "合格率(%)": (([$d[] | select(.verdict=="pass")] | length) / $n * 100 | round),
    "平均指摘数(Critical+Warning)": (([$d[] | (.critical + .warning)] | add) / $n * 10 | round / 10),
    "平均画面数": (([$d[].screens] | add) / $n * 10 | round / 10),
    "レベル別の実行数": ($d | group_by(.level) | map({key: ("L" + (.[0].level | tostring)), value: length}) | from_entries)
  } end'

echo ""
echo "== 4. /atdd(ATDD ループ)=="
echo "  完走率が高く、平均周回が少ない = 計画とテストが最初から噛み合っている"
echo "$DATA" | jq -s '
  ([.[] | select(.event=="atdd.start")]) as $s |
  ([.[] | select(.event=="atdd.done")]) as $d |
  ([.[] | select(.event=="atdd.abort")]) as $a |
  ([.[] | select(.event=="tests.run")]) as $t |
  {
    "開始回数": ($s | length),
    "完走回数": ($d | length),
    "打ち切り回数": ($a | length),
    "完走率(%)": (if ($s|length)>0 then (($d|length) / ($s|length) * 100 | round) else null end),
    "平均周回数(完走分)": (if ($d|length)>0 then (([$d[].iterations] | add) / ($d|length) * 10 | round / 10) else null end),
    "テスト実行回数": ($t | length),
    "テスト失敗率(%)": (if ($t|length)>0 then (([$t[] | select(.exit != 0)] | length) / ($t|length) * 100 | round) else null end)
  }'

if [ ${#REPOS[@]} -gt 0 ] && command -v gh >/dev/null 2>&1; then
  echo ""
  echo "== 5. カバー率(マージ済み PR のうち dev-tools を通った割合)=="
  echo "  ブランチ名でログと突合。review = /review-loop 合格、atdd = /atdd 完走、docs = /pr-docs 実行"
  SINCE_DAY=$(if [ -n "$DAYS" ]; then date -u -d "-${DAYS} days" +%Y-%m-%d 2>/dev/null || date -u -v-"${DAYS}"d +%Y-%m-%d; else echo "2000-01-01"; fi)
  BR_REVIEW=$(echo "$DATA" | jq -r 'select(.event=="review.pass") | .branch' | sort -u)
  BR_ATDD=$(echo "$DATA" | jq -r 'select(.event=="atdd.done") | .branch' | sort -u)
  BR_DOCS=$(echo "$DATA" | jq -r 'select(.event=="pr_docs.done") | .branch' | sort -u)
  T=0; R=0; A=0; D=0
  printf "  %-34s %6s %7s %5s %5s\n" "repo" "merged" "review" "atdd" "docs"
  for REPO in "${REPOS[@]}"; do
    PRS=$(gh pr list --repo "$REPO" --state merged --author @me --search "merged:>=${SINCE_DAY}" --limit 200 --json headRefName -q '.[].headRefName' 2>/dev/null || true)
    n=0; r=0; a=0; d=0
    while IFS= read -r br; do
      [ -n "$br" ] || continue
      n=$((n+1))
      grep -qx "$br" <<<"$BR_REVIEW" && r=$((r+1))
      grep -qx "$br" <<<"$BR_ATDD" && a=$((a+1))
      grep -qx "$br" <<<"$BR_DOCS" && d=$((d+1))
    done <<<"$PRS"
    printf "  %-34s %6s %7s %5s %5s\n" "$REPO" "$n" "$r" "$a" "$d"
    T=$((T+n)); R=$((R+r)); A=$((A+a)); D=$((D+d))
  done
  if [ "$T" -gt 0 ]; then
    printf "  %-34s %6s %6s%% %4s%% %4s%%\n" "TOTAL" "$T" "$((R*100/T))" "$((A*100/T))" "$((D*100/T))"
  else
    echo "  (期間内にマージ済み PR なし)"
  fi
fi

echo ""
echo "== リポジトリ別(レビュー実行数 / ゲート通過数)=="
echo "$DATA" | jq -s -r '
  group_by(.repo) | map(
    "  \(.[0].repo): review \([.[] | select(.event=="review.pass")] | length) 回 / gate 通過 \([.[] | select(.event=="gate.pass")] | length) 回 / gate ブロック \([.[] | select(.event=="gate.block")] | length) 回 / pr-docs \([.[] | select(.event=="pr_docs.done")] | length) 回"
  ) | .[]'

echo ""
echo "== 直近 15 イベント(古い順)=="
echo "$DATA" | jq -s -r '
  sort_by(.ts) | .[-15:] | .[] |
  "  \(.ts) [\(.repo)/\(.branch)] \(.event)" +
  (if .event=="review.round" then " round=\(.round) tier=\(.tier) c=\(.critical) w=\(.warning) i=\(.info) \(.verdict)"
   elif .event=="gate.block" then " action=\(.action) reason=\(.reason)"
   elif .event=="gate.pass" then " action=\(.action) reviewed=\(.reviewed) test_plan=\(.has_test_plan)"
   elif .event=="test_check.result" then " covered=\(.covered)/\(.planned) unplanned=\(.unplanned // 0) \(.verdict)"
   elif .event=="test_plan.created" then " cases=\(.cases)"
   elif .event=="design_check.result" then " screens=\(.screens) L\(.level) c=\(.critical) w=\(.warning) i=\(.info) \(.verdict)"
   elif .event=="pr_docs.done" then " pr=#\(.pr) comments=\(.comments)"
   elif .event=="pr_docs.prompt" then " pr=#\(.pr)"
   elif .event=="atdd.iteration" then " \(.iteration) [\(.phase)] tests=\(.tests_green)\(if .design_ok != null then " design=\(.design_ok)" else "" end) review=\(.reviewed) pr=\(.pr_ok)"
   elif .event=="atdd.done" then " iterations=\(.iterations)"
   elif .event=="atdd.resume" then " (再開)"
   elif .event=="atdd.abort" then " iterations=\(.iterations) tests=\(.tests_green) review=\(.reviewed) pr=\(.pr_ok)"
   elif .event=="tests.run" then " exit=\(.exit)"
   else "" end)'
