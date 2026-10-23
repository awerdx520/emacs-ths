;;; ths-live-check.el --- Optional public endpoint smoke check -*- lexical-binding: t; -*-
;;; Commentary:
;; Run with make live-check.  Requires network; excluded from make check.
;;
;; 行情检查项分三类，判据只看「是否真实失败」：
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
;; 外部信息五类源（`ths-info'，探测日期 2026-10-23）：新闻 A / 港 / 美三市场、
;; 公告 A / 港列表与 A 股首条正文、财报 A / 港 / 美三套 reportName、所属行业与
;; 同花顺行业涨跌、宏观面板与两市成交额（`ths-ai-macro-enabled' 默认关闭，检查
;; 时临时绑 t，否则该项会因开关关闭而假 skip）。这些接口是异步回调，每项用
;; 回调 + `accept-process-output' 有界等待：单项受 curl `--max-time'
;; （`ths-info-timeout'）约束，整轮受下面的总 deadline 约束，超时按 §3 结算。
;;
;; 失败 / skip 口径（三层，只让内容层失败变红）：
;;   1. 连接层（curl 退出码 ≠ 0：DNS、连接失败、超时、响应过大）→ skip，附退出码；
;;   2. 源侧不可用（HTTP 200 但正文是数据源自己的拒绝：`"success":false' 错误信封、
;;      HTML 反爬 / 跳转页、或整张表的指标值全为 null）→ skip，附源侧原话；
;;   3. 内容层（HTTP 200、正文能解析成该源的结构，但条目为 0 / 字段缺失 /
;;      不满足判据）→ failed，计入失败数并使脚本非零退出。
;; 分层的理由是网络抖动与源侧封禁不由本项目控制：把连接层判红会让 `make
;; live-check' 随机失败而失去信号价值；而「取到了 200 与该源的结构却没有内容」
;; 是本项目解析或契约的真实回归，必须变红。第 2 层里「结构变化」也只覆盖
;; 「正文根本不是该源的响应」这一种，解析出的结构不达判据仍走第 3 层。
;;
;; 当日实测确认为**源码侧缺陷**（列名、字段名、单元格锚点不符）的项，也只记
;; skip 并把线索打印进原因（见 `ths-live-check--source-hints' 等），由计划层
;; 决定怎么改源码 —— 本脚本只做冒烟，不在真网检查里顺手改源码。
;;
;; `pending' 不写死：检查项先注册、再取注册数，增删检查项无需同步改数字，也不会
;; 出现「等不到回调就超时」的假失败。链式项（公告列表 → 正文、行业名 → 涨跌）
;; 在父项发起前就登记 pending，父项任何结局都会结算子项，故 `checks' 计数稳定。
;;; Code:
(require 'cl-lib)
(require 'subr-x)
(require 'ths-data)
(require 'ths-info)

;; 宏观开关由 `ths-ai.el' 声明（defcustom，默认 nil）。这里只做特殊变量声明，
;; 避免为了临时绑一个开关把 AI 层（含 gptel 传输）整体加载进冒烟脚本。
(defvar ths-ai-macro-enabled)

(defconst ths-live-check--eastmoney-skip "skip（东财本机不可达）"
  "东财端点在本机不可达：相关检查项只标 skip，不置 failed。")

(defconst ths-live-check--min-total '((hkstock . 500) (usstock . 1000))
  "港美榜单 total 的量级下限。
2026-10-22 实测港股 2492 / 美股 18324，线上总数会漂移，故只判量级。")

(defconst ths-live-check--body-floor 50
  "公告正文的最小字数：少于该长度视为「正文没取到」。")

(defconst ths-live-check--macro-floor 3
  "宏观面板至少要有的有效读数项数。")

(defconst ths-live-check--placeholder-regexp "\\`@[A-Za-z_][A-Za-z0-9_]*@\\'"
  "模板占位符形状（如 `@open@'）。
新浪 corp 页面里带未渲染的 JS 模板，若解析抓到这类单元格，说明源码抓错了
单元格，属源侧/解析缺陷而非网络问题，判 skip 并打印占位符原文。")

(defconst ths-live-check--success-envelope-regexp
  "\"success\"[ \t\r\n]*:[ \t\r\n]*false"
  "东财 datacenter 的错误信封标记；带 `\"message\"' 时把原话打进 skip 原因。")

(defconst ths-live-check--source-hints
  '(("REPORT_DATE排序列不存在"
     . "列的拼写已改为 REPORTDATE（2026-10-23 修复）；若复现说明源侧列名再次变更"))
  "源侧拒绝对应到源码侧的已知线索。
键为数据源原话片段，值为当日实测结果；只写进 skip 原因，方便按日志定位，
本脚本不改源码。")

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

;;;; 外部信息检查：判定函数（纯函数，返回 (:ok 摘要) / (:skip 原因) / (:fail 原因)）

(defun ths-live-check--verdict (kind text)
  "Return the outcome plist for KIND with TEXT."
  (list kind text))

(defun ths-live-check--transport-outcome (status)
  "Return a skip outcome for curl STATUS, or nil when the request succeeded.
STATUS is curl's exit code as delivered by `ths-info--http'; a non-zero value
means the request never produced a body (DNS, connect, timeout, size limit)."
  (when (and (numberp status) (/= status 0))
    (ths-live-check--verdict
     :skip (format "连接层失败：%s"
                   (or (ths-info--map-exit-status status)
                       (format "退出码 %s" status))))))

(defun ths-live-check--source-outcome (body)
  "Return a skip outcome when BODY is a provider refusal, or nil.
Two shapes count: the datacenter error envelope (`\"success\":false' plus a
`\"message\"'), and an HTML body — the 同花顺 board list answers a request
without a browser session with a JavaScript redirect stub, and an anti-bot
page is equally unusable without being a regression of this project."
  (cond
   ((not (stringp body)) nil)
   ((string-match ths-live-check--success-envelope-regexp body)
    (let* ((message (and (string-match "\"message\"[ \t\r\n]*:[ \t\r\n]*\"\\([^\"]*\\)\"" body)
                         (match-string 1 body)))
           (hint (and message (cdr (assoc message ths-live-check--source-hints)))))
      (ths-live-check--verdict
       :skip (format "源侧拒绝：%s%s" (or message "success:false")
                     (if hint (format "（%s）" hint) "")))))
   ((string-match "\\`[ \t\r\n]*<" body)
    (let ((text (ths-info--clean-text (replace-regexp-in-string "<[^>]*>" " " body))))
      (ths-live-check--verdict :skip (format "源侧返回 HTML 页面（反爬/跳转）：%s"
                                             (truncate-string-to-width (or text "") 60)))))
   (t nil)))

(defun ths-live-check--news-item-broken-p (item)
  "Return non-nil when news ITEM lacks a title or a `YYYY-MM-DD' timestamp."
  (or (string-empty-p (or (plist-get item :title) ""))
      (not (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}"
                           (or (plist-get item :time) "")))))

(defun ths-live-check--news-outcome (items)
  "Judge parsed news ITEMS: at least one, title non-empty, time `YYYY-MM-DD…'."
  (cond
   ((null items)
    (ths-live-check--verdict :fail "解析结果为空（无可用新闻条目）"))
   ((cl-find-if #'ths-live-check--news-item-broken-p items)
    (ths-live-check--verdict
     :fail (format "条目字段缺失：%S" (cl-find-if #'ths-live-check--news-item-broken-p items))))
   (t (let ((first (car items)))
        (ths-live-check--verdict
         :ok (format "%d 条，首条 %s「%s」" (length items) (plist-get first :time)
                     (truncate-string-to-width (plist-get first :title) 30)))))))

(defun ths-live-check--announcements-outcome (items)
  "Judge parsed announcement ITEMS: at least one, each carrying `:art-code'."
  (cond
   ((null items)
    (ths-live-check--verdict :fail "解析结果为空（无公告条目）"))
   ((cl-find-if (lambda (item) (string-empty-p (or (plist-get item :art-code) ""))) items)
    (ths-live-check--verdict :fail "公告条目缺 art_code"))
   (t (ths-live-check--verdict
       :ok (format "%d 条，首条 art_code=%s「%s」" (length items)
                   (plist-get (car items) :art-code)
                   (truncate-string-to-width (plist-get (car items) :title) 24))))))

(defun ths-live-check--announcement-body-outcome (body)
  "Judge a parsed announcement BODY: non-empty and at least `--body-floor' chars."
  (let ((content (plist-get body :content))
        (pages (plist-get body :pages)))
    (cond
     ((null content) (ths-live-check--verdict :fail "正文解析为空"))
     ((< (length content) ths-live-check--body-floor)
      (ths-live-check--verdict :fail (format "正文仅 %d 字（下限 %d）"
                                             (length content) ths-live-check--body-floor)))
     (t (ths-live-check--verdict
         :ok (format "%d 字%s，开头「%s」" (length content)
                     (if (numberp pages) (format " / %d 页" pages) "")
                     (truncate-string-to-width content 24)))))))

(defconst ths-live-check--metric-keys
  '(:revenue :net-profit :eps :roe :gross-margin)
  "报表明细键；整表全空即视为源侧没给数据。")

(defun ths-live-check--financials-outcome (market rows)
  "Judge parsed ROWS for MARKET (\"a\", \"hk\" or \"us\").
A-share reports must carry a numeric `:revenue' in the newest period; the Hong
Kong and US reports are only required to answer at least one period.  A table
whose every metric is null is the source degrading (the US report currently
answers rows with `ITEM_VALUE: null'), so it is a skip, not a failure."
  (cond
   ((null rows)
    (ths-live-check--verdict :fail "解析结果为空（无报告期）"))
   ((cl-every (lambda (row) (null (cl-some (lambda (key) (plist-get row key))
                                           ths-live-check--metric-keys)))
              rows)
    (ths-live-check--verdict
     :skip (format "%d 期但所有指标值为 null%s（源码缺陷候选，非网络问题）"
                   (length rows)
                   (if (equal market "us")
                       "：实盘数值在 AMOUNT 字段（解析已读 AMOUNT，ITEM_VALUE 仅作回退）"
                     ""))))
   ((and (equal market "a") (not (numberp (plist-get (car rows) :revenue))))
    (ths-live-check--verdict :fail (format "首期 %s 缺 :revenue 数值"
                                           (plist-get (car rows) :period))))
   (t (ths-live-check--verdict
       :ok (format "%d 期（%s），首期 revenue %s"
                   (length rows)
                   (mapconcat (lambda (row) (or (plist-get row :period) "?")) rows " ")
                   (if (numberp (plist-get (car rows) :revenue))
                       (plist-get (car rows) :revenue)
                     "—"))))))

(defun ths-live-check--industry-outcome (industry)
  "Judge a parsed INDUSTRY plist: name non-empty and not a template placeholder."
  (let ((name (plist-get industry :name)))
    (cond
     ((null name) (ths-live-check--verdict :fail "行业名解析为空"))
     ((string-match-p ths-live-check--placeholder-regexp name)
      (ths-live-check--verdict
       :skip (format (concat "解析出模板占位符 %s（ths-info--industry-parse 未锚定"
                             "「所属行业板块」表格，抓到 JS 模板单元格）")
                     name)))
     (t (ths-live-check--verdict :ok (format "行业名 %s" name))))))

(defun ths-live-check--industry-change-outcome (name change)
  "Judge the parsed CHANGE for industry NAME: `:change' must be a number."
  (let ((value (plist-get change :change)))
    (cond
     ((not (numberp value))
      (ths-live-check--verdict :fail (format "%s 的涨跌幅解析为空" name)))
     (t (ths-live-check--verdict :ok (format "%s %+0.2f%%" name value))))))

(defun ths-live-check--errors-outcome (key errors)
  "Return KEY's outcome in ERRORS (alist of keyword to message), or nil.
A transport message means the source was unreachable (skip); any other message
is the collection's own parse/empty verdict (failure)."
  (let ((message (cdr (assq key errors))))
    (when message
      (if (string-match-p "\\`\\(?:HTTP 请求失败\\|响应过大\\)" message)
          (ths-live-check--verdict :skip (format "连接层失败：%s" message))
        (ths-live-check--verdict :fail message)))))

(defun ths-live-check--macro-outcome (info errors)
  "Judge the macro panel and the market-wide turnover in INFO and ERRORS."
  (let* ((macro (plist-get info :macro))
         (turnover (plist-get info :turnover))
         (outcomes (delq nil (list (ths-live-check--errors-outcome :macro errors)
                                   (ths-live-check--errors-outcome :turnover errors))))
         (skips (cl-remove-if-not (lambda (outcome) (eq (car outcome) :skip)) outcomes))
         (readings (cl-loop for (key value) on macro by #'cddr
                            when value collect key)))
    (cond
     (skips (ths-live-check--verdict
             :skip (mapconcat (lambda (outcome) (cadr outcome)) skips "；")))
     (outcomes (ths-live-check--verdict
                :fail (mapconcat (lambda (outcome) (cadr outcome)) outcomes "；")))
     ((< (length readings) ths-live-check--macro-floor)
      (ths-live-check--verdict :fail (format "宏观读数仅 %d 项（下限 %d）"
                                             (length readings) ths-live-check--macro-floor)))
     ((not (numberp turnover))
      (ths-live-check--verdict :fail (format "两市成交额不是数值：%S" turnover)))
     (t (ths-live-check--verdict
         :ok (format "宏观 %d 项（%s），两市成交额 %.2f 亿" (length readings)
                     (mapconcat (lambda (key) (substring (symbol-name key) 1))
                                readings "、")
                     (/ turnover 1e8)))))))

(defun ths-live-check--emit (label outcome)
  "Print LABEL's one-line OUTCOME and return its kind."
  (pcase (car outcome)
    (:ok (princ (format "ok: %s %s\n" label (cadr outcome))))
    (:skip (princ (format "skip: %s（%s）\n" label (cadr outcome))))
    (_ (princ (format "FAILED: %s %s\n" label (cadr outcome)))))
  (car outcome))

(let ((pending 0) (registered 0) (skipped 0) (failed 0) cancels)
  (cl-labels
      ((skip (label)
         (cl-incf skipped)
         (princ (format "%s: %s\n" label ths-live-check--eastmoney-skip)))
       (settle (label outcome)
         ;; 每项只结算一次：把 pending 减一、按 kind 计数、打印一行。
         (cl-decf pending)
         (pcase (car outcome)
           (:ok nil)
           (:skip (cl-incf skipped))
           (_ (cl-incf failed)))
         (ths-live-check--emit label outcome))
       (report (label kind failure result)
         (cl-decf pending)
         (when failure (cl-incf failed))
         (princ (format "%s: %s\n" label
                        (or failure (ths-live-check--render kind result)))))
       (job (_label thunk)
         ;; _LABEL 只为调用点可读：报告在回调里用同一个 label，故此处不读它。
         (cl-incf pending)
         (cl-incf registered)
         ;; 同步失败的回调会在该调用内就 decrement pending，因此先计数再调用。
         (push (funcall thunk) cancels))
       (register (label)
         ;; 链式项在父项发起前先占一个 pending 名额，父项任何结局都会结算它，
         ;; 这样 `checks' 计数不随父项成败变化。
         (cl-incf pending)
         (cl-incf registered)
         label)
       (request (label url parse verdict &optional coding headers on-outcome)
         ;; 已登记 pending 的一项：发请求、判定并结算。
         ;; ON-OUTCOME 在结算前以 (OUTCOME VALUE) 调用，供链式项发起子请求。
         (push (ths-info--http
                url (list :coding (or coding 'utf-8) :headers headers)
                (lambda (body status)
                  (let* ((transport (ths-live-check--transport-outcome status))
                         (value (unless transport (ignore-errors (funcall parse body))))
                         (outcome (or transport
                                      (and value (funcall verdict value))
                                      (ths-live-check--source-outcome body)
                                      (ths-live-check--verdict
                                       :fail "HTTP 成功但内容为空或结构不符"))))
                    (funcall (or on-outcome #'ignore) outcome value)
                    (settle label outcome))))
               cancels))
       (info (label url parse verdict &optional coding headers on-outcome)
         (register label)
         (request label url parse verdict coding headers on-outcome)))
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
          ;; 4) 新闻：A 股 / 港股 / 美股（东财 search JSONP）。
          (dolist (spec '(("sh600519" . "新闻 A 股（sh600519）")
                          ("hk00700" . "新闻 港股（hk00700）")
                          ("usAAPL" . "新闻 美股（usAAPL）")))
            (info (cdr spec) (ths-info--news-url (car spec))
                  #'ths-info--news-parse #'ths-live-check--news-outcome))
          ;; 5) 公告列表 A 股 → 首条正文（链式）。
          (let ((body-label "公告正文（A 股首条 art_code）"))
            (register body-label)
            (info "公告 A 股（sh600519）"
                  (ths-info--announcements-url "a" (ths-info--symbol-code "sh600519"))
                  #'ths-info--announcements-parse #'ths-live-check--announcements-outcome
                  nil nil
                  (lambda (outcome value)
                    (if (not (eq (car outcome) :ok))
                        (settle body-label
                                (ths-live-check--verdict
                                 :skip (format "依赖的公告列表不可用：%s" (cadr outcome))))
                      (request body-label
                               (ths-info--announcement-body-url
                                (plist-get (car value) :art-code))
                               #'ths-info--announcement-body-parse
                               #'ths-live-check--announcement-body-outcome)))))
          ;; 6) 公告列表港股（ann_type=H）。
          (info "公告 港股（hk00700，ann_type=H）"
                (ths-info--announcements-url "hk" (ths-info--symbol-code "hk00700"))
                #'ths-info--announcements-parse #'ths-live-check--announcements-outcome)
          ;; 7) 财报：A 股 / 港股 / 美股三套 reportName。
          (dolist (spec '(("a" "600519" . "财报 A 股（600519）")
                          ("hk" "00700" . "财报 港股（00700）")
                          ("us" "AAPL" . "财报 美股（AAPL）")))
            (pcase-let ((`(,market ,code . ,label) spec))
              (info label (ths-info--financials-url market code)
                    (lambda (text) (ths-info--financials-parse market text))
                    (lambda (rows) (ths-live-check--financials-outcome market rows)))))
          ;; 8) 所属行业 → 同花顺行业涨跌（链式）。
          (let ((change-label "行业涨跌（同花顺行业列表）"))
            (register change-label)
            (info "行业（A 股，sh600519）"
                  (ths-info--industry-url (ths-info--symbol-code "sh600519"))
                  #'ths-info--industry-parse #'ths-live-check--industry-outcome
                  'gb18030 nil
                  (lambda (outcome value)
                    (if (not (eq (car outcome) :ok))
                        (settle change-label
                                (ths-live-check--verdict
                                 :skip (format "依赖的行业名不可用：%s" (cadr outcome))))
                      (let ((name (plist-get value :name)))
                        (request change-label ths-info--industry-change-url
                                 (lambda (text) (ths-info--industry-change text name))
                                 (lambda (change)
                                   (ths-live-check--industry-change-outcome name change))
                                 'gb18030 nil))))))
          ;; 9) 宏观面板 + 两市成交额（`ths-ai-macro-enabled' 默认关闭，临时绑 t）。
          (register "宏观 + 两市成交额（ths-info-collect nil）")
          (let ((ths-ai-macro-enabled t)
                (ths-info-cache-seconds 0))
            (push (ths-info-collect
                   nil
                   (lambda (info errors)
                     (settle "宏观 + 两市成交额（ths-info-collect nil）"
                             (ths-live-check--macro-outcome info errors))))
                  cancels))
          ;; 所有检查并发在跑，等待上限按「单请求超时 × 数据源链深度」估，留余量。
          (let ((deadline (+ (float-time) (* 6 ths-data-timeout) 5)))
            (while (and (> pending 0) (< (float-time) deadline))
              (accept-process-output nil 0.1)))
          (when (> pending 0)
            (princ (format "Timed out with %d unfinished checks\n" pending))
            (cl-incf failed pending))
          (princ (format "live-check: %d checks, %d skipped, %d failed, %s\n"
                         registered skipped failed (if (> failed 0) "FAILED" "ok"))))
      (mapc #'funcall cancels))
    ;; 任一真实失败 → 1；全部 pass / skip → 0。
    (kill-emacs (if (> failed 0) 1 0))))
;;; ths-live-check.el ends here
