#!/usr/bin/env bash
# 离线 ERT 入口：与 Makefile 的 BOOTSTRAP 保持同一套启动引导。
#
# 用法：
#   tests/run-offline.sh                      # 排除已知基线红
#   tests/run-offline.sh --all                # 全量（含已知基线红，预期非零）
#   tests/run-offline.sh --selector REGEXP    # 只跑名字匹配 REGEXP 的用例
#
# 环境变量：EMACS（默认 emacs）、STRAIGHT_BUILD（straight build 目录兜底）。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

EMACS_BIN="${EMACS:-emacs}"

run_all=0
selector_regexp=""
while [ $# -gt 0 ]; do
    case "$1" in
        --all)
            run_all=1
            shift
            ;;
        --selector)
            if [ $# -lt 2 ]; then
                echo "run-offline: --selector 需要一个正则参数" >&2
                exit 2
            fi
            selector_regexp="$2"
            shift 2
            ;;
        --help | -h)
            sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "run-offline: 未知参数 $1" >&2
            exit 2
            ;;
    esac
done

# 与 Makefile 的 TESTS 顺序一致；不含 ths-gui-tests.el（需图形）
# 与 ths-live-check.el（需网络）。
tests=(
    tests/ths-data-tests.el
    tests/ths-otc-tests.el
    tests/ths-ranking-tests.el
    tests/ths-fund-ranking-tests.el
    tests/ths-search-tests.el
    tests/ths-trades-tests.el
    tests/ths-volume-tests.el
    tests/ths-watchlist-tests.el
    tests/ths-tests.el
    tests/ths-layout-tests.el
    tests/ths-ai-tests.el
)

known_failures="ths-fixture-charts-and-book-have-consistent-bounds ths-volume-dashboard-shows-both-panels-without-growing-page ths-volume-terminal-charts-preserve-height-and-column-width"

if [ -n "$selector_regexp" ]; then
    ert_selector="\"$selector_regexp\""
elif [ "$run_all" -eq 1 ]; then
    ert_selector="t"
else
    ert_selector="(quote (not (member $known_failures)))"
fi

if [ -n "${STRAIGHT_BUILD:-}" ]; then
    export STRAIGHT_BUILD_DIR="$STRAIGHT_BUILD"
fi

# 单行 elisp：package-initialize → 找不到 etaf 时补 straight build 目录 →
# 仓库根前置（避免 straight 编译版 ths 遮蔽当前源码）。
bootstrap="(progn (package-initialize) (unless (locate-library \"etaf\") (let ((roots (let ((d (getenv \"STRAIGHT_BUILD_DIR\"))) (if (and d (not (string-empty-p d))) (list d) (append (file-expand-wildcards (expand-file-name \"~/.emacs.d/straight/build-*\")) (file-expand-wildcards (expand-file-name \"~/thomas-emacs/.local/straight/build-*\"))))))) (dolist (root (seq-filter (quote file-directory-p) roots)) (dolist (dir (directory-files root t \"[^.]\")) (when (file-directory-p dir) (add-to-list (quote load-path) dir t)))))) (push \"$REPO_ROOT\" load-path))"

# bash 数组拼 -l，避免 zsh 分词问题
load_args=()
for file in "${tests[@]}"; do
    load_args+=(-l "$file")
done

output_file="$(mktemp)"
trap 'rm -f "$output_file"' EXIT

set +e
"$EMACS_BIN" -Q --batch \
    --eval "$bootstrap" \
    "${load_args[@]}" \
    --eval "(ert-run-tests-batch-and-exit $ert_selector)" 2>&1 | tee "$output_file"
status="${PIPESTATUS[0]}"
set -e

summary_line="$(sed -n 's/^Ran \([0-9][0-9]*\) tests, \([0-9][0-9]*\) results as expected, \([0-9][0-9]*\) unexpected.*/\1 \2 \3/p' "$output_file" | tail -n 1)"

if [ -n "$summary_line" ]; then
    read -r total_tests total_expected total_unexpected <<<"$summary_line"
else
    total_tests=0
    total_expected=0
    total_unexpected=0
fi

echo "offline ERT: ${total_tests} tests, ${total_expected} expected, ${total_unexpected} unexpected"
exit "$status"
