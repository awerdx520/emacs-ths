# THS 开发入口：严格字节编译 + 离线 ERT + 真实行情冒烟检查
#
# 除 `run` 外所有目标都用 `emacs -Q --batch` 启动：不读取用户初始化文件，
# 仅通过 `package-initialize` 加载已安装依赖；THS 一律使用当前检出的源码。
#
# 可用变量：
#   EMACS            Emacs 可执行文件（默认 emacs）
#   LOAD             额外的加载参数，原样展开
#   STRAIGHT_BUILD   依赖由 straight 安装、`package-initialize` 找不到时的
#                    straight build 目录（如 ~/.local/straight/build-31.1）
#
# 严格编译必须走 scripts/compile-strict.el：`-f batch-byte-compile` 是命令，
# 其返回值不影响 emacs 的退出码；`byte-compile-error-on-warn` 为 t 时遇 warning
# 只让 `byte-compile-file` 返回 nil 且不生成 `.elc`，emacs 仍以 0 退出 —— 即
# `make compile` 会假绿。门禁只能由脚本按返回值判失败并显式 `kill-emacs 1`。
# 脚本的源文件清单由命令行参数给出（`--` 之后），缺省回落到 8 个源文件；
# 编译产物写入临时目录，仓库内永不出现 `.elc`。
#
# locale 固定（LOCALE_ENV）：离线套件里曾有 3 条断言
# （ths-fixture-charts-and-book-have-consistent-bounds 与 2 条 ths-volume-*）
# 依赖 Emacs 的宽字符显示宽度，结果随 LC_ALL/LANG 变化：zh_CN.UTF-8 下 3 条失败，
# C.UTF-8 / en_US.UTF-8 下全绿。这是环境敏感的既存断言，与源码无关，因此不改
# 测试语义，而在命令行里固定运行环境。注意 LC_ALL=C（非 UTF-8）会失败，故必须
# 带 .UTF-8 后缀。该前缀有意覆盖调用者的 LC_ALL/LANG，使结果与调用环境无关。

EMACS ?= emacs
LOAD ?=
STRAIGHT_BUILD ?=

SOURCES = ths.el ths-ai.el ths-chart.el ths-data.el ths-diagnose.el ths-search.el ths-theme.el ths-watchlist.el

# 离线 ERT 文件，顺序固定：data → otc → ranking → fund-ranking → search →
# trades → volume → watchlist → tests → layout → ai → hkus。
# 不含 tests/ths-gui-tests.el（需图形）与 tests/ths-live-check.el（需网络）。
TESTS = tests/ths-data-tests.el \
        tests/ths-otc-tests.el \
        tests/ths-ranking-tests.el \
        tests/ths-fund-ranking-tests.el \
        tests/ths-search-tests.el \
        tests/ths-trades-tests.el \
        tests/ths-volume-tests.el \
        tests/ths-watchlist-tests.el \
        tests/ths-tests.el \
        tests/ths-layout-tests.el \
        tests/ths-ai-tests.el \
        tests/ths-hkus-tests.el

# 已知基线失败：当前为空。那 3 条曾被排除的用例已由 LOCALE_ENV=C.UTF-8 转绿。
# 注意：ERT 选择器写成 `(not (member ))` 在列表为空时是非法 elisp，因此
# `test` / `check-all` 一律直接用 `t`，不再拼接 KNOWN_FAILURES。
KNOWN_FAILURES =

REPO_ROOT := $(CURDIR)
TEST_LIBS = $(foreach f,$(TESTS),-l $(f))
LOCALE_ENV = LC_ALL=C.UTF-8

# 启动引导（单行 elisp）：
# 1) package-initialize 加载 elpa 依赖；
# 2) 找不到 etaf 时，把 STRAIGHT_BUILD（若给定）或自动探测到的
#    ~/.emacs.d/straight/build-* / ~/thomas-emacs/.local/straight/build-* 的
#    全部子目录追加到 load-path；
# 3) 最后把仓库根前置，避免 straight 里编译版的 ths 遮蔽当前源码。
BOOTSTRAP := (progn (package-initialize) (unless (locate-library "etaf") (let ((roots (let ((d (getenv "STRAIGHT_BUILD_DIR"))) (if (and d (not (string-empty-p d))) (list d) (append (file-expand-wildcards (expand-file-name "~/.emacs.d/straight/build-*")) (file-expand-wildcards (expand-file-name "~/thomas-emacs/.local/straight/build-*"))))))) (dolist (root (seq-filter (quote file-directory-p) roots)) (dolist (dir (directory-files root t "[^.]")) (when (file-directory-p dir) (add-to-list (quote load-path) dir t)))))) (push "$(REPO_ROOT)" load-path))

BUILD_ENV = STRAIGHT_BUILD_DIR="$(STRAIGHT_BUILD)"

.PHONY: check compile test check-all live-check run clean help

# 默认门禁：严格编译 + 离线 ERT（全量，0 unexpected）
check: compile test
	@echo "check: ok"

# 严格字节编译（警告即错误）：8 个源文件逐一编译，任一 warning/error 即非零退出
compile:
	@$(LOCALE_ENV) $(BUILD_ENV) $(EMACS) -Q --batch $(LOAD) --eval '$(BOOTSTRAP)' \
	  -l scripts/compile-strict.el -- $(SOURCES)

# 离线 ERT 全量。KNOWN_FAILURES 已清空，故选择器直接为 t；
# check / check-all 现等价（3 例宽字符断言已由 LOCALE_ENV=C.UTF-8 转绿）。
test:
	@$(LOCALE_ENV) $(BUILD_ENV) $(EMACS) -Q --batch $(LOAD) --eval '$(BOOTSTRAP)' $(TEST_LIBS) \
	  --eval '(ert-run-tests-batch-and-exit t)'

# 离线 ERT 全量别名：3 例宽字符断言已由 LOCALE_ENV=C.UTF-8 转绿，
# `check` 与 `check-all` 现在等价；保留本目标以免调用方与文档失效。
check-all:
	@$(LOCALE_ENV) $(BUILD_ENV) $(EMACS) -Q --batch $(LOAD) --eval '$(BOOTSTRAP)' $(TEST_LIBS) \
	  --eval '(ert-run-tests-batch-and-exit t)'

# 真实公开接口冒烟检查，需要网络
live-check:
	@$(LOCALE_ENV) $(BUILD_ENV) $(EMACS) -Q --batch $(LOAD) --eval '$(BOOTSTRAP)' -l tests/ths-live-check.el

# 从当前源码启动干净的 Emacs 并打开 THS（需图形环境，故不加 --batch）
run:
	@$(LOCALE_ENV) $(EMACS) -Q $(LOAD) --eval '$(BOOTSTRAP)' --eval '(progn (require (quote ths)) (ths))'

clean:
	rm -f *.elc

help:
	@echo "make check       严格字节编译 + 离线 ERT 全量（0 unexpected）"
	@echo "make check-all   离线 ERT 全量（与 check 等价）"
	@echo "make compile     仅严格字节编译（8 个源文件，警告即错误）"
	@echo "make test        仅离线 ERT 全量（0 unexpected）"
	@echo "make live-check  真实行情接口冒烟检查（需网络）"
	@echo "make run         从当前源码启动干净的 Emacs 并打开 THS"
	@echo "make clean       删除 *.elc"
	@echo "变量：EMACS / LOAD / STRAIGHT_BUILD（locale 固定为 C.UTF-8）"
