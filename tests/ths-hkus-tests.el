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

;;; 分时与日 K（任务3）：真实行格式样本，探测日期 2026-10-22。

(defconst ths-hkus-test-tencent-hk-minute
  (concat "{\"code\":0,\"msg\":\"\",\"data\":{\"hk00700\":{\"data\":{"
          "\"data\":[\"0930 387.000 1655673 640962060.800\","
          "\"1200 390.000 5000000 1950000000.000\","
          "\"1300 389.500 5000001 1950000020.000\","
          "\"1600 380.800 54405891 20022534991.300\"],"
          "\"date\":\"20261022\"},"
          "\"qt\":{\"hk00700\":[\"100\",\"腾讯控股\",\"00700\",\"380.800\",\"393.800\"]},"
          "\"vcm\":\"\"}}}")
  "腾讯港股分时真实形态（探测 2026-10-22）：日期在 data.<code>.data.date，
行 4 列为 HHMM 价 累计量 累计额，行数截断到 4。")

(defconst ths-hkus-test-tencent-us-minute
  (concat "{\"code\":0,\"msg\":\"\",\"data\":{\"usAAPL\":{\"data\":{"
          "\"data\":[\"0930 339.43 349412\",\"1200 341.10 2000000\","
          "\"1600 343.99 35614126\"],\"date\":\"20261021\"},"
          "\"qt\":{\"usAAPL\":[\"200\",\"苹果\",\"AAPL.OQ\",\"343.99\",\"339.50\"]}}}}")
  "腾讯美股分时真实形态（探测 2026-10-22）：层级同港股，行只有 3 列
（HHMM 价 累计量），行数截断到 3。")

(defconst ths-hkus-test-tencent-hk-daily
  (concat "{\"code\":0,\"msg\":\"\",\"data\":{\"hk00700\":{\"day\":["
          "[\"2026-10-20\",\"413.200\",\"410.400\",\"415.600\",\"406.400\",\"22840013.000\"],"
          "[\"2026-10-21\",\"412.000\",\"393.800\",\"413.400\",\"393.800\",\"37783835.000\"]],"
          "\"qt\":{\"hk00700\":[\"100\",\"腾讯控股\",\"00700\",\"380.800\",\"393.800\"]},"
          "\"prec\":\"473.800\"}}}")
  "腾讯港股日 K 真实形态（探测 2026-10-22，fqkline + qfq）：数组键名为 day，
行为 QFQ 调整后的数组 [日期 开 收 高 低 成交量]。")

(defconst ths-hkus-test-tencent-us-daily
  (concat "{\"code\":0,\"msg\":\"\",\"data\":{\"usAAPL.OQ\":{\"qfqday\":["
          "[\"2026-10-20\",\"339.86\",\"339.50\",\"343.06\",\"338.70\",\"35851382.00\"],"
          "[\"2026-10-21\",\"339.36\",\"343.99\",\"345.25\",\"338.83\",\"35614126.00\"]],"
          "\"qt\":{\"usAAPL.OQ\":[\"200\",\"苹果\",\"AAPL.OQ\",\"343.99\",\"339.50\"]},"
          "\"version\":\"12\"}}}")
  "腾讯美股日 K 真实形态（探测 2026-10-22，usfqkline + qfq）：数组键名为
qfqday，data 键带交易所后缀 usAAPL.OQ，行同样为数组。")

(defconst ths-hkus-test-sina-us-daily
  (concat "/*<script>location.href='//sina.com';</script>*/\n"
          "var _AAPL_MinK=([{\"d\":\"2026-10-20\",\"o\":\"339.86\",\"h\":\"343.06\","
          "\"l\":\"338.70\",\"c\":\"339.50\",\"v\":\"35851382\",\"a\":\"12194900000\"},"
          "{\"d\":\"2026-10-21\",\"o\":\"339.36\",\"h\":\"345.25\",\"l\":\"338.83\","
          "\"c\":\"343.99\",\"v\":\"35614107\",\"a\":\"12223100000\"}]);")
  "新浪美股日 K JSONP 真实形态（探测 2026-10-22）：`var _<CODE>_MinK=([...]);'
前有块注释，每条为 d/o/h/l/c/v/a 对象，全历史约 941KB。")

(defun ths-hkus-test-chart-stock (symbol slots base)
  "Return a STOCK plist for SYMBOL with SLOTS and BASE for chart tests."
  (plist-put (list :symbol symbol :price base :intraday-close base
                   :points (cl-loop for (time slot price) in slots
                                    collect (list :time time :slot slot :price price
                                                  :volume 1000)))
             :symbol symbol))

(ert-deftest ths-hkus-minute-slot-hk ()
  "港股槽位按画像两段时段累加：09:30→0、12:00→150、13:00→150、16:00→330。"
  (let ((hk (ths-data-market "hk00700")))
    (should (= 0 (ths-data-minute-slot "09:30" hk)))
    (should (= 150 (ths-data-minute-slot "1200" hk)))
    (should (= 150 (ths-data-minute-slot "13:00" hk)))
    (should (= 330 (ths-data-minute-slot "1600" hk)))
    ;; 符号字符串与画像 plist 等价。
    (should (= 330 (ths-data-minute-slot "1600" "hk00700")))
    ;; 午休空档与收盘后仍报错，不做截断。
    (should-error (ths-data-minute-slot "1215" hk))
    (should-error (ths-data-minute-slot "1601" hk))))

(ert-deftest ths-hkus-minute-slot-us ()
  "美股午间不休息：09:30→0、16:00→390；缺省市场仍是 A 股 240 分钟。"
  (let ((us (ths-data-market "usAAPL")))
    (should (= 0 (ths-data-minute-slot "09:30" us)))
    (should (= 150 (ths-data-minute-slot "12:00" us)))
    (should (= 390 (ths-data-minute-slot "16:00" us)))
    (should-error (ths-data-minute-slot "16:30" us))
    (should (= 0 (ths-data-minute-slot "09:30")))
    (should (= 120 (ths-data-minute-slot "11:30")))
    (should (= 120 (ths-data-minute-slot "13:00")))
    (should (= 240 (ths-data-minute-slot "15:00")))
    (should (= 240 (ths-data-minute-slot "1500" (ths-data-market "sh600519"))))
    (should-error (ths-data-minute-slot "1200"))))

(ert-deftest ths-hkus-intraday-hk-us-parses ()
  "港美分时解析：层级实测为 data.<code>.data.date，港 4 列、美 3 列。"
  (let* ((hk (ths-data--chart ths-hkus-test-tencent-hk-minute "hk00700" 'tencent 'intraday))
         (us (ths-data--chart ths-hkus-test-tencent-us-minute "usAAPL" 'tencent 'intraday))
         (hk-stock (plist-put (copy-sequence hk) :symbol "hk00700"))
         (us-stock (plist-put (copy-sequence us) :symbol "usAAPL")))
    (should (= 4 (length (plist-get hk :points))))
    (should (= 0 (plist-get (car (plist-get hk :points)) :slot)))
    (should (= 330 (plist-get (car (last (plist-get hk :points))) :slot)))
    (should (equal "2026-10-22" (plist-get hk :intraday-date)))
    (should (= 393.8 (plist-get hk :intraday-close)))
    (should (= 3 (length (plist-get us :points))))
    (should (= 0 (plist-get (car (plist-get us :points)) :slot)))
    (should (= 390 (plist-get (car (last (plist-get us :points))) :slot)))
    (should (equal "2026-10-21" (plist-get us :intraday-date)))
    ;; 港行含累计额 → 均价线可用；美行只有累计量 → 均价线必须缺席。
    (should (ths-chart--average-line-p hk-stock))
    (should-not (ths-chart--average-line-p us-stock))))

(ert-deftest ths-hkus-daily-candles-hk-us ()
  "港美日 K：港股键 day、美股键 qfqday，行格式为数组；新浪 JSONP 兜底可解析。"
  (let ((hk (ths-data--chart ths-hkus-test-tencent-hk-daily "hk00700" 'tencent 'daily))
        (us (ths-data--chart ths-hkus-test-tencent-us-daily "usAAPL" 'tencent 'daily))
        (sina (ths-data--chart ths-hkus-test-sina-us-daily "usAAPL" 'sina 'daily)))
    (should (= 2 (length (plist-get hk :candles))))
    (should (equal "2026-10-21" (plist-get (car (last (plist-get hk :candles))) :date)))
    (should (= 393.8 (plist-get (car (last (plist-get hk :candles))) :close)))
    (should (= 2 (length (plist-get us :candles))))
    (should (equal "2026-10-21" (plist-get (car (last (plist-get us :candles))) :date)))
    (should (= 343.99 (plist-get (car (last (plist-get us :candles))) :close)))
    (should (= 2 (length (plist-get sina :candles))))
    (should (= 343.99 (plist-get (car (last (plist-get sina :candles))) :close)))
    (should (= 35614107 (plist-get (car (last (plist-get sina :candles))) :volume)))
    ;; 键名优先级：qfqday 优先，缺了再退回 day；A 股仍只读 day。
    (should (equal '(("a")) (ths-data--tencent-candles
                             '((qfqday ("a")) (day ("b"))) "usAAPL")))
    (should (equal '(("b")) (ths-data--tencent-candles
                             '((qfqday ("a")) (day ("b"))) "sh600519")))
    ;; 真实行格式生成 120 根美股日 K：数量下限与日期形态。
    (let* ((rows (cl-loop for i below 120
                          collect (format "[\"2026-%02d-%02d\",\"1.00\",\"1.10\",\"1.20\",\"0.90\",\"100.00\"]"
                                          (1+ (/ i 28)) (1+ (% i 28)))))
           (text (concat "{\"code\":0,\"data\":{\"usAAPL.OQ\":{\"qfqday\":["
                         (mapconcat #'identity rows ",") "]}}}"))
           (candles (plist-get (ths-data--chart text "usAAPL" 'tencent 'daily) :candles)))
      (should (= 120 (length candles)))
      (should (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'"
                              (plist-get (car (last candles)) :date))))
    ;; 新浪兜底只保留最近 120 根（全历史约一万根）。
    (let* ((rows (cl-loop for i below 130
                          collect (format "{\"d\":\"2026-%02d-%02d\",\"o\":\"1.00\",\"h\":\"1.20\",\"l\":\"0.90\",\"c\":\"1.10\",\"v\":\"100\",\"a\":\"0\"}"
                                          (1+ (/ i 28)) (1+ (% i 28)))))
           (text (concat "var _AAPL_MinK=([" (mapconcat #'identity rows ",") "]);"))
           (candles (plist-get (ths-data--chart text "usAAPL" 'sina 'daily) :candles)))
      (should (= 120 (length candles))))))

(ert-deftest ths-hkus-svg-omits-average-line-us ()
  "美股无均价线：SVG 不出现 mean-line、字符图无均价点；港美股坐标按画像缩放。"
  (let* ((hk (ths-hkus-test-chart-stock
              "hk00700" '(("09:30" 0 387.0) ("12:00" 150 390.0) ("16:00" 330 380.8)) 393.8))
         (us (ths-hkus-test-chart-stock
              "usAAPL" '(("09:30" 0 339.43) ("12:00" 150 341.1) ("16:00" 390 343.99)) 339.5))
         (hk-svg (ths-chart-svg hk)) (us-svg (ths-chart-svg us))
         (hk-line (ths-chart-line hk)) (us-line (ths-chart-line us)))
    (should (string-match-p "id=\"mean-line\"" hk-svg))
    (should-not (string-match-p "mean-line" us-svg))
    ;; 收盘点位贴右边界：330/330 与 390/390 都是 x=644。
    (should (string-match-p "cx=\"644.00\"" hk-svg))
    (should (string-match-p "cx=\"644.00\"" us-svg))
    ;; 轴文案来自画像 :axis-label：港有午休边界，美没有。
    (should (string-match-p "12:00 / 13:00" hk-svg))
    (should-not (string-match-p "11:30 / 13:00" us-svg))
    (should (string-match-p "12:45" us-svg))
    (should (string-match-p ">09:30<" us-svg))
    ;; 字符图：均价点「·」只在港股出现（A 股回归见 ths-chart 既有用例）。
    (should (< (cl-count ?· us-line) (cl-count ?· hk-line)))))

(ert-deftest ths-hkus-url-dispatch ()
  "分时/日 K 端点按市场分派；美股日 K 依赖交易所后缀，缺后缀改走新浪。"
  (should (string-match-p "minute/query\\?code=hk00700"
                          (ths-data--url 'tencent 'intraday "hk00700")))
  (should (string-match-p "usMinute/query\\?code=usAAPL"
                          (ths-data--url 'tencent 'intraday "usAAPL")))
  (should (string-match-p "minute/query\\?code=sh600519"
                          (ths-data--url 'tencent 'intraday "sh600519")))
  (should (string-match-p "fqkline/get\\?param=hk00700,day,,,120,qfq"
                          (ths-data--url 'tencent 'daily "hk00700")))
  (should (string-match-p "fqkline/get\\?param=sh600519,day,,,120,$"
                          (ths-data--url 'tencent 'daily "sh600519")))
  (let ((ths-data-stocks (list (list :symbol "usAAPL" :code "AAPL" :exchange-suffix "OQ"))))
    (should (string-match-p "usfqkline/get\\?param=usAAPL\\.OQ,day,,,120,qfq"
                            (ths-data--url 'tencent 'daily "usAAPL")))
    (should (equal '(tencent sina) (ths-data--providers "usAAPL" 'daily))))
  (let ((ths-data-stocks nil))
    ;; 无后缀禁止拼无后缀 URL，provider 链直接换成新浪兜底。
    (should-error (ths-data--url 'tencent 'daily "usAAPL"))
    (should (equal '(sina) (ths-data--providers "usAAPL" 'daily)))
    (should (string-match-p "US_MinKService.getDailyK\\?symbol=AAPL"
                            (ths-data--url 'sina 'daily "usAAPL"))))
  (should (equal '(tencent) (ths-data--providers "usAAPL" 'intraday)))
  (should (equal '(tencent) (ths-data--providers "hk00700" 'daily))))

(ert-deftest ths-hkus-daily-throttle-us ()
  "美股日 K 与场外基金同档 900 秒节流；A 股日 K 仍按刷新间隔重取。"
  (should (ths--slow-kind-p (list :symbol "usAAPL") 'daily))
  (should-not (ths--slow-kind-p (list :symbol "usAAPL") 'intraday))
  (should (ths--slow-kind-p (list :symbol "of005827") 'quote))
  (should-not (ths--slow-kind-p (list :symbol "sh600519") 'daily))
  (dolist (case '(("usAAPL" . 0) ("sh600519" . 1)))
    (let* ((symbol (car case)) (expected (cdr case)) (code (substring symbol 2))
           (calls nil)
           (stock (list :symbol symbol :code code
                        :daily-fetched-at (- (float-time) 100)))
           (ths-auto-fetch t) (ths--session 'test))
      (cl-letf (((symbol-function 'etaf-value)
                 (lambda (_state) (list :page 'detail :selected code :chart 'daily)))
                ((symbol-function 'ths-data-find) (lambda (_code) stock))
                ((symbol-function 'ths--fetch)
                 (lambda (sym kind) (push (cons sym kind) calls))))
        (ths--ensure-chart))
      (should (= expected (length (seq-filter (lambda (call) (eq (cdr call) 'daily)) calls))))
      (if (= 1 expected)
          (should (member (cons symbol 'daily) calls))
        (should-not (member (cons symbol 'daily) calls))))))

;;; 任务4：搜索映射与自选兼容（东财 code-table 混合样本，离线构造，无网络请求）

(defconst ths-hkus-test-search-response
  (json-serialize
   `((result . ,(vconcat
                 (mapcar (lambda (row)
                           `((code . ,(nth 0 row)) (shortName . ,(nth 1 row))
                             (securityTypeName . ,(nth 2 row))))
                         '(("00700" "腾讯控股" "港股")
                           ("AAPL" "苹果" "美股")
                           ("600519" "贵州茅台" "沪A")
                           ("510300" "沪深300ETF" "沪基")
                           ("AAPL" "苹果" "指数")   ; 同类不同名的非目标样本。
                           ("IXIC" "纳斯达克" "指数") ; 指数必须整体丢弃。
                           ("110001" "可转债" "债券")))))))
  "东财 code-table 港美 / A 股 / 场内基金混合响应。
含两条「指数」样本与一条「债券」样本，用于断言非目标类别不入结果。")

(ert-deftest ths-hkus-search-maps-hk-us ()
  "港股映射 hk 前缀并保留前导零，美股映射 us 并 upcase，非目标类别丢弃。"
  (let* ((rows (ths-data--search-parse ths-hkus-test-search-response))
         (symbols (mapcar (lambda (row) (plist-get row :symbol)) rows))
         (hk (seq-find (lambda (row) (equal "hk00700" (plist-get row :symbol))) rows))
         (us (seq-find (lambda (row) (equal "usAAPL" (plist-get row :symbol))) rows))
         (share (seq-find (lambda (row) (equal "sh600519" (plist-get row :symbol))) rows))
         (fund (seq-find (lambda (row) (equal "sh510300" (plist-get row :symbol))) rows)))
    (should (equal '("hk00700" "usAAPL" "sh600519" "sh510300") symbols))
    ;; 港股：代码保留 5 位前导零，标签来自画像。
    (should (equal "00700" (plist-get hk :code)))
    (should (equal "港股" (plist-get hk :market-label)))
    (should (equal "腾讯控股" (plist-get hk :name)))
    ;; 美股：代码为大写字母，标签来自画像。
    (should (equal "AAPL" (plist-get us :code)))
    (should (equal "美股" (plist-get us :market-label)))
    ;; A 股与场内基金零回归。
    (should (equal "沪A" (plist-get share :market-label)))
    (should (equal "沪基" (plist-get fund :market-label)))
    (should (ths-data-fund-p fund))
    ;; 指数（IXIC）与债券（110001）不得进入结果。
    (should-not (member "usIXIC" symbols))
    (should-not (seq-find (lambda (row) (member (plist-get row :market-label) '("指数" "债券")))
                          rows))))

(ert-deftest ths-hkus-search-rejects-bad-codes ()
  "港美 code 格式不合法时与该函数既有语义一致：整体报错。"
  (dolist (case '(("007000" . "港股")  ; 港股必须 5 位。
                  ("700" . "港股")     ; 位数不足。
                  ("AA1" . "美股")     ; 美股不允许数字。
                  ("bad" . "沪A")))    ; A 股零回归。
    (should-error
     (ths-data--search-parse
      (format "{\"result\":[{\"code\":\"%s\",\"shortName\":\"坏样本\",\"securityTypeName\":\"%s\"}]}"
              (car case) (cdr case)))
     :type 'error)))

(ert-deftest ths-hkus-watchlist-roundtrip ()
  "自选保存并回读港美代码；旧格式（仅 A 股 / 场外基金）JSON 仍可直接读取。"
  (let* ((file (make-temp-file "ths-watchlist-" nil ".json"))
         (ths-watchlist-file file))
    (unwind-protect
        (progn
          (ths-watchlist-save '("hk00700" "usAAPL" "sh600519"))
          (should (equal '("hk00700" "usAAPL" "sh600519") (ths-watchlist-load)))
          ;; 旧文件是纯字符串数组，格式未变 → 向后兼容。
          (let ((coding-system-for-write 'utf-8-unix))
            (with-temp-file file (insert "[\"sz300033\",\"of005827\"]")))
          (should (equal '("sz300033" "of005827") (ths-watchlist-load))))
      (delete-file file))))

(ert-deftest ths-hkus-search-label ()
  "候选标签的市场名来自画像：港美读 港股 / 美股，场内基金保留 沪基。"
  (should (string-match-p "港股" (ths-search--label '(:symbol "hk00700"))))
  (should (string-match-p "美股" (ths-search--label '(:symbol "usAAPL"))))
  (should (string-match-p "沪基" (ths-search--label '(:symbol "sh510300"))))
  ;; 无法识别的符号回退 --，不再按首两字符猜市场。
  (should (string-match-p "--" (ths-search--label '(:symbol "xx000000")))))

(ert-deftest ths-hkus-search-local-matches-hk-us ()
  "本地过滤：带前缀 / 裸代码 / 市场名都能命中港美候选。"
  (let ((session (ths-search--create :local (ths-data--search-parse ths-hkus-test-search-response))))
    (dolist (case '(("hk00700" . "hk00700") ("00700" . "hk00700") ("港股" . "hk00700")
                    ("usAAPL" . "usAAPL") ("aapl" . "usAAPL") ("美股" . "usAAPL")
                    ("600519" . "sh600519")))
      (should (member (cdr case)
                      (mapcar (lambda (row) (plist-get row :symbol))
                              (ths-search--local session (car case))))))
    ;; 市场名互不串味：搜「港股」不会带出美股候选。
    (should-not (member "usAAPL"
                        (mapcar (lambda (row) (plist-get row :symbol))
                                (ths-search--local session "港股"))))))

;;; ths-hkus-tests.el ends here
