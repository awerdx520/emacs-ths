;;; ths-diagnose.el --- Capture the live THS layout -*- lexical-binding: t; -*-
;;; Commentary:
;; Load in the GUI Emacs showing THS.  Reads layout, writes ths-diagnostic.eldata.
;;; Code:
(require 'cl-lib)
(require 'pp)
(require 'etaf)

(defun ths-diagnose--display (value)
  "Summarize display VALUE without embedding SVG data."
  (cond
   ((eq (car-safe value) 'image)
    (let ((properties (copy-tree (cdr value))))
      (when (plist-get properties :data)
        (setq properties (plist-put properties :data "<image data omitted>")))
      (list :image properties :actual-pixels
            (condition-case err (image-size value t)
              (error (error-message-string err))))))
   ((consp value) (cons (ths-diagnose--display (car value))
                       (ths-diagnose--display (cdr value))))
   (t value)))

(let* ((root (file-name-directory (or load-file-name buffer-file-name)))
       (buffer (get-buffer (if (boundp 'ths-buffer-name) ths-buffer-name "*同花顺*")))
       (window (and buffer (get-buffer-window buffer t)))
       (file (expand-file-name "ths-diagnostic.eldata" root)))
  (unless window (user-error "请先显示 *同花顺* 窗口，再加载诊断文件"))
  (with-selected-window window
    (let* ((runtime (etaf-runtime-for-buffer buffer))
           (report
            (list :emacs emacs-version
                  :window (list :columns (window-body-width window)
                                :pixels (window-body-width window t)
                                :height (window-body-height window t)
                                :start (window-start window)
                                :point (window-point window))
                  :font (face-attribute 'default :font nil t)
                  :remapping face-remapping-alist
                  :line-spacing line-spacing
                  :state (and (boundp 'ths--state) (etaf-value ths--state))
                  :metrics (etaf-display-metrics runtime)
                  :viewport (etaf-runtime-viewport runtime)
                  :window-viewport (etaf-runtime-window-viewport runtime)
                  :hosts (mapcar
                          (lambda (ref)
                            (list ref (etaf-host-ref-size runtime ref)
                                  (etaf-host-ref-bounds runtime ref)))
                          '(intraday-chart daily-chart stock-300033 intraday daily favorite-toggle))
                  :lines
                  (save-excursion
                    (goto-char (point-min))
                    (let (lines)
                      (while (< (point) (point-max))
                        (let* ((begin (line-beginning-position))
                               (end (line-end-position)) (pos begin) runs)
                          (while (< pos end)
                            (let ((next (min end (next-property-change pos nil end))))
                              (push (list (- pos begin)
                                          (buffer-substring-no-properties pos next)
                                          :display (ths-diagnose--display (get-text-property pos 'display))
                                          :face (get-text-property pos 'face)) runs)
                              (setq pos next)))
                          (push (list :line (line-number-at-pos begin)
                                      :pixel-size (window-text-pixel-size window begin end)
                                      :runs (nreverse runs)) lines))
                        (forward-line 1))
                      (nreverse lines))))))
      (with-temp-file file (let ((print-length nil) (print-level nil)) (pp report (current-buffer))))
      (message "THS 诊断已保存：%s" file))))
;;; ths-diagnose.el ends here
