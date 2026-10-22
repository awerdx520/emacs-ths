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

EMACS ?= emacs
LOAD ?=
STRAIGHT_BUILD ?=

SOURCES = ths.el ths-ai.el ths-chart.el ths-data.el ths-diagnose.el ths-search.el ths-theme.el ths-watchlist.el

# 离线 ERT 文件，顺序固定：data → otc → ranking → fund-ranking → search →
# trades → volume → watchlist → tests → layout → ai。
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
        tests/ths-ai-tests.el

# 无 GUI 环境下的基线失败（3 例）：干净检出即红，与本次改动无关。
# `check` 排除它们，`check-all` 保留以便观察基线。
KNOWN_FAILURES = ths-fixture-charts-and-book-have-consistent-bounds ths-volume-dashboard-shows-both-panels-without-growing-page ths-volume-terminal-charts-preserve-height-and-column-width

REPO_ROOT := $(CURDIR)
TEST_LIBS = $(foreach f,$(TESTS),-l $(f))

# 启动引导（单行 elisp）：
# 1) package-initialize 加载 elpa 依赖；
# 2) 找不到 etaf 时，把 STRAIGHT_BUILD（若给定）或自动探测到的
#    ~/.emacs.d/straight/build-* / ~/thomas-emacs/.local/straight/build-* 的
#    全部子目录追加到 load-path；
# 3) 最后把仓库根前置，避免 straight 里编译版的 ths 遮蔽当前源码。
BOOTSTRAP := (progn (package-initialize) (unless (locate-library "etaf") (let ((roots (let ((d (getenv "STRAIGHT_BUILD_DIR"))) (if (and d (not (string-empty-p d))) (list d) (append (file-expand-wildcards (expand-file-name "~/.emacs.d/straight/build-*")) (file-expand-wildcards (expand-file-name "~/thomas-emacs/.local/straight/build-*"))))))) (dolist (root (seq-filter (quote file-directory-p) roots)) (dolist (dir (directory-files root t "[^.]")) (when (file-directory-p dir) (add-to-list (quote load-path) dir t)))))) (push "$(REPO_ROOT)" load-path))

BUILD_ENV = STRAIGHT_BUILD_DIR="$(STRAIGHT_BUILD)"

.PHONY: check compile test check-all live-check run clean help

# 默认门禁：严格编译 + 离线 ERT（排除已知基线红）
check: compile test
	@echo "check: ok"

# 严格字节编译（警告即错误），编译产物随即删除
compile:
	@st=0; $(BUILD_ENV) $(EMACS) -Q --batch $(LOAD) --eval '$(BOOTSTRAP)' \
	  --eval '(setq byte-compile-error-on-warn t)' \
	  -f batch-byte-compile $(SOURCES) || st=$$?; \
	  rm -f $(SOURCES:.el=.elc); exit $$st

# 离线 ERT，排除 KNOWN_FAILURES
test:
	@$(BUILD_ENV) $(EMACS) -Q --batch $(LOAD) --eval '$(BOOTSTRAP)' $(TEST_LIBS) \
	  --eval '(ert-run-tests-batch-and-exit (quote (not (member $(KNOWN_FAILURES)))))'

# 离线 ERT 全量（含已知基线红，预期非零退出）
check-all:
	@$(BUILD_ENV) $(EMACS) -Q --batch $(LOAD) --eval '$(BOOTSTRAP)' $(TEST_LIBS) \
	  --eval '(ert-run-tests-batch-and-exit t)'

# 真实公开接口冒烟检查，需要网络
live-check:
	@$(BUILD_ENV) $(EMACS) -Q --batch $(LOAD) --eval '$(BOOTSTRAP)' -l tests/ths-live-check.el

# 从当前源码启动干净的 Emacs 并打开 THS（需图形环境，故不加 --batch）
run:
	$(EMACS) -Q $(LOAD) --eval '$(BOOTSTRAP)' --eval '(progn (require (quote ths)) (ths))'

clean:
	rm -f *.elc

help:
	@echo "make check       严格字节编译 + 离线 ERT（排除 3 个已知基线红）"
	@echo "make check-all   离线 ERT 全量（含已知基线红，预期非零）"
	@echo "make compile     仅严格字节编译（警告即错误，产物随即删除）"
	@echo "make test        仅离线 ERT（排除已知基线红）"
	@echo "make live-check  真实行情接口冒烟检查（需网络）"
	@echo "make run         从当前源码启动干净的 Emacs 并打开 THS"
	@echo "make clean       删除 *.elc"
	@echo "变量：EMACS / LOAD / STRAIGHT_BUILD"
