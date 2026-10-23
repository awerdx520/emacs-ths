;;; ths-live-check.el --- Optional public endpoint smoke check -*- lexical-binding: t; -*-
;;; Commentary:
;; Run with make live-check.  Requires network; excluded from make check.
;;
;; 检查项分三类，判据只看「是否真实失败」：
;;   1. 腾讯 / 新浪项 —— 真实请求，失败即置 failed（退出码 1）；
;;   2. 东财（eastmoney）项 —— 本机不可达，只打印 `skip（东财本机不可达）'，
;;      既不计数也不参与失败判定（不可达既不能美化成通过，也不该误报为回归）；
;;   3. A 股榜单 —— 数据源链是「东财 → 新浪」，仍按真实项执行，报告里附实际
;;      应答的数据源，因此东财不可达时由新浪兜底，不会假装东财通过。
;;
;; 港股 / 美股项（探测日期 2026-10-22）：腾讯 hk00700 / usAAPL 报价、港股分时
;; （4 列 HHMM 价 累计量 累计额）、港股日 K（fqkline qfq，键 day）、美股日 K
;; （usfqkline qfq，键 qfqday；缺交易所后缀时自动回退新浪）、新浪港股榜与美股榜
;; 的 total 量级下限（线上数字会漂移，只判量级、不固着具体数字）。
;;
;; `pending' 不写死：检查项先注册、再取注册数，增删检查项无需同步改数字，也不会
;; 出现「等不到回调就超时」的假失败。
;;; Code:
(require 'cl-lib)
(require 'ths-data)

(defconst ths-live-check--eastmoney-skip "skip（东财本机不可达）"
  "东财端点在本机不可达：相关检查项只标 skip，不置 failed。")

(defconst ths-live-check--min-total '((hkstock . 500) (usstock . 1000))
  "港美榜单 total 的量级下限。
2026-10-22 实测港股 2492 / 美股 18324，线上总数会漂移，故只判量级。")

(defun ths-live-check--render (kind result)
  "Return a one-line description of RESULT for KIND.
KIND is quote, intraday, daily or ranking; the provider that answered is
appended when the response carries :source."
  (let ((detail
         (pcase kind
           ('quote (format "%s %s %s" (plist-get result :name)
                           (plist-get result :price) (plist-get result :time)))
           ('intraday (format "%s, %d points" (plist-get result :intraday-date)
                              (length (plist-get result :points))))
           ('daily (let ((candles (plist-get result :candles)))
                     (format "%d candles, last %s" (length candles)
                             (plist-get (car (last candles)) :date))))
           ('ranking (format "%d rows / %d securities"
                             (length (plist-get result :rows))
                             (plist-get result :total)))
           (_ (format "%S" result))))
        (source (plist-get result :source)))
    (if source (format "%s [%s]" detail source) detail)))

(defun ths-live-check--total-failure (universe result)
  "Return an error string when RESULT's total is below UNIVERSE's floor."
  (let ((floor (alist-get universe ths-live-check--min-total)))
    (when floor
      (let ((total (plist-get result :total)))
        (unless (and (integerp total) (>= total floor))
          (format "total %s 低于量级下限 %d" total floor))))))

(let ((pending 0) (registered 0) (skipped 0) (failed nil) cancels)
  (cl-labels
      ((skip (label)
         (cl-incf skipped)
         (princ (format "%s: %s\n" label ths-live-check--eastmoney-skip)))
       (report (label kind failure result)
         (cl-decf pending)
         (when failure (setq failed t))
         (princ (format "%s: %s\n" label
                        (or failure (ths-live-check--render kind result)))))
       (job (_label thunk)
         ;; _LABEL 只为调用点可读：报告在回调里用同一个 label，故此处不读它。
         (cl-incf pending)
         (cl-incf registered)
         ;; 同步失败的回调会在该调用内就 decrement pending，因此先计数再调用。
         (push (funcall thunk) cancels)))
    (unwind-protect
        (progn
          ;; 1) 东财项：本机不可达，只标 skip；不注册，故不计入 pending。
          (dolist (label '("eastmoney / search（贵州茅台）"
                           "eastmoney / quote（sz300033）"
                           "eastmoney / intraday（sz300033）"
                           "eastmoney / daily（sz300033）"
                           "eastmoney / trades（sz300033）"))
            (skip label))
          ;; 2) 腾讯 / 新浪报价、分时、日 K：A 股 + 港股 + 美股。
          (dolist (spec '(("sz300033" quote tencent "A 股报价（腾讯）")
                          ("sz300033" intraday tencent "A 股分时（腾讯）")
                          ("sz300033" daily tencent "A 股日 K（腾讯）")
                          ("hk00700" quote tencent "港股报价（腾讯 → 新浪兜底）")
                          ("hk00700" intraday tencent "港股分时（腾讯 4 列）")
                          ("hk00700" daily tencent "港股日 K（腾讯 fqkline qfq）")
                          ("usAAPL" quote tencent "美股报价（腾讯 → 新浪兜底）")
                          ("usAAPL" daily tencent "美股日 K（腾讯 usfqkline → 新浪兜底）")))
            (pcase-let ((`(,symbol ,kind ,provider ,label) spec))
              (job label
                   (lambda ()
                     (let ((ths-data-providers (list provider))
                           ;; 美股日 K 的腾讯端点需要交易所后缀；真实流程由报价
                           ;; 写入，这里预置一条快照使其走 usfqkline，失败再回退新浪。
                           (ths-data-stocks
                            (when (equal symbol "usAAPL")
                              (list (list :symbol "usAAPL" :code "AAPL"
                                          :exchange-suffix "OQ")))))
                       (ths-data-fetch
                        symbol kind
                        (lambda (result failure)
                          (report label kind failure result))))))))
          ;; 3) 榜单：A 股 / ETF / LOF（东财 → 新浪兜底）+ 港股 / 美股（新浪）。
          (dolist (universe '(stock etf lof hkstock usstock))
            (dolist (sort '(change amount))
              (let ((category universe)
                    (metric sort)
                    (label (format "ranking / %s-%s" universe sort)))
                (job label
                     (lambda ()
                       (ths-data-fetch-ranking
                        metric 1
                        (lambda (result failure)
                          (report label 'ranking
                                  (or failure
                                      (ths-live-check--total-failure category result))
                                  result))
                        category))))))
          ;; 所有检查并发在跑，等待上限按「单请求超时 × 数据源链深度」估，留余量。
          (let ((deadline (+ (float-time) (* 6 ths-data-timeout) 5)))
            (while (and (> pending 0) (< (float-time) deadline))
              (accept-process-output nil 0.1)))
          (when (> pending 0)
            (setq failed t)
            (princ (format "Timed out with %d unfinished checks\n" pending)))
          (princ (format "live-check: %d checks, %d skipped（东财本机不可达）, %s\n"
                         registered skipped (if failed "FAILED" "ok"))))
      (mapc #'funcall cancels))
    ;; 任一真实失败 → 1；全部 pass / skip → 0。
    (kill-emacs (if failed 1 0))))
;;; ths-live-check.el ends here
