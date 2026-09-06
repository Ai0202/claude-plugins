#!/usr/bin/env bash
#
# change-failure-rate.sh — 自分のPRベースの変更障害率(CFR)を計測する
#
# 定義(近似):
#   CFR = 障害修正PR数 / マージ済みPR総数
#   「障害修正PR」= 以下のいずれかに該当するマージ済みPR
#     - ラベル: hotfix, incident-fix, revert のいずれかが付いている
#     - タイトルが revert / hotfix で始まる(大文字小文字無視)
#
# 運用ルール(これを守ると数字が意味を持つ):
#   デプロイ後に障害・不具合が発覚して修正PRを出すときは、
#   必ず `hotfix` ラベル(リバートなら `revert`)を付ける。それだけ。
#
# 使い方:
#   ./change-failure-rate.sh [-d 日数] [-a GitHubユーザー名] [-p タイトル正規表現] owner/repo [owner/repo ...]
#   例: ./change-failure-rate.sh -d 30 -a your-name myorg/api myorg/frontend
#       ./change-failure-rate.sh -d 30 -p '^(revert|hotfix)|障害|不具合|緊急|取り消し' myorg/api
#   -p はタイトルの判定パターン(大文字小文字無視)。ラベル判定(hotfix / incident-fix / revert)は常に有効
#
# 前提: gh CLI がインストール済みで gh auth login 済みであること

set -euo pipefail

DAYS=30
AUTHOR="@me"
PATTERN='^(revert|hotfix)'

while getopts "d:a:p:" opt; do
  case $opt in
    d) DAYS="$OPTARG" ;;
    a) AUTHOR="$OPTARG" ;;
    p) PATTERN="$OPTARG" ;;
    *) echo "Usage: $0 [-d days] [-a author] [-p title-regex] owner/repo [owner/repo ...]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if [ $# -eq 0 ]; then
  echo "Usage: $0 [-d days] [-a author] owner/repo [owner/repo ...]" >&2
  exit 1
fi

SINCE=$(date -u -d "-${DAYS} days" +%Y-%m-%d 2>/dev/null || date -u -v-"${DAYS}"d +%Y-%m-%d)

total_all=0
fail_all=0

printf "\n変更障害率レポート(過去 %s 日 / author: %s / タイトル判定: %s)\n" "$DAYS" "$AUTHOR" "$PATTERN"
printf "%s\n" "--------------------------------------------------------------"
printf "%-40s %8s %8s %8s\n" "repo" "merged" "failures" "CFR"

for REPO in "$@"; do
  prs=$(gh pr list --repo "$REPO" --state merged --author "$AUTHOR" \
        --search "merged:>=${SINCE}" --limit 500 \
        --json number,title,labels)

  total=$(echo "$prs" | jq 'length')

  failures=$(echo "$prs" | jq --arg re "$PATTERN" '[ .[] | select(
      ( [.labels[].name] | map(ascii_downcase) | any(. == "hotfix" or . == "incident-fix" or . == "revert") )
      or ( .title | test($re; "i") )
    ) ] | length')

  if [ "$total" -gt 0 ]; then
    cfr=$(awk "BEGIN { printf \"%.1f%%\", ($failures / $total) * 100 }")
  else
    cfr="-"
  fi

  printf "%-40s %8s %8s %8s\n" "$REPO" "$total" "$failures" "$cfr"

  total_all=$((total_all + total))
  fail_all=$((fail_all + failures))
done

printf "%s\n" "--------------------------------------------------------------"
if [ "$total_all" -gt 0 ]; then
  cfr_all=$(awk "BEGIN { printf \"%.1f%%\", ($fail_all / $total_all) * 100 }")
else
  cfr_all="-"
fi
printf "%-40s %8s %8s %8s\n\n" "TOTAL" "$total_all" "$fail_all" "$cfr_all"

# 障害修正PRの一覧(振り返り用)
if [ "$fail_all" -gt 0 ]; then
  echo "障害修正PR一覧:"
  for REPO in "$@"; do
    gh pr list --repo "$REPO" --state merged --author "$AUTHOR" \
      --search "merged:>=${SINCE}" --limit 500 \
      --json number,title,labels,url | \
    jq -r --arg repo "$REPO" --arg re "$PATTERN" '.[] | select(
        ( [.labels[].name] | map(ascii_downcase) | any(. == "hotfix" or . == "incident-fix" or . == "revert") )
        or ( .title | test($re; "i") )
      ) | "  [\($repo)] #\(.number) \(.title)\n    \(.url)"'
  done
  echo ""
  echo "ヒント: 各障害修正PRについて「元のPRで何を見落としたか」を1行メモすると、"
  echo "レビュー観点(agents/*.md)の改善ネタになります。"
fi
