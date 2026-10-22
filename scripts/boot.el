;;; boot.el --- THS batch 会话依赖引导（ETAF / ebox / ecss） -*- lexical-binding: t; -*-

;;; Commentary:

;; `make check' / `make run' / `make live-check' 的默认依赖引导。
;;
;; 背景（实测 2026-10-22，GNU Emacs 31.1）：`emacs -Q --batch' 下 straight 安装的
;; ETAF 不在 `load-path' 里——`package-initialize' 只认 `package-user-dir'，
;; 不含 straight build 目录，因此 `(featurep 'etaf)' 为 nil。本文件按固定顺序修复：
;;
;;   1. `package-initialize'，先把 `package-archives' 置 nil：全程离线，
;;      不建归档索引、不下载、不安装任何东西；
;;   2. ETAF 仍不可见时，按下列顺序把 straight build 目录并入 `load-path'
;;      （只加真实存在的目录）：
;;        ~/.emacs.d/straight/build-*/*
;;        ~/.config/emacs/straight/build-*/*
;;        ~/*/.local/straight/build-*/*
;;        ~/*/straight/build-*/*
;;   3. 仍未 `(featurep 'etaf)' 则直接报错，并提示用 `LOAD=' 覆盖。
;;
;; 覆盖方式（机器布局不同，或想用别的 ETAF 副本时）：
;;   make check LOAD="-l scripts/boot.el -L /path/to/etaf -L /path/to/ebox -L /path/to/ecss"
;; 注意 `LOAD=' 完全替换 Makefile 的默认值，想保留引导就必须显式带上
;; `-l scripts/boot.el'。

;;; Code:

(require 'package)

;; 纯离线：清空归档列表，`package-initialize' 无需索引即可加载已装包。
(setq package-archives nil)
(package-initialize)

(defconst ths-boot--straight-globs
  '("~/.emacs.d/straight/build-*/*"
    "~/.config/emacs/straight/build-*/*"
    "~/*/.local/straight/build-*/*"
    "~/*/straight/build-*/*")
  "straight build 目录的探测顺序（先匹配者先入 `load-path'）。")

(unless (featurep 'etaf)
  (dolist (glob ths-boot--straight-globs)
    (dolist (dir (file-expand-wildcards (expand-file-name glob)))
      (when (file-directory-p dir)
        (add-to-list 'load-path dir))))
  ;; 补完路径后真正 require 一次：`featurep' 不会自己触发加载。
  ;; 这里吞掉错误，统一由下面的检查给出可读提示。
  (require 'etaf nil t))

(unless (featurep 'etaf)
  (error "ETAF 未找到：请用 make check LOAD=\"-l scripts/boot.el -L /path/to/etaf ...\" 覆盖"))

(princ "boot: ETAF 就绪\n")

(provide 'ths-boot)
;;; boot.el ends here
