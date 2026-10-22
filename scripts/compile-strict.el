;;; compile-strict.el --- THS 严格字节编译驱动（零 warning 门禁） -*- lexical-binding: t; -*-

;;; Commentary:

;; 对 7 个源文件做严格字节编译，产物只落临时目录，仓库内永不出现 `.elc'。
;;
;; 两个必须绕开的陷阱（实测 2026-10-22，GNU Emacs 31.1）：
;;
;;   1. `byte-compile-error-on-warn' 为 t 时，遇 warning **不抛 error**：
;;      `byte-compile-file' 只安静地返回 nil，且不写 `.elc'。
;;      所以门禁判据必须取返回值（并复核 `.elc' 是否真的生成），
;;      不能指望 `condition-case' 捕获失败。
;;   2. `emacs --batch' 的退出码**恒为 0**，即使编译失败也是 0。
;;      所以失败必须显式 `(kill-emacs 1)'，否则 make 只会假绿。
;;
;; 产物隔离：`byte-compile-dest-file-function' 把 `.elc' 全部重定向到
;; `(make-temp-file "ths-elc-" t)' 目录；`unwind-protect' 保证成功、失败、
;; 异常三条路径都删掉临时目录。
;;
;; 不编译测试文件：`tests/ths-trades-tests.el:101' 存在既存的 free variable
;; `buffer'，严格编译必失败，属既存噪声，不在本计划范围。

;;; Code:

;; 先把 bytecomp 装上，并显式声明下面要动态绑定的两个变量。
;; 必须这样做：本文件 `lexical-binding' 为 t，若对尚未 `defvar' 的变量做 `let'，
;; 会生成词法绑定；等 `bytecomp' 稍后再 `defvar' 同名变量时就会报
;; "Defining as dynamic an already lexical var"（实测 2026-10-22，首次实现即踩中）。
(require 'bytecomp)
(defvar byte-compile-error-on-warn)
(defvar byte-compile-dest-file-function)

(defconst ths-compile--root
  (expand-file-name ".." (file-name-directory (expand-file-name (or load-file-name buffer-file-name))))
  "仓库根目录：由本文件所在位置反推，不依赖 cwd。")

(defconst ths-compile--sources
  '("ths.el"
    "ths-data.el"
    "ths-chart.el"
    "ths-search.el"
    "ths-watchlist.el"
    "ths-theme.el"
    "ths-diagnose.el")
  "待严格编译的源文件清单（相对仓库根，顺序固定）。")

(let* ((total (length ths-compile--sources))
       (failures nil)
       (dest (make-temp-file "ths-elc-" t))
       (byte-compile-error-on-warn t)
       (byte-compile-dest-file-function
        (lambda (src) (expand-file-name (concat (file-name-nondirectory src) "c") dest))))
  (unwind-protect
      (progn
        (dolist (src ths-compile--sources)
          (let* ((file (expand-file-name src ths-compile--root))
                 (elc (funcall byte-compile-dest-file-function file))
                 (ret (condition-case err
                          (byte-compile-file file)
                        ;; 依赖缺失 / 源文件语法错等「抛错型」失败：
                        ;; 不接住会留下未处理 backtrace，且判据（返回值）根本走不到。
                        (error (push (cons src (error-message-string err)) failures)
                               nil))))
            (cond
             ((null ret)
              ;; 已被上一分支记录过的抛错不再重复计入。
              (unless (assoc src failures)
                (push (cons src "byte-compile-file 返回 nil（error 或 warning，详见上方 *Compile-Log*）")
                      failures)))
             ((not (file-exists-p elc))
              (push (cons src (format "未生成 %s" elc)) failures)))))
        (if failures
            (progn
              (princ (format "严格编译失败：%d/%d 个文件未通过\n"
                             (length failures) total))
              (dolist (failure (nreverse failures))
                (princ (format "  ✗ %s：%s\n" (car failure) (cdr failure)))))
          (princ (format "严格编译通过：%d/%d 个源文件零 error 零 warning\n" total total))))
    ;; 无论走哪条分支，临时产物目录都不留。
    (delete-directory dest t))
  ;; 陷阱②：batch 退出码恒为 0，失败必须显式退出，否则 make 假绿。
  (when failures (kill-emacs 1)))

;;; compile-strict.el ends here
