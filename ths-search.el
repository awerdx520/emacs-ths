;;; ths-search.el --- Asynchronous stock suggestions -*- lexical-binding: t; -*-

;;; Code:
(require 'ths-watchlist)
(require 'minibuffer)

;; Optional completion frontend; THS also works without Vertico installed.
(defvar vertico-mode)
(defvar vertico--input)
(defvar vertico--candidates-ov)
(declare-function vertico--exhibit "ext:vertico")

(cl-defstruct (ths-search--session (:constructor ths-search--create))
  buffer local rows labels query timer cancel (generation 0) (active t) status overlay)
(defvar-local ths-search--current nil)

(defun ths-search--label (stock)
  "Return a searchable completion label for STOCK."
  (format "%s  %s  %s%s" (plist-get stock :symbol) (plist-get stock :name)
          (or (plist-get stock :market-label)
              (pcase (substring (plist-get stock :symbol) 0 2) ("sh" "沪A") ("sz" "深A") (_ "京A")))
          (if (string-empty-p (or (plist-get stock :pinyin) "")) ""
            (concat "  " (plist-get stock :pinyin)))))

(defun ths-search--local (session query)
  "Return SESSION's known stocks matching QUERY."
  (seq-filter (lambda (stock)
                (string-match-p (regexp-quote (downcase query)) (downcase (ths-search--label stock))))
              (ths-search--session-local session)))

(defun ths-search--set-rows (session rows)
  "Store deduplicated ROWS and their completion labels in SESSION."
  (let ((seen (make-hash-table :test #'equal)) unique)
    (dolist (row rows)
      (unless (gethash (plist-get row :symbol) seen)
        (puthash (plist-get row :symbol) t seen)
        (push row unique)))
    (setf (ths-search--session-rows session) (nreverse unique)
          (ths-search--session-labels session)
          (mapcar (lambda (row) (cons (ths-search--label row) row)) (ths-search--session-rows session)))))

(defun ths-search--cancel (session)
  "Cancel pending timer and request owned by SESSION."
  (when (timerp (ths-search--session-timer session)) (cancel-timer (ths-search--session-timer session)))
  (when (functionp (ths-search--session-cancel session)) (funcall (ths-search--session-cancel session)))
  (setf (ths-search--session-timer session) nil (ths-search--session-cancel session) nil))

(defun ths-search--close (session)
  "Dispose SESSION and ignore all later callbacks."
  (setf (ths-search--session-active session) nil)
  (ths-search--cancel session)
  (when (overlayp (ths-search--session-overlay session)) (delete-overlay (ths-search--session-overlay session)))
  (when (buffer-live-p (ths-search--session-buffer session))
    (with-current-buffer (ths-search--session-buffer session)
      (when (eq ths-search--current session)
        (remove-hook 'post-command-hook #'ths-search--changed t)
        (setq ths-search--current nil)))))

(defun ths-search--notify (session)
  "Update SESSION's status and the active completion frontend."
  (let ((window (active-minibuffer-window)))
    (when (and (ths-search--session-active session) window
               (eq (window-buffer window) (ths-search--session-buffer session)))
      (with-selected-window window
        (let ((overlay (ths-search--session-overlay session)))
          (when (overlayp overlay)
            (move-overlay overlay (point-max) (point-max))
            (overlay-put overlay 'after-string
                         (propertize (concat "  [" (ths-search--session-status session) "]") 'face 'shadow))))
        (cond
         ((bound-and-true-p vertico-mode)
          ;; The table changes asynchronously while the input stays the same.
          ;; Invalidate Vertico's input cache so it recomputes the candidates.
          ;; Setup hooks may run before Vertico has created its overlays.
          (when (and (overlayp (bound-and-true-p vertico--candidates-ov))
                     (fboundp 'vertico--exhibit))
            (setq-local vertico--input t)
            (vertico--exhibit)))
         ((ths-search--session-rows session)
          (let ((completion-auto-help t)) (minibuffer-completion-help)))
         (t
          (with-output-to-temp-buffer "*Completions*"
            (princ (ths-search--session-status session)))))))))

(defun ths-search--setup (session)
  "Attach SESSION to the minibuffer without replacing frontend bindings."
  (setq-local ths-search--current session)
  (unless (bound-and-true-p vertico-mode)
    (use-local-map (copy-keymap (current-local-map)))
    (local-set-key (kbd "<down>") #'minibuffer-next-completion)
    (local-set-key (kbd "<up>") #'minibuffer-previous-completion))
  (setf (ths-search--session-buffer session) (current-buffer)
        (ths-search--session-overlay session) (make-overlay (point-max) (point-max) nil t t))
  (add-hook 'post-command-hook #'ths-search--changed nil t)
  (ths-search--changed))

(defun ths-search--request (session query generation)
  "Fetch QUERY only while SESSION still owns GENERATION."
  (when (and (ths-search--session-active session) (= generation (ths-search--session-generation session)))
    (let ((cancel
           (ths-data-search
            (if (string-match "\\`\\(?:sh\\|sz\\|bj\\)\\([0-9]+\\)\\'" query) (match-string 1 query) query)
            (lambda (rows failure)
              (when (and (ths-search--session-active session) (= generation (ths-search--session-generation session)))
                (setf (ths-search--session-cancel session) nil)
                (ths-search--set-rows session (append rows (ths-search--local session query)))
                (setf (ths-search--session-status session)
                      (cond (failure "在线搜索失败；可选本地结果或输入完整代码")
                            ((ths-search--session-rows session) "↑↓ 选择候选，RET 添加；C-g 取消")
                            (t "没有匹配的 A 股，请换个关键词")))
                (ths-search--notify session))))))
      ;; Cancellation is harmless for an already completed HTTP request.
      (when (and (ths-search--session-active session) (= generation (ths-search--session-generation session)))
        (setf (ths-search--session-cancel session) cancel)))))

(defun ths-search--update (session query)
  "Refresh local suggestions and debounce online QUERY for SESSION."
  (unless (or (equal query (ths-search--session-query session))
              (assoc-string query (ths-search--session-labels session) t))
    (cl-incf (ths-search--session-generation session))
    (ths-search--cancel session)
    (setf (ths-search--session-query session) query)
    (ths-search--set-rows session (ths-search--local session query))
    (setf (ths-search--session-status session)
          (if (string-empty-p query) "输入股票／场内基金代码或名称；TAB 选择候选" "搜索中…"))
    (unless (string-empty-p query)
      (setf (ths-search--session-timer session)
            (run-with-idle-timer 0.3 nil #'ths-search--request session query (ths-search--session-generation session))))
    (ths-search--notify session)))

(defun ths-search--changed ()
  "Observe edits to this search minibuffer."
  (when ths-search--current
    (ths-search--update ths-search--current (downcase (string-trim (minibuffer-contents-no-properties))))))

(defun ths-search--table (session string pred action)
  "Implement completion for STRING, PRED and ACTION from SESSION."
  (cond ((eq action 'metadata) '(metadata (category . ths-stock) (display-sort-function . identity)))
        ((and (eq action 'lambda) (ignore-errors (ths-watchlist-symbol string))) t)
        (t (complete-with-action action (ths-search--session-labels session) string pred))))

(defun ths-search-read (stocks)
  "Read a stock using async online suggestions and local STOCKS.
Return metadata for the chosen candidate, or a placeholder for a typed code."
  (let* ((session (ths-search--create :local (copy-tree stocks)))
         (completion-styles '(substring basic))
         (completion-category-overrides '((ths-stock (styles substring basic))))
         (completion-ignore-case t)
         (completion-show-help nil)
         (completions-format 'one-column)
         (completion-auto-select nil)
         (minibuffer-completion-auto-choose t))
    (unwind-protect
        (save-window-excursion
          (minibuffer-with-setup-hook
              (lambda () (ths-search--setup session))
            (let* ((answer (completing-read "添加自选（代码 / 名称）: "
                                             (lambda (string pred action) (ths-search--table session string pred action)) nil t))
                   (stock (cdr (assoc-string answer (ths-search--session-labels session) t))))
              (or stock (ths-data-placeholder (ths-watchlist-symbol answer))))))
      (ths-search--close session))))

(provide 'ths-search)
;;; ths-search.el ends here
