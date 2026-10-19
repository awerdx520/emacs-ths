;;; ths-fixtures.el --- Offline test data only -*- lexical-binding: t; -*-
(require 'ths-data)
(defconst ths-test--stocks
  '((:code "300033" :name "同花顺"   :sector "金融科技" :close 168.00 :price 173.88 :amount 2863000000 :turnover 4.26)
    (:code "300750" :name "宁德时代" :sector "电池"     :close 256.00 :price 260.35 :amount 4218000000 :turnover 1.72)
    (:code "600519" :name "贵州茅台" :sector "白酒"     :close 1480.0 :price 1465.20 :amount 3157000000 :turnover 0.38)
    (:code "002594" :name "比亚迪"   :sector "汽车整车" :close 285.00 :price 291.84 :amount 3652000000 :turnover 2.11)
    (:code "601318" :name "中国平安" :sector "保险"     :close 48.60  :price 48.12  :amount 1623000000 :turnover 0.67)
    (:code "600036" :name "招商银行" :sector "银行"     :close 37.20  :price 37.20  :amount 1205000000 :turnover 0.42)
    (:code "688981" :name "中芯国际" :sector "半导体"   :close 92.00  :price 95.86  :amount 5581000000 :turnover 3.86)
    (:code "300059" :name "东方财富" :sector "证券"     :close 21.60  :price 22.46  :amount 4827000000 :turnover 5.13))
  "Synthetic fixtures.  Numbers are deliberately not dated market quotes.")

(defun ths-test--series (stock &optional count)
  "Return COUNT synthetic intraday prices for STOCK, ending at its price."
  (let* ((count (max 2 (or count 48)))
         (base (plist-get stock :close))
         (delta (- (plist-get stock :price) base))
         (phase (/ (string-to-number (substring (plist-get stock :code) -2)) 10.0)))
    (cl-loop for i below count
             for ratio = (/ (float i) (1- count))
             collect (+ base (* delta ratio)
                        (* base 0.006 (sin (* float-pi ratio))
                           (sin (+ phase (* ratio 19))))))))

(defun ths-test--candles (stock &optional count)
  "Return COUNT synthetic OHLC candles for STOCK."
  (let* ((prices (ths-test--series stock (1+ (or count 24))))
         (base (plist-get stock :close)))
    (cl-loop for (open close) on prices while close
             for i from 0
             collect (list :open open :close close :volume (+ 5000 (* i 700))
                           :high (+ (max open close) (* base (+ 0.002 (* 0.001 (abs (sin i))))))
                           :low (- (min open close) (* base (+ 0.002 (* 0.001 (abs (cos i))))))))))

(defun ths-test--book (stock)
  "Return synthetic five-level order book for STOCK, asks then bids."
  (let ((price (plist-get stock :price)))
    (append
     (cl-loop for level downfrom 5 to 1
              collect (list (format "卖%d" level) (+ price (* level 0.01))
                            (+ 100 (* level 137)) 'ask))
     (cl-loop for level from 1 to 5
              collect (list (format "买%d" level) (- price (* level 0.01))
                            (+ 180 (* level 213)) 'bid)))))


(defun ths-test-stocks ()
  "Generate isolated UI fixtures.  Never loaded by the application."
  (mapcar
   (lambda (stock)
     (append (copy-sequence stock)
             (list :symbol (concat (if (string-prefix-p "6" (plist-get stock :code)) "sh" "sz")
                                   (plist-get stock :code))
                   :points (cl-loop for price in (ths-test--series stock 241) for i from 0
                                    collect (list :slot i :price price :volume (+ 100 (* (mod i 17) 30))))
                   :candles (mapcar (lambda (c) (append c '(:date "2026-10-15"))) (ths-test--candles stock))
                   :book (ths-test--book stock) :quote-source 'tencent :intraday-source 'tencent
                   :daily-source 'tencent :quote-fetched-at 1 :time "2026-10-15 15:00:00"
                   :intraday-date "2026-10-15"))) ths-test--stocks))

(provide 'ths-fixtures)
;;; ths-fixtures.el ends here
