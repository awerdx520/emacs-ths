;;; ths-hkus-tests.el --- Hong Kong / US support regressions -*- lexical-binding: t; -*-

;;; Commentary:
;; 港股 / 美股支持用例。任务1 落符号矩阵与画像表骨架，任务7 在同一文件扩充
;; 探测夹具与其余用例。本文件只断言符号与画像层，不发起任何网络请求。

;;; Code:
(require 'ert)
(require 'ths)

(ert-deftest ths-symbol-matrix ()
  "合法符号归一为带前缀形态，非法输入一律报错。"
  (dolist (pair '(("sh600519" . "sh600519") ("bj920001" . "bj920001")
                  ("of005827" . "of005827") ("hk00700" . "hk00700")
                  ("usAAPL" . "usAAPL") ("usaapl" . "usAAPL")
                  ("us.IXIC" . "us.IXIC") ("us.ixic" . "us.IXIC")
                  ("  hk00700 " . "hk00700")))
    (should (equal (cdr pair) (ths-data-symbol (car pair)))))
  (dolist (input '("" "600519" "hk700" "hk007000" "us" "us123"
                   "xx300033" "hkHSI" "sz3990010"))
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

;;; ths-hkus-tests.el ends here
