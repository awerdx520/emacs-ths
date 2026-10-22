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

;;; 任务5：排行榜（新浪港美榜单样本，探测日期 2026-10-22）。
;; 线上总数（港股 2492 / 美股 18324）会漂移，样本改为 3 条记录 + 总数 3，
;; 用于断言「行数与 total 一致」这一结构事实，不固着线上数字。

(defconst ths-hkus-test-sina-hk-ranking
  (concat "[{\"symbol\":\"00385\",\"name\":\"建联集团\",\"engname\":\"CHINNEY ALLI\","
          "\"lasttrade\":\"0.32000\",\"prevclose\":\"0.23900\",\"open\":\"0.26000\","
          "\"high\":\"0.34500\",\"low\":\"0.24600\",\"volume\":\"475200\","
          "\"amount\":\"138408\",\"ticktime\":\"2026/10/22 15:59:59\","
          "\"pricechange\":\"0.01600\",\"changepercent\":\"33.89121\","
          "\"market_value\":\"0\",\"pe_ratio\":\"0\"},"
          "{\"symbol\":\"02938\",\"name\":\"帝王国际投资－旧\",\"engname\":\"KING INTL OLD\","
          "\"lasttrade\":\"0.50000\",\"prevclose\":\"0.47000\",\"open\":\"0.48000\","
          "\"high\":\"0.51000\",\"low\":\"0.47000\",\"volume\":\"120000\","
          "\"amount\":\"59000\",\"ticktime\":\"2026/10/22 15:59:59\","
          "\"pricechange\":\"0.03000\",\"changepercent\":\"6.38298\","
          "\"market_value\":\"0\",\"pe_ratio\":\"0\"},"
          "{\"symbol\":\"00700\",\"name\":\"腾讯控股\",\"engname\":\"TENCENT\","
          "\"lasttrade\":\"380.60000\",\"prevclose\":\"393.80000\",\"open\":\"387.00000\","
          "\"high\":\"391.20000\",\"low\":\"378.40000\",\"volume\":\"51371074\","
          "\"amount\":\"19647253727\",\"ticktime\":\"2026/10/22 15:59:59\","
          "\"pricechange\":\"-13.20000\",\"changepercent\":\"-3.25038\","
          "\"market_value\":\"0\",\"pe_ratio\":\"0\"}]")
  "新浪港股榜裸 JSON 数组首页样本（24 个字符串字段，截为 3 条）。")

(defconst ths-hkus-test-sina-us-ranking
  (concat "/*<script>location.href='//sina.com';</script>*/\n"
          "var t=({\"count\":\"3\",\"data\":["
          "{\"name\":\"OceanLight Acquisition Corp\",\"cname\":\"OceanLight Acquisition Corp\","
          "\"symbol\":\"OCLTR\",\"price\":\"0.28\",\"diff\":\"0.14\",\"chg\":\"99.29\","
          "\"preclose\":\"0.14\",\"open\":\"0.15\",\"high\":\"0.30\",\"low\":\"0.14\","
          "\"amplitude\":\"11.06%\",\"volume\":\"15503\",\"mktcap\":\"358000\",\"market\":\"NASDAQ\"},"
          "{\"name\":\"NVDA\",\"cname\":\"英伟达公司\",\"symbol\":\"NVDA\",\"price\":\"221.97\","
          "\"diff\":\"5.50\",\"chg\":\"2.54\",\"preclose\":\"216.47\",\"open\":\"217.00\","
          "\"high\":\"222.50\",\"low\":\"216.20\",\"amplitude\":\"2.91%\",\"volume\":\"87085661\","
          "\"mktcap\":\"5400000000\",\"market\":\"NASDAQ\"},"
          "{\"name\":\"AAPL\",\"cname\":\"苹果公司\",\"symbol\":\"AAPL\",\"price\":\"261.10\","
          "\"diff\":\"1.20\",\"chg\":\"0.46\",\"preclose\":\"259.90\",\"open\":\"260.00\","
          "\"high\":\"261.80\",\"low\":\"259.50\",\"amplitude\":\"0.88%\",\"volume\":\"41234567\","
          "\"mktcap\":\"3900000000\",\"market\":\"NASDAQ\"}]});")
  "新浪美股榜 JSONP 首页样本：块注释 + `var t=({count,data});`，截为 3 条。
注意美股榜单体内没有成交额字段。")

(ert-deftest ths-hkus-ranking-urls ()
  "港美榜单走新浪端点；东财港美分支直接报错，不发请求；A 股 / ETF / LOF 不变。"
  (let ((hk-change (ths-data--ranking-sina-url 'change 1 nil 'hkstock))
        (hk-amount (ths-data--ranking-sina-url 'amount 2 nil 'hkstock))
        (hk-count (ths-data--ranking-sina-url 'change 1 t 'hkstock))
        (us-change (ths-data--ranking-sina-url 'change 1 nil 'usstock))
        (us-amount (ths-data--ranking-sina-url 'amount 1 nil 'usstock)))
    (should (string-match-p "Market_Center.getHKStockData" hk-change))
    (should (string-match-p "node=qbgg_hk" hk-change))
    (should (string-match-p "sort=changepercent&asc=0" hk-change))
    (should (string-match-p "page=2&num=20" hk-amount))
    (should (string-match-p "sort=amount&asc=0" hk-amount))
    (should (string-match-p "getHKStockCount" hk-count))
    (should (string-match-p "node=qbgg_hk" hk-count))
    (should (string-match-p "US_CategoryService.getList" us-change))
    (should (string-match-p "sort=chg&asc=0" us-change))
    (should (string-match-p "sort=amount&asc=0" us-amount)))
  ;; 东财港美分支：报错跳过，不构造请求。
  (dolist (universe '(hkstock usstock))
    (dolist (sort '(change amount))
      (should-error (ths-data--ranking-url sort 1 nil universe))
      (should-error (ths-data--ranking-url sort 1 t universe))))
  ;; A 股 / ETF / LOF 的东财 URL 零回归。
  (should (string-match-p "82.push2.eastmoney.com" (ths-data--ranking-url 'change 1 nil 'stock)))
  (should (string-match-p "fs=m:0" (ths-data--ranking-url 'change 1 nil 'stock)))
  (should (string-match-p "b:MK0021" (ths-data--ranking-url 'change 1 nil 'etf)))
  (should (string-match-p "b:MK0404" (ths-data--ranking-url 'change 1 nil 'lof)))
  (should (string-match-p "node=hs_a" (ths-data--ranking-sina-url 'change 1 nil 'stock)))
  (should (string-match-p "node=etf_hq_fund" (ths-data--ranking-sina-url 'change 1 nil 'etf)))
  (should (string-match-p "node=lof_hq_fund" (ths-data--ranking-sina-url 'change 1 nil 'lof))))

(ert-deftest ths-hkus-ranking-parse-total ()
  "港股榜裸数组解析出 3 行、total 与缺失字段；美股榜从体内读 count。"
  (let ((hk (ths-data--ranking-sina-parse ths-hkus-test-sina-hk-ranking 'change 1 3 'hkstock))
        (us (ths-data--ranking-sina-parse ths-hkus-test-sina-us-ranking 'change 1 nil 'usstock)))
    (should (eq 'hkstock (plist-get hk :universe)))
    (should (= 3 (plist-get hk :total)))
    (should (= 3 (length (plist-get hk :rows))))
    (should (equal '("hk00385" "hk02938" "hk00700")
                   (mapcar (lambda (row) (plist-get row :symbol)) (plist-get hk :rows))))
    (let ((row (car (plist-get hk :rows))))
      (should (= 1 (plist-get row :rank)))
      (should (equal "00385" (plist-get row :code)))
      (should (equal "建联集团" (plist-get row :name)))
      (should (= 0.32 (plist-get row :price)))
      (should (= 33.89121 (plist-get row :change)))
      (should (= 475200 (plist-get row :volume)))
      (should (= 138408 (plist-get row :amount)))
      (should (= 0.239 (plist-get row :close)))
      ;; 港股榜单无换手率 / 流通市值 / 60 日涨跌幅 → nil，不填 0。
      (should-not (plist-get row :turnover))
      (should-not (plist-get row :float-cap))
      (should-not (plist-get row :change-60d)))
    ;; 港股代码保留 5 位前导零。
    (should (equal "00700" (plist-get (nth 2 (plist-get hk :rows)) :code)))
    ;; 美股：JSONP 剥离包裹，总数来自体内 count。
    (should (eq 'usstock (plist-get us :universe)))
    (should (= 3 (plist-get us :total)))
    (should (equal '("usOCLTR" "usNVDA" "usAAPL")
                   (mapcar (lambda (row) (plist-get row :symbol)) (plist-get us :rows))))
    (let ((row (car (plist-get us :rows))))
      (should (equal "OCLTR" (plist-get row :code)))
      (should (= 0.28 (plist-get row :price)))
      (should (= 99.29 (plist-get row :change)))
      (should (= 15503 (plist-get row :volume)))
      (should (= 0.14 (plist-get row :close)))
      ;; 美股榜单无成交额 / 流通市值 / 60 日涨跌幅 → nil。
      (should-not (plist-get row :amount))
      (should-not (plist-get row :float-cap))
      (should-not (plist-get row :change-60d)))
    ;; 单独 count 端点样本（JSON 字符串）与行数一致性校验。
    (should (= 3 (ths-data--ranking-sina-count "\"3\"")))
    (should-error (ths-data--ranking-sina-parse ths-hkus-test-sina-hk-ranking 'change 1 4 'hkstock))
    (should-error (ths-data--ranking-sina-us-parse
                   (replace-regexp-in-string "\"count\":\"3\"" "\"count\":\"4\""
                                             ths-hkus-test-sina-us-ranking t t)
                   'change 1))
    ;; 港股样本喂给美股解析器必须报错（格式不兼容，不做猜测）。
    (should-error (ths-data--ranking-sina-us-parse ths-hkus-test-sina-hk-ranking 'change 1))))

(ert-deftest ths-hkus-ranking-fetch-skips-eastmoney-and-reads-inline-count ()
  "港美榜单只请求新浪；港股先取总数再取榜，美股单请求并读体内 count。"
  (let (urls result failure)
    (cl-letf (((symbol-function 'ths-data--http)
               (lambda (url _provider callback)
                 (push url urls)
                 (funcall callback
                          (cond ((string-match-p "getHKStockCount" url) "\"3\"")
                                ((string-match-p "getHKStockData" url) ths-hkus-test-sina-hk-ranking)
                                (t ths-hkus-test-sina-us-ranking))
                          nil)
                 #'ignore)))
      (ths-data-fetch-ranking 'change 1 (lambda (data err) (setq result data failure err)) 'hkstock)
      (should-not failure)
      (should (= 2 (length urls)))
      (should (cl-every (lambda (url) (string-match-p "sina" url)) urls))
      (should (= 3 (plist-get result :total)))
      (should (equal "hk00385" (plist-get (car (plist-get result :rows)) :symbol)))
      (setq urls nil result nil failure nil)
      (ths-data-fetch-ranking 'amount 1 (lambda (data err) (setq result data failure err)) 'usstock)
      (should-not failure)
      ;; 美股只发一次请求，不请求单独的 count 端点。
      (should (= 1 (length urls)))
      (should (string-match-p "US_CategoryService.getList" (car urls)))
      (should (= 3 (plist-get result :total)))
      (should (equal "usOCLTR" (plist-get (car (plist-get result :rows)) :symbol))))))

(ert-deftest ths-hkus-ranking-us-symbols ()
  "港美代码映射与标签：美股 upcase 保留点号，港股保留 5 位前导零。"
  (should (equal "usAAPL" (ths-data--ranking-symbol "aapl" nil 'usstock)))
  (should (equal "usAAPL" (ths-data--ranking-symbol "AAPL" nil 'usstock)))
  (should (equal "us.IXIC" (ths-data--ranking-symbol ".ixic" nil 'usstock)))
  (dolist (bad '("" "1234" "AA1"))
    (should-not (ths-data--ranking-symbol bad nil 'usstock)))
  (should (equal "hk00700" (ths-data--ranking-symbol "00700" nil 'hkstock)))
  (dolist (bad '("700" "007000" "HK00700"))
    (should-not (ths-data--ranking-symbol bad nil 'hkstock)))
  (should (equal "港股" (ths-data-ranking-label 'hkstock)))
  (should (equal "美股" (ths-data-ranking-label 'usstock)))
  (should (equal "A 股" (ths-data-ranking-label 'stock)))
  (should (equal "ETF" (ths-data-ranking-label 'etf)))
  (should (equal "LOF" (ths-data-ranking-label 'lof)))
  (should-error (ths-data-ranking-universe 'unknown)))

(ert-deftest ths-hkus-ranking-cycle-5-states ()
  "u 键循环 5 态：A股 → ETF → LOF → 港股 → 美股 → A股。"
  (ths-test-with-dashboard
    (should (eq #'ths-ranking-cycle-universe (key-binding (kbd "u"))))
    (dolist (universe '(etf lof hkstock usstock))
      (call-interactively #'ths-ranking-cycle-universe)
      (should (eq universe (plist-get (etaf-value ths--state) :ranking-universe)))
      (should (ths-test-visible (ths-data-ranking-label universe))))
    (call-interactively #'ths-ranking-cycle-universe)
    (should (eq 'stock (plist-get (etaf-value ths--state) :ranking-universe)))))

(ert-deftest ths-hkus-ranking-narrow-window-hides-hk-us-buttons ()
  "窄窗口（44 列）只显示 5 个按钮，港美按钮从 ths--ranking-hk-us-buttons 列起出现。"
  (ths-test-with-dashboard
    (ths-show-ranking)
    (let ((runtime (etaf-runtime-for-buffer buffer)))
      (dolist (width '(44 54 79 80))
        (etaf-runtime-refit runtime width 24)
        (dolist (ref '(rank-stock rank-etf rank-lof rank-change rank-amount))
          (should (etaf-host-ref-position runtime ref)))
        (if (>= width ths--ranking-hk-us-buttons)
            (dolist (ref '(rank-hkstock rank-usstock))
              (let ((pos (etaf-host-ref-position runtime ref)))
                (should pos)
                (should (= 3 (line-number-at-pos pos)))
                (save-excursion
                  (goto-char pos)
                  (should (<= (+ (current-column) (car (etaf-host-ref-size runtime ref)))
                              (1- width))))))
          (should-not (etaf-host-ref-position runtime 'rank-hkstock))
          (should-not (etaf-host-ref-position runtime 'rank-usstock)))))))

;;; ths-hkus-tests.el ends here
