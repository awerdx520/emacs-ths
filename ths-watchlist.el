;;; ths-watchlist.el --- Persistent stock watchlist -*- lexical-binding: t; -*-

;;; Code:
(require 'ths-data)

(defcustom ths-watchlist-file
  (expand-file-name "ths-watchlist.json" user-emacs-directory)
  "File storing watchlist symbols.  Nil keeps changes in the current session."
  :type '(choice (const nil) file) :group 'ths)

(defun ths-watchlist-symbol (input)
  "Normalize stock or ETF/LOF INPUT, inferring the market from trading codes."
  (let ((value (downcase (string-trim input))))
    (when (string-match-p "\\`[0-9]\\{6\\}\\'" value)
      (setq value (concat (or (ths-data-fund-market value)
                             (pcase (aref value 0)
                               (?6 "sh") ((or ?0 ?3) "sz")
                               ((or ?4 ?8 ?9) "bj")
                               (_ (user-error "无法识别市场，请输入 sh、sz 或 bj 前缀"))))
                         value)))
    (unless (and (string-match-p "\\`\\(?:sh\\|sz\\|bj\\|of\\)[0-9]\\{6\\}\\'" value)
                 (not (member value ths-data-index-symbols)))
      (user-error "请输入股票／基金代码；场外基金使用 of 前缀，例如 of005827"))
    value))

(defun ths-watchlist-load ()
  "Read saved symbols without evaluating file content.
An absent file uses the initial watchlist; an empty array stays empty."
  (if (or (null ths-watchlist-file) (not (file-exists-p ths-watchlist-file)))
      '("sz300033" "sz300750" "sh688981")
    (condition-case err
        (with-temp-buffer
          (insert-file-contents ths-watchlist-file)
          (let ((data (json-parse-buffer :array-type 'array :object-type 'alist)))
            (unless (vectorp data) (error "文件内容应为股票代码数组"))
            (delete-dups (mapcar #'ths-watchlist-symbol (append data nil)))))
      (error (user-error "读取自选失败，原文件已保留：%s" (error-message-string err))))))

(defun ths-watchlist-save (symbols)
  "Atomically save SYMBOLS, or signal an error before changing the UI."
  (when ths-watchlist-file
    (let* ((file (expand-file-name ths-watchlist-file))
           (directory (file-name-directory file)) temporary)
      (condition-case err
          (unwind-protect
              (progn
                (make-directory directory t)
                (setq temporary (make-temp-file (expand-file-name ".ths-watchlist-" directory)))
                (let ((coding-system-for-write 'utf-8-unix))
                  (write-region (json-serialize (vconcat symbols)) nil temporary nil 'silent))
                (rename-file temporary file t))
            (when (and temporary (file-exists-p temporary)) (delete-file temporary)))
        (error (user-error "保存自选失败，未修改自选：%s" (error-message-string err)))))))

(provide 'ths-watchlist)
;;; ths-watchlist.el ends here
