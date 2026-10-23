;;; ths-info.el --- External information sources for THS AI facts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Five families of public information behind the AI facts layer: news,
;; announcements (title list plus the newest body), finance reports, industry
;; and the optional macro panel.  Provider responses are parsed as data and
;; never evaluated as JavaScript or Lisp.
;;
;; The module is offline-testable by construction: `ths-info--http' is the only
;; function that starts a process, every parser is a pure function over an
;; already decoded string, and `ths-info-collect' accepts a stubbed transport.
;;
;; Field names come from the 2026-10-23 endpoint probes recorded in
;; `docs/adr/0002-ai-external-info-sources.md' and mirrored by the ERT fixtures.
;; A provider field that is absent stays nil: no zero, no guessed date.

;;; Code:
(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'url-util)

(defgroup ths nil "Market dashboard using ETAF." :group 'applications)

(defcustom ths-info-cache-seconds 120
  "Seconds a parsed information response stays reusable in memory.
Zero means every collection refetches, which is what the offline tests use
to isolate their request counts."
  :type 'natnum :group 'ths)

(defcustom ths-info-timeout 8
  "Maximum seconds for one information request and for a whole collection.
The per-request budget is the curl `--max-time' value; the collection budget
is the overall watchdog that delivers a partial result."
  :type 'number :group 'ths)

(defcustom ths-info-body-limit 2097152
  "Maximum response body size in bytes, 2 MiB by default.
The limit is enforced by curl (`--max-filesize'), whose exit status 63 means
the body was rejected before it ever reached this process.  A chunked response
carries no `Content-Length', so curl has nothing to compare the limit against
and accepts such a body however large it is: the limit is a cheap guard for the
common case, not a hard cap (see `openspec/tech-debt.md')."
  :type 'natnum :group 'ths)

(defconst ths-info--curl-program "curl"
  "Curl executable used for the asynchronous requests.")

(defconst ths-info--news-page-size 5
  "Number of news headlines requested per collection.")

(defconst ths-info--announcement-count 3
  "Number of announcement headlines requested per collection.")

(defconst ths-info--financial-periods 4
  "Number of report periods requested per collection.")

(defconst ths-info--us-secucode-suffix "O"
  "Exchange suffix appended to a US ticker when querying the finance report.
The Eastmoney report keys US issuers as `<TICKER>.<EXCHANGE>'; the probe
fixture carries `AAPL.O', so `.O' is the documented assumption.  When the
source rejects the suffix the factor degrades to nil and is reported in
ERRORS, so a wrong assumption never fabricates numbers.")

(defconst ths-info--sina-headers '(("Referer" . "https://finance.sina.com.cn"))
  "Headers required by `hq.sinajs.cn'; every other source sends none.")

(defconst ths-info--industry-change-url
  "http://q.10jqka.com.cn/thshy/index/field/199112/order/desc/page/1/ajax/1/"
  "Tonghuashun industry board list, one row per industry with its change.")

(defconst ths-info--macro-symbols
  "fx_susdcny,fx_shkdcny,DINIW,hf_CL,hf_GC,hf_CHA50CFD,hf_HSI,int_dji,int_nasdaq,int_sp500"
  "Macro keys fetched in one Sina batch so that the panel costs one request.
This is the fallback for `ths-ai-macro-symbols', which is the user option and
wins whenever `ths-ai.el' is loaded; the two defaults are kept identical.")

;; `ths-ai-macro-symbols' lives in `ths-ai.el', which is loaded on top of this
;; module and might not be loaded at all (`ths-info' is usable standalone).
;; Declaring it here keeps the byte compiler from reporting a free variable and
;; lets `ths-info--macro-url' read it through `boundp'.
(defvar ths-ai-macro-symbols)

(defun ths-info--macro-url-symbols ()
  "Return the macro panel symbols, preferring the user option.
`ths-ai-macro-symbols' is the documented switch; the constant is only the
fallback for a session that never loaded `ths-ai.el'.  Reading the option here
is what makes it a live setting instead of a dead defcustom."
  (if (boundp 'ths-ai-macro-symbols)
      ths-ai-macro-symbols
    ths-info--macro-symbols))

(defconst ths-info--macro-readings
  '(("fx_susdcny" :fx-usdcny 1)
    ("fx_shkdcny" :fx-hkdcny 1)
    ("DINIW" :dollar-index 1)
    ("hf_CL" :oil 0)
    ("hf_GC" :gold 0)
    ("hf_CHA50CFD" :a50 0)
    ("hf_HSI" :hsi-future 0))
  "Macro keys as (HQ-KEY PROPERTY FIELD-INDEX) for Sina quote layouts.")

(defconst ths-info--overnight-readings
  '(("int_dji" :dji) ("int_nasdaq" :nasdaq) ("int_sp500" :sp500))
  "Overseas index keys; their field 1 is the level.")

(defconst ths-info--a-financial-fields
  '(("TOTAL_OPERATE_INCOME" . :revenue)
    ("PARENT_NETPROFIT" . :net-profit)
    ("YSTZ" . :revenue-yoy)
    ("SJLTZ" . :profit-yoy)
    ("BASIC_EPS" . :eps)
    ("WEIGHTAVG_ROE" . :roe)
    ("XSMLL" . :gross-margin))
  "A-share report fields (RPT_LICO_FN_CPD) mapped onto the shared keys.")

(defconst ths-info--hk-financial-fields
  '(("OPERATE_INCOME" . :revenue)
    ("HOLDER_PROFIT" . :net-profit)
    ("OPERATE_INCOME_YOY" . :revenue-yoy)
    ("HOLDER_PROFIT_YOY" . :profit-yoy)
    ("BASIC_EPS" . :eps)
    ("ROE_AVG" . :roe)
    ("GROSS_PROFIT_RATIO" . :gross-margin))
  "Hong Kong report fields (RPT_HKF10_FN_MAININDICATOR) mapped onto the same keys.")

(defconst ths-info--us-financial-items
  '(("营业总收入" . :revenue)
    ("净利润" . :net-profit)
    ("基本每股收益" . :eps)
    ("净资产收益率" . :roe)
    ("毛利率" . :gross-margin))
  "US report ITEM_NAME values mapped onto the same keys.
The US report is a long table: one row per metric, grouped by `REPORT'.")

(defconst ths-info--yoy-keys
  '((:revenue . :revenue-yoy)
    (:net-profit . :profit-yoy))
  "Year-on-year key per metric; `:net-profit' maps to `:profit-yoy'.
Only the metrics the facts layer actually carries have an entry: the US long
table also reports `YOY_RATIO' for EPS, ROE and gross margin, but no consumer
reads `:eps-yoy' / `:roe-yoy' / `:gross-margin-yoy' (`ths-ai--financial-metrics'
has none of them), so mapping them would only compute values nobody uses.")

(defconst ths-info--hq-regexp
  "var[ \t]+hq_str_\\([A-Za-z0-9_]+\\)=\"\\([^\"]*\\)\""
  "Sina quote line shape: `var hq_str_KEY=\"FIELD,FIELD,...\";'.")

;;;; Small shared helpers

(defun ths-info--number (value)
  "Return VALUE as a number, or nil when it is not a plain decimal."
  (cond
   ((numberp value) value)
   ((and (stringp value)
         (string-match-p "\\`[-+]?[0-9]+\\(?:\\.[0-9]+\\)?\\'" (string-trim value)))
    (string-to-number (string-trim value)))))

(defun ths-info--clean-text (text)
  "Return TEXT with runs of whitespace collapsed and trimmed, or nil if empty."
  (when (stringp text)
    (let ((clean (string-trim (replace-regexp-in-string "[ \t\r\n]+" " " text))))
      (unless (string-empty-p clean) clean))))

(defun ths-info--strip-tags (text)
  "Return TEXT with HTML tags (including search `<em>' markup) removed."
  (when (stringp text)
    (let ((flat (replace-regexp-in-string "<[^<>]*>" "" text)))
      (setq flat (replace-regexp-in-string "&nbsp;" " " flat))
      (setq flat (replace-regexp-in-string "&amp;" "&" flat))
      (ths-info--clean-text flat))))

(defun ths-info--date-only (value)
  "Return the `YYYY-MM-DD' prefix of the report date VALUE, or nil."
  (when (stringp value)
    (let ((text (string-trim value)))
      (when (string-match "\\`\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" text)
        (match-string 1 text)))))

(defun ths-info--count-matches (regexp text)
  "Return how many times REGEXP matches TEXT."
  (let ((count 0) (pos 0))
    (while (and (stringp text) (string-match regexp text pos))
      (setq count (1+ count)
            pos (max (1+ pos) (match-end 0))))
    count))

(defun ths-info--json (text)
  "Parse JSON TEXT into plists, returning nil when TEXT is not valid JSON."
  (when (and (stringp text) (not (string-empty-p (string-trim text))))
    (condition-case nil
        (json-parse-string (string-trim text) :object-type 'plist :array-type 'list
                           :null-object nil :false-object nil)
      (error nil))))

(defun ths-info--jsonp-body (text)
  "Return the JSON payload of a JSONP response TEXT, or nil.
The payload is the whole trimmed text when it is plain JSON, otherwise the
object inside a callback wrapper such as `cb({\"code\":0})'; an empty or
tagged (non-JSON) body yields nil so that callers can record a failure."
  (when (stringp text)
    (let ((trimmed (string-trim text)))
      (cond
       ((string-empty-p trimmed) nil)
       ((string-prefix-p "{" trimmed) trimmed)
       (t (let* ((start (and (string-match "\\`[A-Za-z_$][A-Za-z0-9_$.]*[ \t\r\n]*(" trimmed)
                             (match-end 0)))
                 (end (and start (string-match ")[ \t\r\n]*;?\\'" trimmed)
                           (match-beginning 0))))
            (when (and start end (> end start))
              (string-trim (substring trimmed start end)))))))))

(defun ths-info--jsonp (text)
  "Parse the JSON payload of JSONP TEXT, or return nil."
  (ths-info--json (ths-info--jsonp-body text)))

(defun ths-info--hq-entries (text)
  "Return TEXT's Sina quote lines as an alist of (KEY . FIELDS).
The match data is read into locals before `split-string' runs: that call
uses `string-match' internally and would otherwise leave this loop's match
data overwritten, so the scan position never advances."
  (let ((entries nil) (pos 0))
    (when (stringp text)
      (while (string-match ths-info--hq-regexp text pos)
        (let ((key (match-string 1 text))
              (raw (match-string 2 text))
              (end (match-end 0)))
          (push (cons key (split-string raw ",")) entries)
          (setq pos (max (1+ pos) end)))))
    (nreverse entries)))

(defun ths-info--map-exit-status (status)
  "Return an error message for curl exit STATUS, or nil when it succeeded.
Status 63 is curl's refusal to download a body larger than `--max-filesize';
any other non-zero status is reported as a plain request failure."
  (cond
   ((or (null status) (and (numberp status) (zerop status))) nil)
   ((and (numberp status) (= 63 status)) "响应过大")
   (t (format "HTTP 请求失败 (%s)" status))))

;;;; Symbol helpers

(defun ths-info--symbol-text (symbol)
  "Return SYMBOL as a string, accepting a stock plist as well."
  (if (listp symbol) (plist-get symbol :symbol) symbol))

(defun ths-info--symbol-market (symbol)
  "Return \"a\", \"hk\" or \"us\" for SYMBOL, or nil when unrecognized.
SYMBOL is either a market-qualified string or a stock plist whose `:symbol'
names the market, matching `ths-data--market-symbol'."
  (let* ((value (ths-info--symbol-text symbol))
         (key (and (stringp value) (>= (length value) 2)
                   (downcase (substring value 0 2)))))
    (pcase key
      ((or "sh" "sz" "bj") "a")
      ("hk" "hk")
      ("us" "us"))))

(defun ths-info--symbol-code (symbol)
  "Return the bare provider code of SYMBOL, e.g. `sh600519' becomes `600519'."
  (let ((value (ths-info--symbol-text symbol)))
    (when (stringp value)
      (let ((trimmed (string-trim value)))
        (if (string-match "\\`\\(?:sh\\|sz\\|bj\\|of\\|hk\\|us\\)\\(.+\\)\\'" trimmed)
            (match-string 1 trimmed)
          trimmed)))))

(defun ths-info--news-url (symbol)
  "Return the Eastmoney search JSONP URL for SYMBOL's news headlines.
The keyword is the six-digit (or ticker) code; the nested `param' object is
the shape the endpoint documents, while `keyword' and `pageSize' are also
passed at the top level so the request stays readable in logs."
  (let* ((code (or (ths-info--symbol-code symbol) ""))
         (param (format (concat "{\"uid\":\"\",\"keyword\":\"%s\",\"type\":[\"cmsArticleWebOld\"],"
                                "\"client\":\"web\",\"clientType\":\"web\",\"clientVersion\":\"curr\","
                                "\"param\":{\"cmsArticleWebOld\":{\"searchScope\":\"default\","
                                "\"sort\":\"default\",\"pageIndex\":1,\"pageSize\":%d,"
                                "\"preTag\":\"<em>\",\"postTag\":\"</em>\"}}}")
                        code ths-info--news-page-size)))
    (format (concat "https://search-api-web.eastmoney.com/search/jsonp"
                    "?cb=cb&keyword=%s&type=cmsArticleWebOld&pageSize=%d&param=%s")
            (url-hexify-string code) ths-info--news-page-size (url-hexify-string param))))

(defun ths-info--announcements-url (market code)
  "Return the announcement list URL for MARKET and CODE.
A-share issuers use `ann_type=A', Hong Kong issuers `ann_type=H'."
  (format (concat "https://np-anotice-stock.eastmoney.com/api/security/ann"
                  "?sr=-1&page_size=%d&page_index=1&ann_type=%s&client_source=web&stock_list=%s")
          ths-info--announcement-count (if (equal market "hk") "H" "A") code))

(defun ths-info--announcement-body-url (art-code)
  "Return the announcement body URL for ART-CODE."
  (format (concat "https://np-cnotice-stock.eastmoney.com/api/content/ann"
                  "?art_code=%s&client_source=web&page_index=1")
          (url-hexify-string art-code)))

(defun ths-info--financials-url (market &optional code)
  "Return the finance report URL for MARKET and CODE.
CODE may be omitted: MARKET is then a market-qualified symbol such as
`sh600519' and both the market and the bare code are derived from it.
Each market has its own report name, filter field and sort column; the page
size is widened for the US long table, which repeats the period per metric.
The A-share sort column is `REPORTDATE': the provider rejects the
underscored spelling with `REPORT_DATE排序列不存在' (probed 2026-10-23)."
  (let* ((subject market)
         (market (if code market (or (ths-info--symbol-market subject) "a")))
         (code (or code (ths-info--symbol-code subject)))
         (report (pcase market
                   ("hk" "RPT_HKF10_FN_MAININDICATOR")
                   ("us" "RPT_USF10_FN_INCOME")
                   (_ "RPT_LICO_FN_CPD")))
         (filter (pcase market
                   ("hk" (format "(SECUCODE=\"%s.HK\")" code))
                   ("us" (format "(SECUCODE=\"%s.%s\")" code ths-info--us-secucode-suffix))
                   (_ (format "(SECURITY_CODE=\"%s\")" code))))
         (sort (pcase market
                 ("us" "REPORT")
                 ("hk" "REPORT_DATE")
                 (_ "REPORTDATE")))
         (size (if (equal market "us")
                   (* ths-info--financial-periods 10)
                 ths-info--financial-periods)))
    (format (concat "https://datacenter.eastmoney.com/api/data/v1/get"
                    "?reportName=%s&columns=ALL&filter=%s&pageNumber=1&pageSize=%d"
                    "&sortColumns=%s&sortTypes=-1&source=WEB&client=WEB")
            report (url-hexify-string filter) size sort)))

(defun ths-info--industry-url (code)
  "Return the Sina corp page URL carrying CODE's industry classification."
  (format (concat "https://vip.stock.finance.sina.com.cn/corp/go.php"
                  "/vCI_CorpOtherInfo/stockid/%s/menu_num/2.phtml")
          code))

(defun ths-info--macro-url ()
  "Return the single Sina batch URL for every macro reading.
The symbol list comes from `ths-ai-macro-symbols', via
`ths-info--macro-url-symbols', so a customized panel is what gets fetched."
  (concat "https://hq.sinajs.cn/list=" (ths-info--macro-url-symbols)))

(defun ths-info--turnover-url ()
  "Return the Sina batch URL for the Shanghai and Shenzhen turnover."
  "https://hq.sinajs.cn/list=sh000001,sz399001")

;;;; Parsers (pure functions over already decoded text)

(defun ths-info--news-parse (text)
  "Parse a news search response TEXT into `(:title :time :source)' entries.
Titles keep their provider timestamp format `YYYY-MM-DD HH:MM:SS' and lose
the search highlight markup; an empty or malformed payload yields nil."
  (let* ((payload (ths-info--jsonp text))
         (items (plist-get (plist-get payload :result) :cmsArticleWebOld)))
    (delq nil (mapcar (lambda (item)
                        (let ((title (ths-info--strip-tags (plist-get item :title)))
                              (time (ths-info--clean-text (plist-get item :date)))
                              (source (ths-info--clean-text (plist-get item :mediaName))))
                          (when (and title time)
                            (list :title title :time time :source (or source "")))))
                      (if (listp items) items nil)))))

(defun ths-info--announcements-parse (text)
  "Parse an announcement list response TEXT into `(:title :time :art-code)'.
A 200 response carrying an empty list (observed for US issuers) yields nil so
that the caller can report missing data instead of rendering an empty section."
  (let* ((payload (ths-info--json text))
         (items (plist-get (plist-get payload :data) :list)))
    (delq nil (mapcar (lambda (item)
                        (let ((art-code (ths-info--clean-text (plist-get item :art_code)))
                              (title (ths-info--strip-tags (plist-get item :title)))
                              (time (ths-info--clean-text (plist-get item :notice_date))))
                          (when (and art-code title)
                            (list :title title :time (or time "") :art-code art-code))))
                      (if (listp items) items nil)))))

(defun ths-info--announcement-body-parse (text)
  "Parse an announcement body response TEXT into `(:content :pages)'.
`:pages' is the provider `page_size', which is the page count (380 for a
paged Hong Kong filing) and not a character count."
  (let* ((payload (ths-info--json text))
         (data (plist-get payload :data))
         (content (ths-info--clean-text (plist-get data :notice_content)))
         (pages (ths-info--number (plist-get data :page_size))))
    (when content
      (list :content content :pages pages))))

(defun ths-info--report-date (row)
  "Return ROW's report period as `YYYY-MM-DD', or nil.
The A-share report names the column `REPORTDATE'; the Hong Kong report uses
`REPORT_DATE'.  Both spellings are accepted so that one row reader serves
every market, and a row without either field yields nil instead of a guess."
  (or (ths-info--date-only (plist-get row :REPORTDATE))
      (ths-info--date-only (plist-get row :REPORT_DATE))))

(defun ths-info--financial-row (row fields)
  "Return ROW as a report plist using the FIELD mapping, or nil.
A metric missing from ROW is left out of the plist instead of being zeroed."
  (when (listp row)
    (let ((result (list :period (ths-info--report-date row))))
      (dolist (field fields)
        (let ((value (ths-info--number
                      (plist-get row (intern (concat ":" (car field)))))))
          (when value
            (setq result (plist-put result (cdr field) value)))))
      (when (plist-get result :period) result))))

(defun ths-info--financials-long (rows)
  "Group the US long-table ROWS by `REPORT' and map `ITEM_NAME' to keys.
Rows keep the provider order, so the newest period stays first; the source
label (`2026/Q9', a cumulative period) is kept as `:period' verbatim rather
than being turned into a made-up calendar date.  The metric value lives in
`AMOUNT' (probed 2026-10-23); `ITEM_VALUE' is the older spelling of the same
column and is still accepted, so a source that answers one spelling with null
cannot zero the factor."
  (let ((periods nil))
    (dolist (row rows)
      (let* ((period (ths-info--clean-text (plist-get row :REPORT)))
             (item (ths-info--clean-text (plist-get row :ITEM_NAME)))
             (key (cdr (assoc item ths-info--us-financial-items))))
        (when (and period key)
          (let ((cell (assoc period periods)))
            (unless cell
              (setq cell (cons period (list :period period)))
              (push cell periods))
            (let ((value (or (ths-info--number (plist-get row :AMOUNT))
                             (ths-info--number (plist-get row :ITEM_VALUE)))))
              (when value (setcdr cell (plist-put (cdr cell) key value))))
            (let ((yoy (ths-info--number (plist-get row :YOY_RATIO))))
              (when yoy
                (let ((yoy-key (cdr (assq key ths-info--yoy-keys))))
                  (when yoy-key
                    (setcdr cell (plist-put (cdr cell) yoy-key yoy))))))))))
    (mapcar #'cdr (nreverse periods))))

(defun ths-info--financials-parse (market text)
  "Parse a finance report response TEXT for MARKET.
MARKET is \"a\", \"hk\" or \"us\"; every market answers with the same keys
\(`:period', `:revenue', `:net-profit', `:revenue-yoy', `:profit-yoy',
`:eps', `:roe', `:gross-margin'), newest period first."
  (let* ((market (if (symbolp market) (symbol-name market) market))
         (payload (ths-info--json text))
         (rows (plist-get (plist-get payload :result) :data)))
    (when (listp rows)
      (if (equal market "us")
          (ths-info--financials-long rows)
        (let ((fields (if (equal market "hk")
                          ths-info--hk-financial-fields
                        ths-info--a-financial-fields)))
          (delq nil (mapcar (lambda (row) (ths-info--financial-row row fields)) rows)))))))

(defconst ths-info--industry-label "所属行业板块"
  "Label of the Sina corp table cell that carries the industry name.
The page mentions 所属行业 in its navigation list as well, and it ships
unrendered JavaScript template cells such as `@open@', so the parser anchors
on this table label instead of the first 所属行业 occurrence.")

(defconst ths-info--industry-cell-regexp
  (concat "<td[ \t\r\n]+class=\"ct\"[^>]*>[ \t\r\n]*"
          "\\(?:<[^>]*>\\)*[ \t\r\n]*\\([^<@]+\\)</td>")
  "A `class=\"ct\"' table cell holding plain text.
The captured value may contain neither `<' nor `@', so an unrendered template
placeholder such as `@open@' can never be taken for an industry name.")

(defconst ths-info--industry-placeholder-regexp "\\`@[^@]*@\\'"
  "Shape of an unrendered template placeholder such as `@open@'.")

(defun ths-info--industry-parse (text)
  "Parse a Sina corp page TEXT into `(:name NAME)' for the industry cell.
The name is the first plain-text `class=\"ct\"' cell after the 所属行业板块
label, so navigation entries and JavaScript templates (`@open@') are skipped.
A fragment whose only cell is the industry name is accepted as well, because
the GBK round-trip fixture is exactly such a fragment; a page without a usable
cell yields nil rather than a placeholder."
  (when (stringp text)
    (let ((pos 0) (found nil))
      (while (and (not found) (string-match ths-info--industry-label text pos))
        (let ((start (match-end 0)))
          (setq pos (max (1+ pos) start))
          (when (string-match ths-info--industry-cell-regexp text start)
            (let ((name (ths-info--strip-tags (match-string 1 text))))
              (when (and name
                         (not (equal name ths-info--industry-label))
                         (not (string-match-p
                               ths-info--industry-placeholder-regexp name)))
                (setq found (list :name name)))))))
      (or found
          (when (= 1 (ths-info--count-matches "<td[ >]" text))
            (when (string-match "<td[^>]*>[[:space:]]*\\(?:<[^>]+>\\)*\\([^<@]+\\)"
                                text)
              (let ((name (ths-info--strip-tags (match-string 1 text))))
                (when name (list :name name)))))))))

(defun ths-info--industry-change (text name)
  "Return `(:name NAME :change PERCENT)' from the industry list TEXT, or nil.
NAME must match the anchor text exactly; an unknown industry yields nil
instead of a fabricated zero.  The 同花顺 board ajax currently answers an
anti-bot page without a single matching row (2026-10-23), so TEXT may be HTML
that parses to nothing: the result is then nil and no error is signalled."
  (when (and (stringp text) (stringp name) (not (string-empty-p name)))
    (let ((regexp (concat "<a[^>]*>[[:space:]]*\\([^<]+\\)[[:space:]]*</a>[[:space:]]*</td>"
                          "[[:space:]]*<td[^>]*>[[:space:]]*"
                          "\\([-+]?[0-9]+\\(?:\\.[0-9]+\\)?\\)"))
          (pos 0) (found nil))
      (while (and (not found) (string-match regexp text pos))
        ;; Capture the match data before `string-trim' (which uses
        ;; `string-match' internally) overwrites it.
        (let ((label (match-string 1 text))
              (value (match-string 2 text))
              (next (match-end 0)))
          (when (equal name (string-trim label))
            (setq found (list :name name :change (string-to-number value))))
          (setq pos (max (1+ pos) next))))
      found)))

(defun ths-info--macro-parse (text)
  "Return the macro readings of a Sina hq TEXT response.
Readings that the provider answered with an empty or unusable field stay nil
and `:overnight' is absent when no overseas index came back."
  (let ((entries (ths-info--hq-entries text))
        (result nil)
        (overnight nil))
    (dolist (spec ths-info--macro-readings)
      (let* ((fields (cdr (assoc (nth 0 spec) entries)))
             (value (and fields (ths-info--number (nth (nth 2 spec) fields)))))
        (when value (setq result (plist-put result (nth 1 spec) value)))))
    (dolist (spec ths-info--overnight-readings)
      (let* ((fields (cdr (assoc (nth 0 spec) entries)))
             (value (and fields (ths-info--number (nth 1 fields)))))
        (when value (setq overnight (plist-put overnight (nth 1 spec) value)))))
    (when overnight (setq result (plist-put result :overnight overnight)))
    result))

(defun ths-info--turnover-parse (text)
  "Return the combined Shanghai and Shenzhen turnover in yuan, or nil.
Field 9 of a Sina index quote is the amount in yuan; the two markets are
summed so the panel reports the market-wide figure."
  (let ((total nil))
    (dolist (entry (ths-info--hq-entries text))
      (when (member (car entry) '("sh000001" "sz399001"))
        (let ((amount (ths-info--number (nth 9 (cdr entry)))))
          (when amount (setq total (+ (or total 0) amount))))))
    total))

;;;; Transport

(defun ths-info--http (url params callback)
  "Fetch URL asynchronously and call CALLBACK with (BODY STATUS).
PARAMS is a plist of `:headers' (alist of header name to value), `:coding'
\(coding system used to decode the raw bytes) and `:parser' (optional
function applied to the decoded body).  STATUS is 0 on success and curl's
exit status otherwise, with BODY nil; callers translate it through
`ths-info--map-exit-status'.  `ths-info-collect' deliberately parses in its
own callback instead of through `:parser', so that a malformed body is
attributed to its source and recorded in ERRORS.  Return a cancel function:
after it runs the callback is never invoked again.

The callback is always delivered asynchronously, including the failure taken
when `make-process' itself signals: a synchronous call would let
`ths-info-collect' finish before it has assembled the remaining requests, and
every factor after the first would vanish from ERRORS.  The cancel function
also suppresses that deferred delivery, so cancellation keeps its meaning."
  (let* ((headers (plist-get params :headers))
         (coding (or (plist-get params :coding) 'utf-8))
         (parser (plist-get params :parser))
         (buffer (generate-new-buffer " *ths-info-http*"))
         (cancelled nil)
         process)
    (condition-case nil
        (setq process
              (make-process
               :name "ths-info-http" :buffer buffer :connection-type 'pipe
               :coding 'binary :noquery t
               :command
               (append
                (list ths-info--curl-program "--disable" "--silent" "--show-error"
                      "--max-time" (number-to-string (max 1 ths-info-timeout))
                      "--max-filesize" (number-to-string ths-info-body-limit))
                (cl-loop for (name . value) in headers
                         append (list "-H" (format "%s: %s" name value)))
                (list "--url" url))
               :sentinel
               (lambda (proc _event)
                 (when (memq (process-status proc) '(exit signal))
                   (let ((raw (when (buffer-live-p buffer)
                                (with-current-buffer buffer (buffer-string))))
                         (status (process-exit-status proc)))
                     (when (buffer-live-p buffer) (kill-buffer buffer))
                     (unless cancelled
                       (if (zerop status)
                           (let* ((text (decode-coding-string (or raw "") coding))
                                  (body (if parser
                                            (condition-case nil (funcall parser text)
                                              (error nil))
                                          text)))
                             (funcall callback body 0))
                         (funcall callback nil status))))))))
      (error (when (buffer-live-p buffer) (kill-buffer buffer))
             ;; 延迟交付：`make-process' 抛错时若同步回调，`ths-info-collect'
             ;; 会在装配其余请求之前就 finish，ERRORS 里只剩第一个因子，其余
             ;; 全被吞掉。取消语义不变——已 cancelled 则不再回调。
             (run-at-time 0 nil
                          (lambda ()
                            (unless cancelled
                              (funcall callback nil 1))))))
    (lambda ()
      (setq cancelled t)
      (when (process-live-p process) (delete-process process))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

;;;; Cache

(defvar ths-info--cache (make-hash-table :test #'equal)
  "Parsed responses keyed by (CATEGORY . IDENTITY), valued as (TIME . VALUE).")

(defun ths-info--cache-get (key)
  "Return the cached value under KEY when it is still fresh, else nil.
`ths-info-cache-seconds' zero makes every entry stale, i.e. immediately
expired, which keeps the offline request counts deterministic."
  (let ((entry (gethash key ths-info--cache)))
    (when (and entry (> ths-info-cache-seconds 0)
               (< (- (float-time) (car entry)) ths-info-cache-seconds))
      (cdr entry))))

(defun ths-info--cache-put (key value)
  "Store VALUE under KEY with the current timestamp and return VALUE.
Entries older than twice `ths-info-cache-seconds' are dropped first: the TTL
only decides whether an entry is reused, it never removes anything, so a long
session would keep every parsed response in memory for good.  Sweeping on write
costs one pass over the table and bounds it without a timer; twice the TTL
leaves the just-expired generation around (still useful for debugging a cache
miss) while keeping the table proportional to the live sources."
  (let ((now (float-time))
        (limit (* 2 (or ths-info-cache-seconds 0)))
        (stale nil))
    (maphash (lambda (entry-key entry)
               (when (> (- now (car entry)) limit)
                 (push entry-key stale)))
             ths-info--cache)
    (dolist (entry-key stale)
      (remhash entry-key ths-info--cache))
    (puthash key (cons now value) ths-info--cache)
    value))

;;;; Orchestration

(defun ths-info--enabled-p (variable)
  "Return non-nil when the info switch VARIABLE is enabled.
A switch that is not defined yet counts as enabled, so the data layer also
works before `ths-ai.el' declares its defcustoms."
  (if (boundp variable) (not (null (symbol-value variable))) t))

(defun ths-info-collect (stock callback)
  "Collect the five information families for STOCK and call CALLBACK once.
STOCK is a stock plist (or a market-qualified symbol string); CALLBACK
receives (INFO ERRORS) where INFO is a plist with `:news' (headline
plists), `:announcements' (headline plists), `:financials' (report plists),
`:industry' (`:name' plus `:change'), `:macro' (readings plist) and
`:turnover' (yuan).  When the newest announcement body came back it is
stored on the first element of `:announcements' as `:content' and `:pages',
so INFO never grows a second announcement key.

ERRORS is an alist of keyword to message using the same keywords as INFO, plus
`:announcement-body' for the body request: a body that fails does not mark the
whole `:announcements' factor as failed, because the headlines did arrive.
Requests run concurrently (at most eight: news, announcement list and body,
reports, industry name and change, macro panel and turnover); a failed or
empty source only drops its own factor.  `ths-info-timeout' bounds the whole
collection and delivers the factors that did arrive.  CALLBACK runs exactly
once.  Return a cancel function that aborts the requests, the timeout and
the callback.

STOCK may be nil: the macro panel and the market-wide turnover are whole-market
readings, so they are requested whenever `ths-ai-macro-enabled' is on, with or
without a security.  That is what lets the market analysis — which collects with
a nil stock — render its 外围与宏观 block.  The other four families are
symbol-specific and are simply not requested when STOCK has no code; skipping
them for lack of a subject is not a failure and records nothing in ERRORS."
  (let* ((symbol (ths-info--symbol-text stock))
         (code (ths-info--symbol-code symbol))
         (market (ths-info--symbol-market symbol))
         (info nil)
         (errors nil)
         (pending 0)
         (done nil)
         (timer nil)
         (cancels nil))
    (cl-labels
        ((finish ()
           (unless done
             (setq done t)
             (when (timerp timer) (cancel-timer timer) (setq timer nil))
             ;; 收尾时把仍在途的请求一并中止：只取消定时器的话，那些 curl 进程会
             ;; 一直跑到自己的 `--max-time'，其回调虽被 `done' 挡住，进程、buffer
             ;; 与句柄仍是泄漏。全部请求已完成的自然结束路径上调 cancel 无害
             ;; （进程已退出、buffer 已 kill），所以两种情况共用同一段收尾。
             (dolist (cancel cancels) (ignore-errors (funcall cancel)))
             (setq cancels nil)
             (funcall callback info (nreverse errors))))
         (fail (key message)
           (unless (assq key errors) (push (cons key message) errors)))
         (record (key value)
           (when value (setq info (plist-put info key value))))
         (settle ()
           (setq pending (1- pending))
           (when (<= pending 0) (finish)))
         (request (key url parse on-value &optional headers coding)
           (setq pending (1+ pending))
           (let ((cancel
                  (ths-info--http url (list :headers headers :coding coding)
                                  (lambda (body status)
                                    (unless done
                                      (let ((problem (and (numberp status)
                                                          (ths-info--map-exit-status status)))
                                            (value nil))
                                        (unless problem
                                          (setq value (ignore-errors (funcall parse body)))
                                          (unless value
                                            (setq problem "解析失败或数据为空")))
                                        (if problem
                                            (fail key problem)
                                          (funcall on-value value))
                                        ;; Chain first so that a follow-up request is
                                        ;; counted before this one settles.
                                        (settle)))))))
             (when (functionp cancel) (push cancel cancels))))
         (request-cached (key url parse on-value &optional headers coding cache-key)
           (let* ((cache-key (or cache-key (list key symbol)))
                  (cached (ths-info--cache-get cache-key)))
             (if cached
                 (funcall on-value cached)
               (request key url parse
                        (lambda (value)
                          (ths-info--cache-put cache-key value)
                          (funcall on-value value))
                        headers coding))))
         (fetch-body (art-code)
           (when (and art-code (not done))
             (request-cached
              ;; 正文有自己的错误键：正文抓取失败不该把整个 `:announcements'
              ;; 标成失败——标题列表其实已经拿到了。
              :announcement-body (ths-info--announcement-body-url art-code)
              #'ths-info--announcement-body-parse
              (lambda (body)
                (let ((items (plist-get info :announcements)))
                  (when (and (listp items) items)
                    ;; 先拷贝再改写：ITEMS 可能直接来自 `ths-info--cache'，
                    ;; `setcar' 原地改会把缓存里的条目一起污染。
                    (setcar items (append (copy-sequence (car items))
                                          (list :content (plist-get body :content)
                                                :pages (plist-get body :pages)))))))
              nil 'utf-8 (list :announcement-body art-code))))
         (fetch-industry-change (name)
           (when (and name (not done))
             (request-cached
              :industry ths-info--industry-change-url
              (lambda (text) (ths-info--industry-change text name))
              (lambda (change)
                (let ((industry (plist-get info :industry)))
                  (when industry
                    (record :industry (plist-put (copy-sequence industry)
                                                 :change (plist-get change :change))))))
              nil 'gb18030 (list :industry-change name)))))
      (setq timer (run-at-time (max 0.01 ths-info-timeout) nil #'finish))
      (when (and symbol code)
        (when (ths-info--enabled-p 'ths-ai-news-enabled)
          (request-cached :news (ths-info--news-url symbol) #'ths-info--news-parse
                          (lambda (items) (record :news items)) nil 'utf-8))
        (when (and (ths-info--enabled-p 'ths-ai-announcements-enabled)
                   (member market '("a" "hk")))
          (request-cached :announcements (ths-info--announcements-url market code)
                          #'ths-info--announcements-parse
                          (lambda (items)
                            (record :announcements items)
                            (fetch-body (plist-get (car items) :art-code)))
                          nil 'utf-8))
        (when (ths-info--enabled-p 'ths-ai-financials-enabled)
          (request-cached :financials (ths-info--financials-url market code)
                          (lambda (text) (ths-info--financials-parse market text))
                          (lambda (rows) (record :financials rows)) nil 'utf-8))
        (when (and (ths-info--enabled-p 'ths-ai-industry-enabled) (equal market "a"))
          (request-cached :industry (ths-info--industry-url code)
                          #'ths-info--industry-parse
                          (lambda (industry)
                            (record :industry industry)
                            (fetch-industry-change (plist-get industry :name)))
                          nil 'gb18030)))
      ;; 宏观面板与两市成交额不依赖 STOCK：它们是全市场读数，盘面分析（STOCK 为
      ;; nil）同样需要。放在 `symbol'/`code' 判空之外，否则盘面事实里的 `:macro'
      ;; 与 `:turnover' 恒空，盘面报告的宏观小节在生产路径上永远不渲染。这两项
      ;; 由 macro 开关控制；开关关闭时连请求都不发。
      (when (ths-info--enabled-p 'ths-ai-macro-enabled)
        (request-cached :macro (ths-info--macro-url) #'ths-info--macro-parse
                        (lambda (macro) (record :macro macro))
                        ths-info--sina-headers 'gb18030 (list :macro nil))
        (request-cached :turnover (ths-info--turnover-url) #'ths-info--turnover-parse
                        (lambda (turnover) (record :turnover turnover))
                        ths-info--sina-headers 'gb18030 (list :turnover nil)))
      ;; Every factor may have been served from the cache, in which case no
      ;; request is outstanding and the callback still has to run once.
      (when (<= pending 0) (finish))
      (lambda ()
        (unless done
          (setq done t)
          (when (timerp timer) (cancel-timer timer) (setq timer nil))
          (dolist (cancel cancels) (ignore-errors (funcall cancel)))
          (setq cancels nil))))))

(provide 'ths-info)
;;; ths-info.el ends here
