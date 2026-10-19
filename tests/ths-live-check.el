;;; ths-live-check.el --- Optional public endpoint smoke check -*- lexical-binding: t; -*-
;;; Commentary:
;; Run with make live-check.  Requires network; excluded from make check.
;;; Code:
(require 'ths-data)
(let ((pending 11) (failed nil) cancels)
  (unwind-protect
      (progn
        (push (ths-data-search
               "贵州茅台"
               (lambda (rows failure)
                 (cl-decf pending)
                 (unless (seq-some (lambda (stock) (equal (plist-get stock :symbol) "sh600519")) rows)
                   (setq failure (or failure "Expected sh600519 in search results")))
                 (when failure (setq failed t))
                 (princ (format "eastmoney / search: %s\n"
                                (or failure (format "%d A-share candidates" (length rows))))))) cancels)
        (dolist (job '((tencent quote) (eastmoney quote) (sina quote)
                       (tencent intraday) (eastmoney intraday)
                       (tencent daily) (eastmoney daily) (eastmoney trades)))
          (let ((ths-data-providers (list (car job)))
                (provider (car job)) (kind (cadr job)))
            (push (ths-data-fetch
                   "sz300033" kind
                   (lambda (result failure)
                     (cl-decf pending)
                     (when failure (setq failed t))
                     (princ (format "%s / %s: %s\n" provider kind
                                    (or failure
                                        (pcase kind
                                          ('quote (format "%s %s %s" (plist-get result :name)
                                                          (plist-get result :price) (plist-get result :time)))
                                          ('intraday (format "%s, %d points" (plist-get result :intraday-date)
                                                             (length (plist-get result :points))))
                                          ('trades (format "%d records, latest %s" (length (plist-get result :trades))
                                                           (plist-get (car (plist-get result :trades)) :time)))
                                          ('daily (format "%d candles, last %s" (length (plist-get result :candles))
                                                          (plist-get (car (last (plist-get result :candles))) :date)))))))))
                  cancels)))
        (dolist (sort '(change amount))
          (let ((metric sort))
            (push (ths-data-fetch-ranking
                   metric 1
                   (lambda (result failure)
                     (cl-decf pending)
                     (when failure (setq failed t))
                     (princ (format "%s / ranking-%s: %s\n" (plist-get result :source) metric
                                    (or failure (format "%d rows / %d stocks"
                                                        (length (plist-get result :rows))
                                                        (plist-get result :total)))))))
                  cancels)))
        (let ((deadline (+ (float-time) (* 4 ths-data-timeout) 5)))
          (while (and (> pending 0) (< (float-time) deadline))
            (accept-process-output nil 0.1)))
        (when (> pending 0)
          (setq failed t)
          (princ (format "Timed out with %d unfinished checks\n" pending))))
    (mapc #'funcall cancels))
  (kill-emacs (if failed 1 0)))
;;; ths-live-check.el ends here
