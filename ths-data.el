;;; ths-data.el --- Public market data providers for THS -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Asynchronous HTTPS quotes, intraday points and unadjusted daily candles.
;; Provider responses are parsed as data, never evaluated as JavaScript/Lisp.
;; No credentials or synthetic market values are used.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'json)
(require 'url-util)

(defgroup ths nil "Market dashboard using ETAF." :group 'applications)
(defcustom ths-data-providers '(tencent eastmoney sina)
  "Quote providers in fallback order.  Sina is skipped for charts."
  :type '(repeat (choice (const tencent) (const eastmoney) (const sina))) :group 'ths)
(defcustom ths-data-ranking-providers '(eastmoney sina)
  "Market ranking providers in fallback order, independent of quote providers."
  :type '(repeat (choice (const eastmoney) (const sina))) :group 'ths)
(defcustom ths-data-timeout 10
  "Maximum seconds for each provider request."
  :type 'natnum :group 'ths)
(defcustom ths-data-curl-program "curl"
  "Curl executable used for asynchronous HTTPS requests."
  :type 'string :group 'ths)
(defcustom ths-data-symbols
  '("sz300033" "sz300750" "sh600519" "sz002594" "sh601318" "sh600036" "sh688981" "sz300059")
  "Stock and exchange-traded fund symbols to show, with market prefixes."
  :type '(repeat string) :group 'ths)
(defconst ths-data-index-symbols '("sh000001" "sz399001" "sz399006"))
(defconst ths-data-trades-count 12 "Maximum recent trade records per stock.")
(defconst ths-data--metadata
  '(("sz300033" "同花顺" "金融科技") ("sz300750" "宁德时代" "电池")
    ("sh600519" "贵州茅台" "白酒") ("sz002594" "比亚迪" "汽车整车")
    ("sh601318" "中国平安" "保险") ("sh600036" "招商银行" "银行")
    ("sh688981" "中芯国际" "半导体") ("sz300059" "东方财富" "证券")
    ("sh000001" "上证指数" "指数") ("sz399001" "深证成指" "指数")
    ("sz399006" "创业板指" "指数"))
  "Display names/categories only; these are not market quotes.")
(defvar-local ths-data-stocks nil "Last successful stock snapshots in this buffer.")
(defvar-local ths-data-indices nil "Last successful index snapshots in this buffer.")

(defun ths-data-symbol (symbol)
  "Validate and normalize a market-qualified SYMBOL."
  (let ((value (downcase (string-trim symbol))))
    (unless (string-match-p "\\`\\(?:sh\\|sz\\|bj\\)[0-9]\\{6\\}\\'" value)
      (error "股票代码须含市场前缀，例如 sz300033: %s" symbol))
    value))

(defun ths-data-fund-market (code)
  "Return the market prefix for an ETF/LOF trading CODE, or nil.
This recognizes code ranges, not whether an individual fund is listed."
  (when (and (stringp code) (string-match-p "\\`[0-9]\\{6\\}\\'" code))
    (cond ((string-match-p "\\`\\(?:50[12]\\|5[1268][0-9]\\)" code) "sh")
          ((string-match-p "\\`1[56]" code) "sz"))))

(defun ths-data-fund-p (stock)
  "Return non-nil when STOCK has an ETF/LOF trading symbol."
  (let ((symbol (plist-get stock :symbol)))
    (and (stringp symbol) (= (length symbol) 8)
         (equal (substring symbol 0 2)
                (ths-data-fund-market (substring symbol 2))))))

(defun ths-data-format-price (stock value &optional signed)
  "Format VALUE for STOCK, using three decimals for funds.
SIGNED includes a sign for price changes.  Missing values stay unavailable."
  (if (numberp value)
      (format (if (ths-data-fund-p stock)
                  (if signed "%+.3f" "%.3f")
                (if signed "%+.2f" "%.2f"))
              value)
    "--"))

(defun ths-data-placeholder (symbol)
  "Return metadata for SYMBOL with no invented quote values."
  (setq symbol (ths-data-symbol symbol))
  (let ((meta (assoc symbol ths-data--metadata))
        (fund (ths-data-fund-p (list :symbol symbol))))
    (list :symbol symbol :code (substring symbol 2)
          :name (or (nth 1 meta) (substring symbol 2))
          :sector (or (nth 2 meta) (if fund "场内基金" "--"))
          :market-label (if fund (if (string-prefix-p "sh" symbol) "沪基" "深基")
                          (pcase (substring symbol 0 2)
                            ("sh" "沪A") ("sz" "深A") (_ "京A"))))))

(defun ths-data-change (stock)
  "Return percentage change for STOCK, or nil if unavailable."
  (let ((price (plist-get stock :price)) (close (plist-get stock :close)))
    (when (and (numberp price) (numberp close) (> price 0) (> close 0))
      (* 100.0 (/ (- price close) (float close))))))

(defun ths-data-find (code)
  "Return stock matching CODE, or nil."
  (seq-find (lambda (stock) (equal code (plist-get stock :code))) ths-data-stocks))

(defun ths-data-filter (query favorites only-favorites sorted)
  "Filter stocks by QUERY, FAVORITES, ONLY-FAVORITES and SORTED."
  (let ((stocks
         (seq-filter
          (lambda (stock)
            (and (or (not only-favorites) (member (plist-get stock :code) favorites))
                 (or (string-empty-p query)
                     (cl-some (lambda (key) (string-match-p (regexp-quote query)
                                                            (or (plist-get stock key) "")))
                              '(:code :name :sector))))) ths-data-stocks)))
    (if sorted
        (cl-stable-sort (copy-sequence stocks)
                        (lambda (a b) (> (or (ths-data-change a) -1.0e+99)
                                         (or (ths-data-change b) -1.0e+99))))
      stocks)))

(defun ths-data-series (stock &optional count)
  "Return actual intraday prices for STOCK, sampling at most COUNT points."
  (let* ((prices (mapcar (lambda (p) (plist-get p :price)) (plist-get stock :points)))
         (n (length prices)))
    (if (and count (> n count) (> count 1))
        (cl-loop for i below count collect (nth (round (* i (/ (float (1- n)) (1- count)))) prices))
      prices)))

(defun ths-data-chart-base (stock)
  "Return the previous close belonging to STOCK's intraday session.
Do not pair a cached older chart with a newer quote's previous close."
  (or (plist-get stock :intraday-close)
      (when (and (plist-get stock :intraday-date) (plist-get stock :time)
                 (string-prefix-p (plist-get stock :intraday-date) (plist-get stock :time)))
        (plist-get stock :close))))

(defun ths-data-candles (stock &optional count)
  "Return the latest COUNT actual daily candles for STOCK."
  (let ((candles (plist-get stock :candles)))
    (last candles (or count 24))))

(defun ths-data-book (stock)
  "Return STOCK's actual asks then bids; quantities are lots of 100 shares."
  (plist-get stock :book))

(defun ths-data-number (value)
  "Parse numeric VALUE strictly; unavailable values remain nil."
  (cond ((numberp value) value)
        ((and (stringp value)
              (string-match-p "\\`[-+]?[0-9]+\\(?:\\.[0-9]+\\)?\\'" value))
         (string-to-number value))))

(defun ths-data--positive (value)
  "Parse VALUE as a positive number or return nil."
  (let ((n (ths-data-number value))) (and n (> n 0) n)))

(defun ths-data--scale (value scale)
  "Divide numeric VALUE by SCALE, preserving missing values."
  (when-let* ((n (ths-data-number value))) (/ n (float scale))))

(defun ths-data--json (text)
  "Parse JSON TEXT with symbol keys and list arrays."
  (json-parse-string text :object-type 'alist :array-type 'list :null-object nil :false-object nil))

(defun ths-data--get (object &rest keys)
  "Read nested KEYS in JSON OBJECT."
  (dolist (key keys object) (setq object (alist-get (intern key) object))))

(defun ths-data--fields (text prefix separator)
  "Extract quoted fields from TEXT matching PREFIX, split by SEPARATOR."
  (unless (string-match (concat (regexp-quote prefix) "[ \t]*=[ \t]*\"\\([^\"]*\\)\"") text)
    (error "行情响应格式不正确"))
  (split-string (match-string 1 text) separator nil))

(defun ths-data--timestamp (text)
  "Normalize a provider's compact date/time TEXT."
  (if (and (stringp text) (string-match-p "\\`[0-9]\\{14\\}\\'" text))
      (format "%s-%s-%s %s:%s:%s" (substring text 0 4) (substring text 4 6)
              (substring text 6 8) (substring text 8 10) (substring text 10 12) (substring text 12 14))
    text))

(defun ths-data--book-rows (getter ask-start bid-start volume-first divisor &optional step)
  "Build book from GETTER at ASK-START/BID-START.
VOLUME-FIRST describes field order; DIVISOR converts quantities to lots.
STEP is the field-index increment between levels (default 2)."
  (cl-loop for side in '(ask bid) for start in (list ask-start bid-start)
           append
           (cl-loop for level in (if (eq side 'ask) '(5 4 3 2 1) '(1 2 3 4 5))
                    for i = (+ start (* (or step 2) (1- level)))
                    collect (list (format "%s%d" (if (eq side 'ask) "卖" "买") level)
                                  (ths-data--positive (funcall getter (+ i (if volume-first 1 0))))
                                  (ths-data--scale (funcall getter (+ i (if volume-first 0 1))) divisor)
                                  side))))

(defun ths-data--quote-tencent (text symbol)
  "Parse Tencent quote TEXT for SYMBOL."
  (let* ((fields (ths-data--fields text (concat "v_" symbol) "~"))
         (get (lambda (i) (nth i fields))))
    (unless (and (>= (length fields) 39) (equal (nth 2 fields) (substring symbol 2)))
      (error "腾讯行情为空或代码不匹配"))
    (list :name (nth 1 fields) :price (ths-data--positive (nth 3 fields))
          :close (ths-data--positive (nth 4 fields)) :open (ths-data--positive (nth 5 fields))
          :high (ths-data--positive (nth 33 fields)) :low (ths-data--positive (nth 34 fields))
          :amount (when-let* ((n (ths-data-number (nth 37 fields)))) (* n 10000.0))
          :turnover (ths-data-number (nth 38 fields))
          :time (ths-data--timestamp (nth 30 fields))
          :book (ths-data--book-rows get 19 9 nil 1))))

(defun ths-data--quote-sina (text symbol)
  "Parse Sina quote TEXT for SYMBOL; share quantities become lots."
  (let* ((fields (ths-data--fields text (concat "hq_str_" symbol) ","))
         (get (lambda (i) (nth i fields))))
    (unless (>= (length fields) 32) (error "新浪行情为空"))
    (list :name (nth 0 fields) :price (ths-data--positive (nth 3 fields))
          :close (ths-data--positive (nth 2 fields)) :open (ths-data--positive (nth 1 fields))
          :high (ths-data--positive (nth 4 fields)) :low (ths-data--positive (nth 5 fields))
          :amount (ths-data-number (nth 9 fields)) :turnover nil
          :time (concat (nth 30 fields) " " (nth 31 fields))
          :book (ths-data--book-rows get 20 10 t 100))))

(defun ths-data--quote-eastmoney (text symbol)
  "Parse Eastmoney quote TEXT for SYMBOL (fltt=2, prices in yuan)."
  (let* ((data (ths-data--get (ths-data--json text) "data"))
         (get (lambda (n) (ths-data--get data (format "f%d" n)))))
    (unless (equal (funcall get 57) (substring symbol 2)) (error "东方财富行情为空或代码不匹配"))
    (list :name (funcall get 58) :price (ths-data--positive (funcall get 43))
          :close (ths-data--positive (funcall get 60)) :open (ths-data--positive (funcall get 46))
          :high (ths-data--positive (funcall get 44)) :low (ths-data--positive (funcall get 45))
          :amount (ths-data-number (funcall get 48)) :turnover (ths-data-number (funcall get 168))
          :time (when-let* ((stamp (ths-data--positive (funcall get 86))))
                  (format-time-string "%F %T" (seconds-to-time stamp) 28800))
          ;; Eastmoney numbers levels backwards: ask1=f39, ask5=f31;
          ;; bid1=f19, bid5=f11.  Quantities are already lots.
          :book (ths-data--book-rows get 39 19 nil 1 -2))))

(defun ths-data-minute-slot (time)
  "Map HH:MM or HHMM TIME to trading minutes since 09:30, excluding lunch."
  (let ((digits (replace-regexp-in-string ":" "" time)))
    (unless (string-match-p "\\`[0-9]\\{4\\}\\'" digits) (error "无效分时时间: %s" time))
    (when (> (string-to-number (substring digits 2 4)) 59)
      (error "无效分时时间: %s" time))
    (let ((m (+ (* 60 (string-to-number (substring digits 0 2)))
                (string-to-number (substring digits 2 4)))))
      (cond ((<= 570 m 690) (- m 570))
            ((<= 780 m 900) (+ 120 (- m 780)))
            (t (error "非连续竞价时段: %s" time))))))

(defun ths-data--volume (value)
  "Return nonnegative VALUE in lots, preserving missing volume as nil."
  (when-let* ((number (ths-data-number value)))
    (when (>= number 0) number)))

(defun ths-data--point (time price &optional volume)
  "Return a valid intraday point from TIME, PRICE and VOLUME in lots."
  (when-let* ((n (ths-data--positive price)))
    (condition-case nil
        (list :time time :slot (ths-data-minute-slot time) :price n
              :volume (ths-data--volume volume))
      (error nil))))

(defun ths-data--candle (date open close high low &optional volume)
  "Return a valid OHLC candle with DATE and VOLUME in lots."
  (let ((o (ths-data--positive open)) (c (ths-data--positive close))
        (h (ths-data--positive high)) (l (ths-data--positive low)))
    (when (and o c h l (>= h (max o c)) (<= l (min o c)))
      (list :date date :open o :close c :high h :low l
            :volume (ths-data--volume volume)))))

(defun ths-data--minute-volumes (points)
  "Convert Tencent POINTS' cumulative lots to per-minute lots in place.
Include opening auction volume in the 09:30 bar.  Missing values, gaps and
counter decreases have unknown minute volume, rather than a made-up zero."
  (let ((previous 0) (previous-slot -1))
    (dolist (point points)
      (let ((total (plist-get point :volume)) (slot (plist-get point :slot)))
        (setf (plist-get point :volume)
              (when (and total previous (<= 0 (- slot previous-slot) 1)
                         (>= total previous))
                (- total previous)))
        (setq previous total previous-slot slot))))
  points)

(defun ths-data--chart (text symbol provider kind)
  "Parse chart TEXT for SYMBOL from PROVIDER of KIND."
  (let* ((root (ths-data--json text))
         (data (if (eq provider 'tencent) (ths-data--get root "data" symbol)
                 (ths-data--get root "data")))
         points candles date)
    (if (eq kind 'intraday)
        (if (eq provider 'tencent)
            (progn
              (setq date (ths-data--get data "data" "date"))
              (dolist (row (ths-data--get data "data" "data"))
                (let ((f (split-string row " " t)))
                  (when-let* ((point (ths-data--point (nth 0 f) (nth 1 f) (nth 2 f)))) (push point points)))))
          (dolist (row (ths-data--get data "trends"))
            (let* ((f (split-string row ",")) (stamp (split-string (car f) " ")))
              (setq date (car stamp))
              (when-let* ((point (ths-data--point (cadr stamp) (nth 2 f) (nth 5 f)))) (push point points)))))
      (dolist (row (ths-data--get data (if (eq provider 'tencent) "day" "klines")))
        (let* ((f (if (stringp row) (split-string row ",") row))
               (candle (apply #'ths-data--candle (seq-take f 6))))
          (when candle (push candle candles)))))
    (if (eq kind 'intraday)
        (progn
          (unless (and points (stringp date)) (error "暂无分时数据"))
          (when (string-match-p "\\`[0-9]\\{8\\}\\'" date)
            (setq date (format "%s-%s-%s" (substring date 0 4) (substring date 4 6) (substring date 6 8))))
          (setq points (nreverse points))
          (when (eq provider 'tencent) (ths-data--minute-volumes points))
          (list :points points :intraday-date date
                :intraday-close (ths-data--positive
                                 (if (eq provider 'tencent)
                                     (nth 4 (ths-data--get data "qt" symbol))
                                   (ths-data--get data "preClose")))))
      (unless candles (error "暂无日 K 数据"))
      (list :candles (nreverse candles)))))

(defun ths-data--url (provider kind symbol)
  "Build a public HTTPS endpoint for PROVIDER, KIND and SYMBOL."
  (let ((secid (concat (if (string-prefix-p "sh" symbol) "1." "0.") (substring symbol 2))))
    (pcase (list provider kind)
      (`(tencent quote) (concat "https://qt.gtimg.cn/q=" symbol))
      (`(sina quote) (concat "https://hq.sinajs.cn/list=" symbol))
      (`(tencent intraday) (concat "https://web.ifzq.gtimg.cn/appstock/app/minute/query?code=" symbol))
      (`(tencent daily) (concat "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=" symbol ",day,,,120,"))
      (`(eastmoney quote)
       (concat "https://push2.eastmoney.com/api/qt/stock/get?secid=" secid
               "&fltt=2&invt=2&fields=f43,f44,f45,f46,f48,f57,f58,f60,f86,f168,f530,"
               (mapconcat (lambda (n) (format "f%d" n)) (append (number-sequence 11 20) (number-sequence 31 40)) ",")))
      (`(eastmoney intraday)
       (concat "https://push2his.eastmoney.com/api/qt/stock/trends2/get?secid=" secid
               "&fields1=f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11&fields2=f51,f52,f53,f54,f55,f56,f57,f58&ndays=1&iscr=0"))
      (`(eastmoney daily)
       (concat "https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=" secid
               "&klt=101&fqt=0&lmt=120&end=20500101&fields1=f1,f2,f3,f4,f5,f6&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61"))
      (`(eastmoney trades)
       (concat "https://push2.eastmoney.com/api/qt/stock/details/get?secid=" secid
               "&fields1=f1,f2,f3,f4,f5&fields2=f51,f52,f53,f54,f55&fltt=2"
               "&ut=bd1d9ddb04089700cf9c27f6f7426281"
               (format "&pos=-%d" ths-data-trades-count)))
      (_ (error "不支持的数据源: %s / %s" provider kind)))))

(defun ths-data--trades (text symbol)
  "Parse Eastmoney trade TEXT for SYMBOL as a recent snapshot.
Prices are yuan (fltt=2); volumes are lots.  These are provider-classified
time-and-sales records, not a guaranteed exchange Level-2 tick stream."
  (let* ((data (ths-data--get (ths-data--json text) "data"))
         (code (ths-data--get data "code"))
         (details (ths-data--get data "details")) rows)
    (unless (and data (assq 'details data) (listp details)
                 (or (null code) (equal code (substring symbol 2))))
      (error "成交明细响应为空或代码不匹配"))
    (dolist (line details)
      (let* ((fields (split-string line ",")) (time (car fields))
             (price (ths-data--positive (nth 1 fields)))
             (volume (ths-data-number (nth 2 fields))))
        (unless (and (>= (length fields) 5)
                     (string-match-p "\\`\\(?:[01][0-9]\\|2[0-3]\\):[0-5][0-9]:[0-5][0-9]\\'" time)
                     price volume (>= volume 0))
          (error "成交明细含无效时间、价格或数量"))
        (push (list :time time :price price :volume volume
                    :side (pcase (nth 4 fields) ("2" 'buy) ("1" 'sell) ("4" 'neutral) (_ 'unknown))) rows)))
    ;; Reverse arrival order for equal timestamps; do not deduplicate separate
    ;; executions with identical time/price/size.  Each poll replaces the list.
    (list :trades (seq-take (cl-stable-sort rows
                                          (lambda (a b) (string> (plist-get a :time) (plist-get b :time))))
                           ths-data-trades-count))))

(defun ths-data--decode (raw provider)
  "Decode RAW response bytes from PROVIDER, including Sina JSON arrays."
  (if (and (eq provider 'sina) (string-match-p "\\`[ \r\n\t]*\\[" raw))
      (let ((decoded (decode-coding-string raw 'utf-8)))
        (if (seq-some (lambda (char) (eq (char-charset char) 'eight-bit)) decoded)
            (decode-coding-string raw 'gb18030)
          decoded))
    (decode-coding-string raw (if (and (memq provider '(tencent sina))
                                      (not (string-match-p "\\`[ \r\n]*{" raw)))
                                 'gb18030 'utf-8))))

(defun ths-data--http (url provider callback)
  "Fetch URL asynchronously for PROVIDER; CALLBACK receives TEXT and ERROR.
Return a cancellation function.  Curl handles HTTP errors and total timeout."
  (let ((buffer (generate-new-buffer " *ths-http*")) process cancelled)
    (condition-case err
        (setq process
              (make-process
               :name "ths-http" :buffer buffer :connection-type 'pipe :coding 'binary :noquery t
               :command (list ths-data-curl-program "--disable" "--silent" "--show-error" "--fail"
                              "--connect-timeout" (number-to-string (max 1 ths-data-timeout))
                              "--max-time" (number-to-string (max 1 ths-data-timeout))
                              "--user-agent" "Mozilla/5.0 THS/0.2"
                              "--referer" (pcase provider ('sina "https://finance.sina.com.cn/")
                                                 ('eastmoney "https://quote.eastmoney.com/")
                                                 (_ "https://gu.qq.com/"))
                              "--url" url)
               :sentinel
               (lambda (proc _event)
                 (when (memq (process-status proc) '(exit signal))
                   (let ((raw (when (buffer-live-p buffer)
                                (with-current-buffer buffer (buffer-string)))))
                     (when (buffer-live-p buffer) (kill-buffer buffer))
                     (unless cancelled
                       (if (zerop (process-exit-status proc))
                           (funcall callback (ths-data--decode raw provider) nil)
                         (funcall callback nil (format "HTTP 请求失败 (%s): %s"
                                                       (process-exit-status proc)
                                                       (string-trim (or raw "")))))))))))
      (error (when (buffer-live-p buffer) (kill-buffer buffer))
             (funcall callback nil (error-message-string err))))
    (lambda ()
      (setq cancelled t)
      (when (and process (process-live-p process)) (delete-process process))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(defun ths-data--parse (text symbol provider kind)
  "Parse and validate TEXT for SYMBOL from PROVIDER of KIND."
  (cond
   ((eq kind 'trades) (ths-data--trades text symbol))
   ((eq kind 'quote)
      (let ((quote (funcall (pcase provider
                              ('tencent #'ths-data--quote-tencent)
                              ('sina #'ths-data--quote-sina)
                              ('eastmoney #'ths-data--quote-eastmoney)) text symbol)))
        (unless (and (plist-get quote :close)
                     (not (string-empty-p (or (plist-get quote :name) ""))))
          (error "报价缺少有效昨收或名称"))
        quote))
   (t (ths-data--chart text symbol provider kind))))

(defun ths-data-fetch (symbol kind callback)
  "Fetch SYMBOL's KIND with fallback; CALLBACK receives a plist and error.
KIND is quote, intraday, daily or trades.  Return a cancellation function.
A failed provider never replaces cached data with invented values."
  (setq symbol (ths-data-symbol symbol))
  (let ((providers (if (eq kind 'trades) '(eastmoney)
                    (seq-filter (lambda (p) (or (eq kind 'quote) (not (eq p 'sina))))
                                ths-data-providers)))
        (generation 0) cancel cancelled errors)
    (cl-labels
     ((next ()
        (unless cancelled
          (if (null providers)
              (funcall callback nil (if errors (mapconcat #'identity (nreverse errors) "; ")
                                      "未配置可用数据源"))
            (let* ((provider (pop providers))
                   (request-id (cl-incf generation))
                   (handle
                    (ths-data--http
                     (ths-data--url provider kind symbol) provider
                     (lambda (text failure)
                       (unless cancelled
                         (let (result)
                           (unless failure
                             (condition-case err
                                 (setq result (ths-data--parse text symbol provider kind))
                               (error (setq failure (error-message-string err)))))
                           (if failure
                               (progn (push (format "%s: %s" provider failure) errors) (next))
                             (funcall callback
                                      (append result (list :source provider :fetched-at (float-time))) nil))))))))
              ;; A synchronous failure may already have started a fallback.
              (when (= request-id generation) (setq cancel handle)))))))
     (next))
    (lambda () (setq cancelled t) (when cancel (funcall cancel)))))

(defconst ths-data-ranking-page-size 20
  "Number of securities per market ranking page.")

(define-error 'ths-data-ranking-universe-error "排行榜返回了非 A 股证券")

(defun ths-data--ranking-stock-symbol (code market)
  "Return the A-share symbol for CODE and Eastmoney MARKET, or nil.
Check the market together with the trading code: 1.000001 is an index,
whereas 0.000001 is a stock.  Fund, bond and index ranges are excluded."
  (when (and (stringp code) (string-match-p "\\`[0-9]\\{6\\}\\'" code))
    (cond
     ((and (eq market 1) (string-match-p "\\`\\(?:60\\|68\\)" code)) (concat "sh" code))
     ((and (eq market 0) (string-match-p "\\`\\(?:00[0-4]\\|30\\)" code)) (concat "sz" code))
     ((and (eq market 0) (string-match-p "\\`\\(?:43\\|83\\|87\\|920\\)" code)) (concat "bj" code)))))

(defun ths-data--ranking-url (sort page &optional fallback)
  "Return Eastmoney's A-share ranking URL for SORT and PAGE.
Use the alternate node when FALLBACK is non-nil."
  (unless (and (memq sort '(change amount)) (integerp page) (> page 0))
    (error "无效排行参数: %s / %s" sort page))
  (concat (if fallback "https://push2.eastmoney.com/api/qt/clist/get"
            "https://82.push2.eastmoney.com/api/qt/clist/get")
          (format "?pn=%d&pz=%d&po=1&np=1&fltt=2&invt=2&fid=%s"
                  page ths-data-ranking-page-size (if (eq sort 'amount) "f6" "f3"))
          "&ut=bd1d9ddb04089700cf9c27f6f7426281"
          ;; Use form-encoded spaces (+) consistently in the market expression.
          "&fs=m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23,m:0+t:81+s:2048"
          "&fields=f2,f3,f5,f6,f8,f12,f13,f14,f15,f16,f17,f18,f21,f24,f124"))

(defun ths-data--ranking-parse (text sort page)
  "Parse whole-market ranking TEXT for SORT and PAGE, preserving server order.
Volumes (f5) are lots; amounts (f6) and float market cap (f21) are yuan.
The 60-day change (f24) is already a percentage.  Missing values remain nil."
  (let* ((data (ths-data--get (ths-data--json text) "data"))
         (total (ths-data--get data "total"))
         (diff (ths-data--get data "diff"))
         (offset (* (1- page) ths-data-ranking-page-size)))
    (unless (and data (integerp total) (> total 0))
      (error "排行榜响应缺少有效总数"))
    ;; Some endpoints return a numeric-keyed object instead of an array.
    (when (and diff (symbolp (caar diff)))
      (setq diff (mapcar #'cdr (sort (copy-sequence diff)
                                    (lambda (a b)
                                      (< (string-to-number (symbol-name (car a)))
                                         (string-to-number (symbol-name (car b)))))))))
    (unless (and (<= (length diff) ths-data-ranking-page-size)
                 (<= (+ offset (length diff)) (max total offset))
                 (or diff (>= offset total)))
      (error "排行榜响应条目不完整"))
    (list
     :sort sort :page page :total total :source 'eastmoney :fetched-at (float-time)
     :rows
     (cl-loop for row in diff for rank from (1+ offset)
              for code = (ths-data--get row "f12")
              for name = (ths-data--get row "f14")
              for market = (ths-data--get row "f13")
              for symbol = (ths-data--ranking-stock-symbol code market)
              collect
              (progn
                (unless (and (stringp code) (string-match-p "\\`[0-9]\\{6\\}\\'" code)
                             (stringp name) (not (string-empty-p name)) (memq market '(0 1)))
                  (error "排行榜响应含无效股票"))
                ;; Reject the complete page instead of dropping rows: removing
                ;; funds locally would corrupt ranks, total and pagination.
                (unless symbol
                  (signal 'ths-data-ranking-universe-error (list (format "%s.%s %s" market code name))))
                (list :rank rank :code code :name name
                      :symbol symbol
                      :price (ths-data--positive (ths-data--get row "f2"))
                      :change (ths-data-number (ths-data--get row "f3"))
                      :volume (ths-data-number (ths-data--get row "f5"))
                      :amount (ths-data-number (ths-data--get row "f6"))
                      :turnover (ths-data-number (ths-data--get row "f8"))
                      :float-cap (ths-data--positive (ths-data--get row "f21"))
                      :change-60d (ths-data-number (ths-data--get row "f24"))
                      :close (ths-data--positive (ths-data--get row "f18"))
                      :high (ths-data--positive (ths-data--get row "f15"))
                      :low (ths-data--positive (ths-data--get row "f16"))
                      :open (ths-data--positive (ths-data--get row "f17"))
                      :time (when-let* ((stamp (ths-data--positive (ths-data--get row "f124"))))
                              (format-time-string "%F %T" (seconds-to-time stamp) 28800))))))))

(defun ths-data--ranking-sina-url (sort page &optional count)
  "Return Sina's A-share ranking URL for SORT and PAGE, or COUNT endpoint."
  (unless (and (memq sort '(change amount)) (integerp page) (> page 0))
    (error "无效排行参数: %s / %s" sort page))
  (concat "https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center."
          (if count "getHQNodeStockCount?node=hs_a"
            (format "getHQNodeData?page=%d&num=%d&sort=%s&asc=0&node=hs_a&symbol=&_s_r_a=page"
                    page ths-data-ranking-page-size (if (eq sort 'amount) "amount" "changepercent")))))

(defun ths-data--ranking-sina-count (text)
  "Parse Sina's stock count TEXT, rejecting empty or invalid totals."
  (let ((count (ths-data-number (ths-data--json text))))
    (unless (and (integerp count) (> count 0)) (error "新浪排行榜响应缺少有效总数"))
    count))

(defun ths-data--ranking-sina-parse (text sort page total)
  "Normalize Sina ranking TEXT for SORT, PAGE and TOTAL to the shared schema.
Volumes are shares, amount is yuan, and nmc is float market cap in 10,000 yuan.
Sina does not provide the 60-day percentage change in this endpoint."
  (unless (string-match-p "\\`[ \t\r\n]*\\[" text)
    (error "新浪排行榜响应不是股票列表"))
  ;; Older responses omit quotes around keys.  Match complete JSON strings
  ;; first so names containing punctuation are never rewritten.  Never eval.
  (let* ((normalized
          (replace-regexp-in-string
           "\"\\(?:[^\"\\\\]\\|\\\\.\\)*\"\\|\\_<\\([A-Za-z_][A-Za-z0-9_]*\\)[ \t]*:"
           (lambda (part) (if (match-string 1 part) (concat "\"" (match-string 1 part) "\":") part))
           text t t))
         (rows (ths-data--json normalized))
         (offset (* (1- page) ths-data-ranking-page-size)) seen result)
    (unless (and (integerp total) (> total 0)
                 (= (length rows) (min ths-data-ranking-page-size (max 0 (- total offset)))))
      (error "新浪排行榜响应条目不完整"))
    (cl-loop for row in rows for rank from (1+ offset) do
             (let* ((symbol (ths-data--get row "symbol")) (code (ths-data--get row "code"))
                    (name (ths-data--get row "name"))
                    (market (if (and (stringp symbol) (string-prefix-p "sh" symbol)) 1 0))
                    (expected (ths-data--ranking-stock-symbol code market)))
               (unless (and expected (equal symbol expected))
                 (signal 'ths-data-ranking-universe-error (list (format "%s" symbol))))
               (unless (and (stringp name) (not (string-empty-p name)) (not (member symbol seen)))
                 (error "新浪排行榜含无效或重复股票"))
               (push symbol seen)
               (push (list :rank rank :code code :symbol symbol :name name
                           :price (ths-data--positive (ths-data--get row "trade"))
                           :change (ths-data-number (ths-data--get row "changepercent"))
                           :volume (ths-data--scale (ths-data--get row "volume") 100)
                           :amount (ths-data-number (ths-data--get row "amount"))
                           :turnover (ths-data-number (ths-data--get row "turnoverratio"))
                           :float-cap (when-let* ((cap (ths-data--positive (ths-data--get row "nmc"))))
                                        (* cap 10000.0))
                           :change-60d nil
                           :close (ths-data--positive (ths-data--get row "settlement"))
                           :high (ths-data--positive (ths-data--get row "high"))
                           :low (ths-data--positive (ths-data--get row "low"))
                           :open (ths-data--positive (ths-data--get row "open"))
                           :time (ths-data--get row "ticktime")) result)))
    (list :sort sort :page page :total total :source 'sina :fetched-at (float-time)
          :rows (nreverse result))))

(defun ths-data-fetch-ranking (sort page callback)
  "Fetch ranking SORT and PAGE asynchronously; return a cancellation function.
CALLBACK receives the parsed ranking and error.  Providers use market-wide
server sorting, independently of `ths-data-symbols'."
  (unless (and (memq sort '(change amount)) (integerp page) (> page 0))
    (error "无效排行参数: %s / %s" sort page))
  (let ((nodes (cl-loop for provider in ths-data-ranking-providers append
                       (pcase provider ('eastmoney '((eastmoney) (eastmoney . t)))
                              ('sina '((sina . count)))
                              (_ (error "无效排行榜数据源: %s" provider)))))
        total cancel cancelled done (generation 0) failures)
    (cl-labels
        ((next ()
           (if (null nodes)
               (progn (setq done t)
                      (funcall callback nil (if failures (mapconcat #'identity (nreverse failures) "；")
                                              "未配置排行榜数据源")))
             (let* ((node (pop nodes)) (provider (car node)) (stage (cdr node))
                    (request-id (cl-incf generation))
                    (handle
                     (ths-data--http
                      (if (eq provider 'sina) (ths-data--ranking-sina-url sort page (eq stage 'count))
                        (ths-data--ranking-url sort page stage)) provider
                      (lambda (text failure)
                        (when (and (not cancelled) (not done) (= request-id generation))
                          (let (result)
                            (unless failure
                              (condition-case err
                                  (setq result (if (eq provider 'eastmoney) (ths-data--ranking-parse text sort page)
                                                 (if (eq stage 'count) (ths-data--ranking-sina-count text)
                                                   (ths-data--ranking-sina-parse text sort page total))))
                                (error (setq failure (error-message-string err)))))
                            (cond
                             (failure (push (format "%s: %s" provider failure) failures) (next))
                             ((and (eq provider 'sina) (eq stage 'count))
                              (setq total result) (push '(sina . data) nodes) (next))
                             (t (setq done t) (funcall callback result nil)))))))))
               ;; A synchronous callback may already have started the retry.
               (when (= request-id generation) (setq cancel handle))))))
      (next))
    (lambda () (setq cancelled t) (when cancel (funcall cancel)))))

(defun ths-data--search-url (query)
  "Return the public Eastmoney code-table search URL for QUERY."
  (concat "https://search-codetable.eastmoney.com/codetable/search/web"
          "?client=web&clientType=webSuggest&clientVersion=lastest&pageIndex=1&pageSize=20&keyword="
          (url-hexify-string (string-trim query))))

(defun ths-data--search-parse (text)
  "Parse code-table TEXT for mainland stocks and exchange-traded funds."
  (let* ((json (ths-data--json text)) (rows (ths-data--get json "result")) result)
    (unless (and (assq 'result json) (listp rows))
      (error "股票搜索响应缺少结果列表"))
    (dolist (row rows)
      (let* ((market (ths-data--get row "securityTypeName"))
             (code (ths-data--get row "code"))
             (fund-market (ths-data-fund-market code))
             (prefix
              (or (cdr (assoc market '(("沪A" . "sh") ("深A" . "sz") ("京A" . "bj"))))
                  (and fund-market
                       (or (and (member market '("沪基" "沪基金" "沪市基金"))
                                (equal fund-market "sh"))
                           (and (member market '("深基" "深基金" "深市基金"))
                                (equal fund-market "sz"))
                           (member market '("基金" "场内基金" "ETF" "LOF" "ETF基金" "LOF基金")))
                       fund-market))))
        (when prefix
          (let ((name (ths-data--get row "shortName"))
                (pinyin (ths-data--get row "pinyin")))
            (unless (and (stringp code) (string-match-p "\\`[0-9]\\{6\\}\\'" code)
                         (stringp name) (not (string-empty-p name))
                         (not (string-match-p "[\n\r\t]" name)))
              (error "股票搜索结果包含无效代码或名称"))
            (unless (seq-find (lambda (stock) (equal (plist-get stock :symbol) (concat prefix code))) result)
              (let ((stock (ths-data-placeholder (concat prefix code))))
                (setq stock (plist-put stock :name name))
                (setq stock (plist-put stock :pinyin (if (stringp pinyin) pinyin "")))
                (push stock result)))))))
    (nreverse result)))

(defun ths-data-search (query callback)
  "Search stocks and listed funds by QUERY; CALLBACK receives rows and error.
Return a cancellation function.  The endpoint requires no account or API key."
  (ths-data--http
   (ths-data--search-url query) 'eastmoney
   (lambda (text failure)
     (let (rows)
       (unless failure
         (condition-case err (setq rows (ths-data--search-parse text))
           (error (setq failure (error-message-string err)))))
       (funcall callback rows failure)))))

(provide 'ths-data)
;;; ths-data.el ends here
