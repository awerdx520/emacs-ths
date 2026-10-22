;;; test-batch.el --- THS 离线 ERT 入口（不联网） -*- lexical-binding: t; -*-

;;; Commentary:

;; `make check' 的第二步：在 `emacs -Q --batch' 下离线跑全部 ERT 用例。
;;
;; 显式加载 12 个文件，顺序固定：
;;
;;   1. `tests/ths-tests.el' —— 公共宏 `ths-test-with-dashboard' 与辅助函数
;;      `ths-test-press' / `ths-test-visible' 定义在这里；它内部用
;;      `load-file-name' 自动加载 `tests/ths-fixtures.el'，故夹具不必在此重复加载。
;;   2. 其余 11 个含 `ert-deftest' 的文件。
;;
;; 为什么显式前置 `ths-tests.el'（加固，不是必需）：`-l' 解释执行下
;; `ert-deftest' 只把 body 包进 `(lambda () ...)'，宏在测试运行时才展开，
;; 因此字母序（宏使用者先于定义者）也能跑通；但一旦将来把测试改成字节编译，
;; 缺宏只会产生警告，加载期会静默取到未展开宏的旧字节码。
;;
;; 排除 `tests/ths-live-check.el'：它发真实网络请求，属 `make live-check'。

;;; Code:

(require 'ert)

(defconst ths-test--root
  (expand-file-name ".." (file-name-directory (expand-file-name (or load-file-name buffer-file-name))))
  "仓库根目录：由本文件所在位置反推，不依赖 cwd。")

(defconst ths-test--files
  '("tests/ths-tests.el"
    "tests/ths-data-tests.el"
    "tests/ths-fund-ranking-tests.el"
    "tests/ths-gui-tests.el"
    "tests/ths-hkus-tests.el"
    "tests/ths-layout-tests.el"
    "tests/ths-otc-tests.el"
    "tests/ths-ranking-tests.el"
    "tests/ths-search-tests.el"
    "tests/ths-trades-tests.el"
    "tests/ths-volume-tests.el"
    "tests/ths-watchlist-tests.el")
  "显式加载的 ERT 文件（12 个；`ths-tests.el' 必须在首位）。")

(dolist (rel ths-test--files)
  (load (expand-file-name rel ths-test--root) nil t))

(ert-run-tests-batch-and-exit)
;;; test-batch.el ends here
