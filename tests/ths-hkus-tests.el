;;; ths-hkus-tests.el --- Hong Kong / US support regressions -*- lexical-binding: t; -*-

;;; Commentary:
;; 港股 / 美股支持用例。任务1 落符号矩阵与画像表骨架，任务2 补报价解析与
;; provider 路由（真实响应夹具），任务7 继续扩充其余用例。本文件只断言符号、
;; 画像与解析层，不发起任何网络请求。

;;; Code:
(require 'ert)
(require 'ths)

(defconst ths-hkus-test-tencent-hk-quote
  "v_hk00700=\"100~腾讯控股~00700~380.600~393.800~387.000~52357080.0~0~0~380.600~0~0~0~0~0~0~0~0~0~380.600~0~0~0~0~0~0~0~0~0~52357080.0~2026/10/22 15:13:16~-13.200~-3.35~391.200~378.400~380.600~52357080.0~20022534991.300~0~13.90\";"
  "腾讯港股报价真实响应（探测 2026-10-22，截断到 f39，f0..f38 位置完整）。")

(defconst ths-hkus-test-tencent-us-quote
  "v_usAAPL=\"200~苹果~AAPL.OQ~343.99~339.50~339.36~35614126~0~0~343.80~360~0~0~0~0~0~0~0~0~343.93~80~0~0~0~0~0~0~0~0~~2026-10-21 16:00:01~4.49~1.32~345.25~338.83~USD~35614126~12221259717~0.24\";"
  "腾讯美股报价真实响应（探测 2026-10-22，截断到 f38，f0..f38 位置完整）。")

(defconst ths-hkus-test-sina-hk-quote
  "var hq_str_hk00700=\"TENCENT,腾讯控股,387.000,393.800,391.200,378.400,380.800,-13.000,-3.301,380.60001,380.79999,19647253727,51371074,0.000,0.000,656.353,378.400,2026/10/22,15:02\";"
  "新浪港股报价真实响应（探测 2026-10-22，19 字段）。")

(defconst ths-hkus-test-sina-us-quote
  "var hq_str_gb_aapl=\"苹果,343.9900,1.32,2026-10-22 09:30:13,4.4900,339.3600,345.2500,338.8300,348.1500,242.8900,35614126,39244484,5020252050093,8.30,41.440000,0.00,0.00,0.00,0.00,14594180209,63,343.8900,-0.03,-0.10,Oct 21 07:59PM EDT,Oct 21 04:00PM EDT,339.5000,4174623,1,2026,12223111721.0000,344.1799,343.5000,1436007934.9952,344.0500,339.5000\";"
  "新浪美股报价真实响应（探测 2026-10-22，36 字段）。")

(ert-deftest ths-symbol-matrix ()
  "合法符号归一为带前缀形态，非法输入一律报错。"
  (dolist (pair '(("sh600519" . "sh600519") ("bj920001" . "bj920001")
                  ("of005827" . "of005827") ("hk00700" . "hk00700")
                  ("hkHSI" . "hkHSI") ("hk hscei" . "hkHSCEI")
                  ("usAAPL" . "usAAPL") ("usaapl" . "usAAPL")
                  ("us.IXIC" . "us.IXIC") ("us.ixic" . "us.IXIC")
                  ("  hk00700 " . "hk00700")))
    (should (equal (cdr pair) (ths-data-symbol (car pair)))))
  (dolist (input '("" "600519" "hk700" "hk007000" "us" "us123"
                   "xx300033" "hkA" "sz3990010"))
    (should-error (ths-data-symbol input) :type 'error)))

(ert-deftest ths-hkus-market-profile ()
  "画像表是市场事实的单一来源，港美与 A 股取值各自成立。"
  (let ((hk (ths-data-market "hk00700"))
        (us (ths-data-market "usAAPL"))
        (sh (ths-data-market "sh600519")))
    (should (equal "HKD" (plist-get hk :currency)))
    (should (= 330 (plist-get hk :minutes)))
    (should (= 1 (plist-get hk :book-levels)))
    (should (equal "USD" (plist-get us :currency)))
    (should (= 390 (plist-get us :minutes)))
    (should (= 1 (plist-get us :book-levels)))
    (should (equal "CNY" (plist-get sh :currency)))
    (should (= 240 (plist-get sh :minutes)))
    (should (= 5 (plist-get sh :book-levels)))
    (should (equal "us" (ths-data-market-key "us.IXIC")))
    (should (equal "hk" (ths-data-market-key '(:symbol "hk00700"))))
    (should (= 330 (plist-get (ths-data-market '(:symbol "hk00700")) :minutes)))
    (should-not (ths-data-market "xx300033"))
    (should-not (ths-data-market-key "x"))))

(ert-deftest ths-hkus-symbol-id-and-fund-p ()
  "港美符号不参与场内基金判定，symbol-id 只剥两字符前缀。"
  (should (equal "00700" (ths-data-symbol-id "hk00700")))
  (should (equal ".IXIC" (ths-data-symbol-id "us.IXIC")))
  (should-not (ths-data-fund-p '(:symbol "hk00700")))
  (should-not (ths-data-fund-p '(:symbol "usAAPL")))
  (should-not (ths-data-fund-p '(:symbol "of005827")))
  (should (ths-data-fund-p '(:symbol "sh510300")))
  (should-not (ths-data-fund-p '(:symbol "sh600519"))))

(ert-deftest ths-hkus-format-price-decimals ()
  "价格小数位由画像决定：hk 3 位、us 2 位、场外基金 4 位、场内基金 3 位。"
  (should (equal "1.235" (ths-data-format-price '(:symbol "hk00700") 1.234567)))
  (should (equal "1.23" (ths-data-format-price '(:symbol "usAAPL") 1.234567)))
  (should (equal "1.2346" (ths-data-format-price '(:symbol "of005827") 1.234567)))
  (should (equal "1.235" (ths-data-format-price '(:symbol "sh510300") 1.234567)))
  (should (equal "1.23" (ths-data-format-price '(:symbol "sh600519") 1.234567)))
  (should (equal "--" (ths-data-format-price '(:symbol "hk00700") nil))))

(ert-deftest ths-hkus-watchlist-symbol ()
  "自选入口放行港美前缀，5 位纯数字提示补 hk 前缀。"
  (should (equal "hk00700" (ths-watchlist-symbol "hk00700")))
  (should (equal "usAAPL" (ths-watchlist-symbol "usaapl")))
  (should (equal "hk00700" (ths-watchlist-symbol "  hk00700 ")))
  (should-error (ths-watchlist-symbol "00700") :type 'user-error))

(ert-deftest ths-hkus-quote-tencent-parses ()
  "腾讯港美报价：现价/昨收/归一化时间/1 档盘口/美股交易所后缀。"
  (let ((hk (ths-data--quote-tencent ths-hkus-test-tencent-hk-quote "hk00700"))
        (us (ths-data--quote-tencent ths-hkus-test-tencent-us-quote "usAAPL")))
    (should (= 380.6 (plist-get hk :price)))
    (should (= 393.8 (plist-get hk :close)))
    (should (= 387.0 (plist-get hk :open)))
    (should (= 391.2 (plist-get hk :high)))
    (should (= 378.4 (plist-get hk :low)))
    (should (equal "2026-10-22 15:13:16" (plist-get hk :time)))
    (should (= 2 (length (plist-get hk :book))))
    (should (equal "卖1" (nth 0 (nth 0 (plist-get hk :book)))))
    (should (= 380.6 (nth 1 (nth 0 (plist-get hk :book)))))
    (should (eq 'ask (nth 3 (nth 0 (plist-get hk :book)))))
    (should (equal "买1" (nth 0 (nth 1 (plist-get hk :book)))))
    (should (eq 'bid (nth 3 (nth 1 (plist-get hk :book)))))
    (should-not (plist-get hk :exchange-suffix))
    (should (= 343.99 (plist-get us :price)))
    (should (= 339.5 (plist-get us :close)))
    (should (equal "OQ" (plist-get us :exchange-suffix)))
    (should (= 12221259717 (plist-get us :amount)))
    ;; 美股 f30 已是 %F %T，解析器必须原样保留而不改写。
    (should (equal "2026-10-21 16:00:01" (plist-get us :time)))
    (should (= 2 (length (plist-get us :book))))))

(ert-deftest ths-hkus-quote-sina-parses ()
  "新浪港美报价：字段布局与 A 股不同，港美各用专用解析器。"
  (let ((hk (ths-data--quote-sina-hk ths-hkus-test-sina-hk-quote "hk00700"))
        (us (ths-data--quote-sina-us ths-hkus-test-sina-us-quote "usAAPL")))
    (should (equal "腾讯控股" (plist-get hk :name)))
    (should (= 380.8 (plist-get hk :price)))
    (should (= 393.8 (plist-get hk :close)))
    (should (= 387.0 (plist-get hk :open)))
    (should (= 391.2 (plist-get hk :high)))
    (should (= 378.4 (plist-get hk :low)))
    (should (= 19647253727 (plist-get hk :amount)))
    ;; 港股源只有 HH:MM，缺秒按 0 补齐后归一到 %F %T。
    (should (equal "2026-10-22 15:02:00" (plist-get hk :time)))
    (should (= 2 (length (plist-get hk :book))))
    (should (equal "卖1" (nth 0 (nth 0 (plist-get hk :book)))))
    (should (= 380.79999 (nth 1 (nth 0 (plist-get hk :book)))))
    (should-not (nth 2 (nth 0 (plist-get hk :book))))
    (should (equal "买1" (nth 0 (nth 1 (plist-get hk :book)))))
    (should (= 380.60001 (nth 1 (nth 1 (plist-get hk :book)))))
    (should-not (nth 2 (nth 1 (plist-get hk :book))))
    (should (equal "苹果" (plist-get us :name)))
    (should (= 343.99 (plist-get us :price)))
    (should (= 339.5 (plist-get us :close)))
    (should (= 339.36 (plist-get us :open)))
    (should (= 345.25 (plist-get us :high)))
    (should (= 338.83 (plist-get us :low)))
    (should (= 12223111721 (plist-get us :amount)))
    (should (equal "2026-10-22 09:30:13" (plist-get us :time)))
    ;; 该源无盘口，禁止伪造档位。
    (should-not (plist-get us :book))
    (should-error (ths-data--quote-sina-us
                   "var hq_str_gb_aapl=\"苹果,343.99\";" "usAAPL"))
    (should-error (ths-data--quote-sina-hk
                   "var hq_str_hk00700=\"TENCENT\";" "hk00700"))))

(ert-deftest ths-hkus-quote-amount-scale ()
  "成交额倍数按画像分派：A 股万元折元 ×10000，港美原币 ×1。"
  (let ((a (ths-data--quote-tencent ths-test-tencent "sz300033"))
        (hk (ths-data--quote-tencent ths-hkus-test-tencent-hk-quote "hk00700"))
        (us (ths-data--quote-tencent ths-hkus-test-tencent-us-quote "usAAPL")))
    ;; A 股 f37 = 286300 万元 → 2863000000 元（回归）。
    (should (= 2863000000 (plist-get a :amount)))
    ;; 港美 f37 已是原币，倍数为 1，不含任何汇率换算。
    (should (= 20022534991.3 (plist-get hk :amount)))
    (should (= 12221259717 (plist-get us :amount)))))

(ert-deftest ths-hkus-quote-single-level-book ()
  "港美盘口只有 1 档：总两行且不含第 5 档；A 股仍为 5 档。"
  (dolist (quote (list (ths-data--quote-tencent ths-hkus-test-tencent-hk-quote "hk00700")
                       (ths-data--quote-tencent ths-hkus-test-tencent-us-quote "usAAPL")
                       (ths-data--quote-sina-hk ths-hkus-test-sina-hk-quote "hk00700")))
    (let ((book (plist-get quote :book)))
      (should (= 2 (length book)))
      (should-not (cl-some (lambda (row) (member (car row) '("卖5" "买5"))) book))
      (should (equal '("卖1" "买1") (mapcar #'car book)))))
  (should (= 10 (length (plist-get (ths-data--quote-tencent ths-test-tencent "sz300033")
                                   :book)))))

(ert-deftest ths-hkus-fetch-refuses-trades ()
  "港美不提供成交明细：立即回调失败且不发起任何 HTTP；A 股仍发请求。"
  (dolist (symbol '("hk00700" "usAAPL"))
    (let ((calls 0) failure)
      (cl-letf (((symbol-function 'ths-data--http)
                 (lambda (&rest _args) (cl-incf calls) #'ignore)))
        (ths-data-fetch symbol 'trades (lambda (_plist error) (setq failure error))))
      (should (= 0 calls))
      (should (stringp failure))))
  (let ((calls 0))
    (cl-letf (((symbol-function 'ths-data--http)
               (lambda (&rest _args) (cl-incf calls) #'ignore)))
      (ths-data-fetch "sh600519" 'trades #'ignore))
    (should (= 1 calls))))

;;; ths-hkus-tests.el ends here
