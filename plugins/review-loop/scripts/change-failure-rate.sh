#!/usr/bin/env bash
#
# change-failure-rate.sh — 自分の PR ベースの変更障害率(CFR)を計測する
#
# 定義:
#   CFR = 期間内にマージされた変更(PR)のうち、あとで修正・取り消しが必要になったものの割合
#   「必要になった」は、修正 PR が原因 PR を指していることで判定する:
#     - 修正 PR の本文に `Caused-by: #123` / `原因PR: #123` / `原因: #123`
#     - 調べたが最近の変更が原因ではない(古い不具合・外部要因)なら `Caused-by: unknown`(不明 / なし でも可)
#     - Revert PR はタイトル中の `(#123)` を原因とみなす
#   修正 PR の候補: ラベル type:bugfix / type:hotfix / bugfix / hotfix / revert、タイトルが -p に一致、本文に Caused-by
#   原因 PR が期間内にマージされていれば、その原因 PR を「失敗した変更」として数える(重複は 1 件)。
#   原因 PR が期間より前なら「古い不具合の修正」であり、今回の CFR には数えない。
#   原因の記載が無い修正 PR(ラベル hotfix/incident-fix/revert、またはタイトルが -p に一致)は
#   「原因未記載」として別に一覧し、-u を付けたときだけ失敗として数える(過去との比較用)。
#
# 運用ルール(これを守ると数字が意味を持つ):
#   不具合を直す PR の本文に `Caused-by: #<原因PR番号>` を 1 行書く。原因が特定できないときは書かない。
#
# 使い方:
#   ./change-failure-rate.sh [-d 日数] [-a GitHubユーザー名] [-p タイトル正規表現] [-u] [--record] [--history] owner/repo [owner/repo ...]
#   例: ./change-failure-rate.sh -d 30 -p '^(revert|hotfix)|障害|不具合|緊急|取り消し' myorg/api
#   --record  結果を ~/.claude/dev-tools.metrics.jsonl に 1 行追記する(長期の推移用)
#   --history 追記済みの推移を表示して終了する
#
# 前提: gh CLI がインストール済みで gh auth login 済みであること

set -euo pipefail

DAYS=30
AUTHOR="@me"
PATTERN='^(revert|hotfix)'
COUNT_UNKNOWN=false
RECORD=false
HISTORY=false
METRICS="${DEV_TOOLS_METRICS:-$HOME/.claude/dev-tools.metrics.jsonl}"

ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -d) DAYS="$2"; shift 2 ;;
    -a) AUTHOR="$2"; shift 2 ;;
    -p) PATTERN="$2"; shift 2 ;;
    -u) COUNT_UNKNOWN=true; shift ;;
    --record) RECORD=true; shift ;;
    --history) HISTORY=true; shift ;;
    -*) echo "Usage: $0 [-d days] [-a author] [-p title-regex] [-u] [--record] [--history] owner/repo [...]" >&2; exit 1 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

if $HISTORY; then
  [ -f "$METRICS" ] || { echo "推移の記録がまだありません($METRICS)。--record を付けて実行すると溜まります"; exit 0; }
  echo "変更障害率の推移($METRICS)"
  printf "%-12s %-34s %5s %7s %7s %8s %9s\n" "記録日" "repo" "日数" "merged" "failed" "CFR" "原因未記載"
  jq -r '"\(.ts[0:10]) \(.repo) \(.days) \(.merged) \(.failed) \(.cfr)% \(.fixes_unknown)"' "$METRICS" | \
    awk '{ printf "%-12s %-34s %5s %7s %7s %8s %9s\n", $1, $2, $3, $4, $5, $6, $7 }'
  exit 0
fi

[ ${#ARGS[@]} -gt 0 ] || { echo "Usage: $0 [-d days] [-a author] [-p title-regex] [-u] [--record] [--history] owner/repo [...]" >&2; exit 1; }

SINCE=$(date -u -d "-${DAYS} days" +%Y-%m-%d 2>/dev/null || date -u -v-"${DAYS}"d +%Y-%m-%d)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

total_all=0; fail_all=0; unknown_all=0

printf "\n変更障害率レポート(過去 %s 日 / author: %s / タイトル判定: %s%s)\n" "$DAYS" "$AUTHOR" "$PATTERN" "$($COUNT_UNKNOWN && echo ' / 原因未記載も失敗に含む')"
printf "%s\n" "----------------------------------------------------------------------------"
printf "%-34s %7s %7s %8s %10s %8s\n" "repo" "merged" "failed" "CFR" "原因未記載" "古い修正"

DETAIL=""
for REPO in "${ARGS[@]}"; do
  prs=$(gh pr list --repo "$REPO" --state merged --author "$AUTHOR" \
        --search "merged:>=${SINCE}" --limit 500 \
        --json number,title,body,labels,url,mergedAt)
  total=$(echo "$prs" | jq 'length')
  merged_numbers=$(echo "$prs" | jq -c '[.[].number]')

  # 修正候補: ラベル / タイトル / 本文の Caused-by
  candidates=$(echo "$prs" | jq -c --arg re "$PATTERN" '
    [ .[] | select(
        ( [.labels[].name] | map(ascii_downcase) | any(test("^(type:)?(hotfix|bugfix|bug[ _-]?fix|incident-fix|revert)$")) )
        or ( .title | test($re; "i") )
        or ( (.body // "") | test("(Caused-by|原因PR|原因)[[:space:]]*[:：]"; "i") )
      ) | {number, title, url, body: (.body // "")} ]')

  # 各候補から原因 PR 番号を抽出(本文優先、Revert はタイトルの #n)
  analyzed=$(echo "$candidates" | jq -c --argjson merged "$merged_numbers" '
    map(
      ( [ .body | capture("(Caused-by|原因PR|原因)[[:space:]]*[:：][[:space:]]*#(?<n>[0-9]+)"; "i") | .n | tonumber ] | .[0] ) as $bodycause
      | ( .body | test("(Caused-by|原因PR|原因)[[:space:]]*[:：][[:space:]]*(unknown|none|不明|なし|特定不能)"; "i") ) as $nocause
      | ( if ($bodycause == null) and (.title | test("revert|取り消し"; "i"))
          then ([ .title | capture("#(?<n>[0-9]+)") | .n | tonumber ] | .[0])
          else $bodycause end ) as $cause
      | . + { cause: $cause, nocause: $nocause,
              cause_in_window: ( if $cause != null then (($merged | index($cause)) != null) elif $nocause then false else null end ) }
    )')

  failed_set=$(echo "$analyzed" | jq -c '[ .[] | select(.cause_in_window == true) | .cause ] | unique')
  failed=$(echo "$failed_set" | jq 'length')
  unknown=$(echo "$analyzed" | jq '[ .[] | select(.cause == null) ] | length')
  old=$(echo "$analyzed" | jq '[ .[] | select(.cause_in_window == false) ] | length')
  if $COUNT_UNKNOWN; then failed=$((failed + unknown)); fi

  if [ "$total" -gt 0 ]; then
    cfr=$(awk "BEGIN { printf \"%.1f\", ($failed / $total) * 100 }")
  else
    cfr="-"
  fi
  printf "%-34s %7s %7s %8s %10s %8s\n" "$REPO" "$total" "$failed" "${cfr}%" "$unknown" "$old"

  DETAIL+=$(echo "$analyzed" | jq -r --arg repo "$REPO" '.[] |
    "  [\($repo)] #\(.number) \(.title)\n    \(.url)\n    " +
    (if .nocause and .cause == null then "原因: 調査済みで該当 PR なし(Caused-by: unknown)→ 計上しない"
     elif .cause == null then "原因: 未記載(本文に Caused-by: #n を書くと計測に乗る)"
     elif .cause_in_window then "原因: #\(.cause)(期間内 → 失敗として計上)"
     else "原因: #\(.cause)(期間外 → 古い不具合。今回は計上しない)" end)')$'\n'

  if $RECORD; then
    mkdir -p "$(dirname "$METRICS")"
    jq -cn --arg ts "$NOW" --arg repo "$REPO" --argjson days "$DAYS" --argjson merged "$total" \
      --argjson failed "$failed" --arg cfr "$cfr" --argjson unknown "$unknown" --argjson old "$old" \
      --arg pattern "$PATTERN" --argjson count_unknown "$COUNT_UNKNOWN" \
      '{ts:$ts, repo:$repo, days:$days, merged:$merged, failed:$failed, cfr:$cfr, fixes_unknown:$unknown, fixes_old:$old, pattern:$pattern, count_unknown:$count_unknown}' >> "$METRICS"
  fi

  total_all=$((total_all + total)); fail_all=$((fail_all + failed)); unknown_all=$((unknown_all + unknown))
done

printf "%s\n" "----------------------------------------------------------------------------"
if [ "$total_all" -gt 0 ]; then
  cfr_all=$(awk "BEGIN { printf \"%.1f%%\", ($fail_all / $total_all) * 100 }")
else
  cfr_all="-"
fi
printf "%-34s %7s %7s %8s %10s\n\n" "TOTAL" "$total_all" "$fail_all" "$cfr_all" "$unknown_all"

if [ -n "$DETAIL" ]; then
  echo "修正・取り消し PR の一覧:"
  printf "%s" "$DETAIL"
  echo ""
fi
$RECORD && echo "推移を記録しました: $METRICS(--history で表示)"
echo "ヒント: 不具合を直す PR の本文に「Caused-by: #<原因PR>」を 1 行書くと、どのリリースの失敗かが自動で紐づきます。"
