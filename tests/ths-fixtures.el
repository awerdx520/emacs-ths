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

;;; 港股 / 美股夹具（数值取自 2026-10-22 腾讯报价真实响应，原始响应体见
;;; tests/ths-hkus-tests.el 的 `ths-hkus-test-tencent-hk-quote' 等 defconst）。
;;
;; 默认 `ths-test--stocks' 保持 A 股 8 只不变：布局列宽、排行榜行数、成交量面板
;; 与 trades 位置断言都依赖它的行数与排序，往默认集里塞港美标的会改变这些断言
;; 的输入。港美样本因此独立成组，需要港美数据的用例自行 append。

(defun ths-test-book-for (stock)
  "Return STOCK's order book using its market profile's level count.
A-share profiles publish five levels, so the result is exactly
`ths-test--book' (delegated, never re-implemented); Hong Kong and US publish
one level each; off-exchange funds publish none at all.  Level prices and
quantities are synthetic and keep the same +/-0.01 ladder as the A-share
fixture, so only the level count differs."
  (let ((levels (plist-get (ths-data-market stock) :book-levels)))
    (cond
     ((or (null levels) (eq levels 5)) (ths-test--book stock))
     ((zerop levels) nil)
     (t (let ((price (plist-get stock :price)))
          (append
           (cl-loop for level downfrom levels to 1
                    collect (list (format "卖%d" level) (+ price (* level 0.01))
                                  (+ 100 (* level 137)) 'ask))
           (cl-loop for level from 1 to levels
                    collect (list (format "买%d" level) (- price (* level 0.01))
                                  (+ 180 (* level 213)) 'bid))))))))

(defconst ths-test--hk-us-quotes
  '((:symbol "hk00700" :code "00700" :name "腾讯控股" :market-label "港股"
     :currency "HKD" :price 380.600 :close 393.800 :open 387.000 :high 391.200
     :low 378.400 :amount 20022534991.3 :turnover 0.0 :volume 52357080 :change -3.35
     :time "2026-10-22 15:13:16"
     ;; 腾讯港股 1 档盘口：该源的档位量恒为 0，不做补值。
     :book (("卖1" 380.600 0.0 ask) ("买1" 380.600 0.0 bid)))
    (:symbol "usAAPL" :code "AAPL" :name "苹果" :market-label "美股"
     :currency "USD" :price 343.99 :close 339.500 :open 339.360 :high 345.250
     :low 338.830 :amount 12221259717.0 :turnover 0.24 :volume 35614126 :change 1.32
     :time "2026-10-21 16:00:01" :exchange-suffix "OQ"
     ;; 腾讯美股 1 档盘口：该源有真实档位量（卖1 80 / 买1 360）。
     :book (("卖1" 343.930 80.0 ask) ("买1" 343.800 360.0 bid))))
  "Hong Kong and US quote fixtures parsed from the 2026-10-22 Tencent responses.
Prices keep the market's own decimals (HK three, US two) and volumes are
share counts, not lots, because the profile's :volume-unit is 股.")

(defun ths-test--full-stock (stock)
  "Return STOCK with the generated points/candles and the remaining UI fields.
The intraday point count is the profile's :minutes plus the closing endpoint
(HK 331, US 391), matching how the chart counts a full session."
  (let* ((minutes (plist-get (ths-data-market stock) :minutes))
         (date "2026-10-22"))
    (append (copy-sequence stock)
            (list :points (cl-loop for price in (ths-test--series stock (1+ (or minutes 240)))
                                   for i from 0
                                   collect (list :slot i :price price
                                                 :volume (+ 100 (* (mod i 17) 30))))
                  :candles (mapcar (lambda (c) (append c (list :date date)))
                                   (ths-test--candles stock))
                  :quote-source 'tencent :intraday-source 'tencent :daily-source 'tencent
                  :quote-fetched-at 1 :intraday-date date))))

(defconst ths-test-hk-stock
  (ths-test--full-stock (car ths-test--hk-us-quotes))
  "港股夹具 hk00700（腾讯控股）：1 档盘口、331 个分时点、3 位小数价格。")

(defconst ths-test-us-stock
  (ths-test--full-stock (cadr ths-test--hk-us-quotes))
  "美股夹具 usAAPL（苹果）：1 档盘口、391 个分时点、带交易所后缀 OQ。")

(defconst ths-test--hk-us-stocks (list ths-test-hk-stock ths-test-us-stock)
  "港美夹具列表，顺序为港股在前、美股在后；需要时 append 到 `ths-test-stocks'。")

(provide 'ths-fixtures)
;;; ths-fixtures.el ends here
