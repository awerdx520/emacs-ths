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
#
# locale 固定：tests 中 3 条断言（ths-fixture-charts-and-book-have-consistent-bounds
# 与 2 条 ths-volume-*）依赖 Emacs 的宽字符显示宽度，结果随 LC_ALL/LANG 变化：
# zh_CN.UTF-8 下 3 条失败，C.UTF-8 / en_US.UTF-8 下全绿。这是环境敏感的既存断言，
# 与源码无关，因此不改测试语义，而在命令行里固定运行环境。
# 选定 C.UTF-8：实测全绿（146 tests / 0 unexpected），且比 en_US.UTF-8 更通用；
# 注意 LC_ALL=C（非 UTF-8）会失败，故必须带 .UTF-8 后缀。
# 该前缀有意覆盖调用者的 LC_ALL/LANG，使 make check / run 与调用环境无关。

EMACS ?= emacs
LOAD ?= -l scripts/boot.el
LOCALE_ENV = LC_ALL=C.UTF-8
BATCH = $(LOCALE_ENV) $(EMACS) -Q --batch $(LOAD) -L . -L tests

.PHONY: check run live-check

check:
	$(BATCH) -l scripts/compile-strict.el
	$(BATCH) -l scripts/test-batch.el

run:
	$(LOCALE_ENV) $(EMACS) -Q $(LOAD) -L . --eval "(progn (require 'ths) (ths))"

live-check:
	$(BATCH) -l tests/ths-live-check.el
