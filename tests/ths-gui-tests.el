;;; ths-gui-tests.el --- Real display geometry regression -*- lexical-binding: t; -*-
;;; Commentary:
;; Load in graphical Emacs, then run ERT selector ths-gui-chart-geometry.
;;; Code:
(require 'ert)
(require 'ths)
(load (expand-file-name "ths-fixtures.el" (file-name-directory load-file-name)) nil t)

(defun ths-gui-test--image (display)
  "Find an image descriptor nested in DISPLAY."
  (cond ((eq (car-safe display) 'image) display)
        ((consp display) (or (ths-gui-test--image (car display))
                             (ths-gui-test--image (cdr display))))))

(ert-deftest ths-gui-chart-geometry ()
  "Image slices must share an X origin and match real row height after zoom."
  (skip-unless (and (display-graphic-p) (image-type-available-p 'svg)))
  (save-window-excursion
    (let* ((ths-auto-fetch nil) (ths-watchlist-file nil)
           (ths-buffer-name " *ths-gui-test*") (buffer (ths)))
      (unwind-protect
          (progn
            (switch-to-buffer buffer)
            (setq ths-data-stocks (ths-test-stocks))
            (ths--publish)
            (ths-refit)
            (dolist (chart '(intraday daily))
              (ths--set ths--state :chart chart)
              (dolist (scale '(0 1 -1))
                (text-scale-set scale)
                (redisplay t)
                ;; Allow ETAF's settled font-metric notification to publish.
                (sleep-for 0.4)
                (redisplay t)
                (let* ((runtime (etaf-runtime-for-buffer buffer))
                       (metrics (etaf-display-metrics runtime))
                       (row-height (plist-get metrics :line-height))
                       (chart-size (etaf-host-ref-size runtime (if (eq chart 'intraday) 'intraday-chart 'daily-chart)))
                       (viewport (etaf-runtime-viewport runtime))
                       (pos (point-min)) slices)
                  (should (<= (cdr (window-text-pixel-size nil (point-min) (point-max)))
                              (window-body-height nil t)))
                  (should (= (window-start) (point-min)))
                  (while (< pos (point-max))
                    (when-let* ((image (ths-gui-test--image (get-text-property pos 'display))))
                      (save-excursion
                        (goto-char pos)
                        (let* ((begin (line-beginning-position)) (end (line-end-position))
                               (line (window-text-pixel-size nil begin end)))
                          (should (= (cdr line) row-height))
                          (should (<= (car line) (car viewport)))
                          (should (= (car (image-size image t)) (car chart-size)))
                          (push (car (window-text-pixel-size nil begin pos)) slices))))
                    (setq pos (next-single-property-change pos 'display nil (point-max))))
                  (should (<= 4 (length slices) (cdr viewport)))
                  (should (= (length slices) (cdr (etaf-host-ref-size runtime 'chart-region))))
                  (should (= (cdr chart-size) (length slices)))
                  (should (cl-every (lambda (x) (= x (car slices))) slices))))))
        (when (buffer-live-p buffer) (kill-buffer buffer))))))
;;; ths-gui-tests.el ends here
