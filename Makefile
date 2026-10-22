# THS 开发入口。依赖（ETAF / ebox / ecss）由 scripts/boot.el 引导：
# 先 package-initialize，若 ETAF 仍不可见则探测 straight build 目录补 load-path。
# 可用 make check LOAD="-l scripts/boot.el -L /path/to/etaf ..." 覆盖。
#
# 严格编译必须走 scripts/compile-strict.el：byte-compile-error-on-warn 为 t 时
# byte-compile-file 遇 warning 只返回 nil 不抛错，且 emacs --batch 退出码恒为 0，
# 门禁只能由脚本按返回值判失败并显式 kill-emacs 1。
#
# check 用两个独立命令行而不是 "&&" 串联：make 逐行执行且首行失败即整体停止，
# 语义与 && 等价，但引号与续行更安全（LOAD 里带引号时也不必二次转义）。

EMACS ?= emacs
LOAD ?= -l scripts/boot.el
BATCH = $(EMACS) -Q --batch $(LOAD) -L . -L tests

.PHONY: check run live-check

check:
	$(BATCH) -l scripts/compile-strict.el
	$(BATCH) -l scripts/test-batch.el

run:
	$(EMACS) -Q $(LOAD) -L . --eval "(progn (require 'ths) (ths))"

live-check:
	$(BATCH) -l tests/ths-live-check.el
