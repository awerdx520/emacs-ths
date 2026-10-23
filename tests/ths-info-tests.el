;;; ths-info-tests.el --- Tests for ths-info -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; TDD 红阶段用例（计划 B2，见 openspec/active/2026-10-23-ths-ai-info-factors.md）。
;; `ths-info.el' 尚未实现，本文件顶部的 `require' 会静默返回 nil，因此当前
;; 全部用例都失败于 `void-function ths-info-…'；B3 实现后应转绿。
;; 失败原因必须是「函数未定义」或「断言未满足」，不能是语法/加载错误。
;;
;; 本文件即接口契约（B3 按此实现，不自行改名）：
;;   配置：ths-info-cache-seconds(120) / ths-info-timeout(8) / ths-info-body-limit(2097152)
;;   纯函数：
;;     (ths-info--map-exit-status STATUS)              -> nil / "响应过大" / "HTTP 请求失败 (N)"
;;     (ths-info--strip-tags TEXT)                     -> 去标签文本
;;     (ths-info--symbol-market SYMBOL)                -> "a" / "hk" / "us"
;;     (ths-info--news-url SYMBOL)                     -> 东财搜索 JSONP URL
;;     (ths-info--news-parse TEXT)                     -> ((:title :time :source) …)
;;     (ths-info--announcements-parse TEXT)            -> ((:title :time :art-code) …)
;;     (ths-info--announcement-body-parse TEXT)        -> (:content :pages)
;;     (ths-info--financials-parse MARKET TEXT)        -> 报告期 plist 列表
;;     (ths-info--industry-parse TEXT)                 -> (:name)
;;     (ths-info--industry-change TEXT NAME)           -> (:name :change) / nil
;;     (ths-info--macro-parse TEXT)                    -> 宏观 plist
;;     (ths-info--turnover-parse TEXT)                 -> 两市成交额（元，number）
;;   编排层：
;;     (ths-info-collect STOCK CALLBACK)               -> cancel 句柄；CALLBACK 收 (INFO ERRORS)
;;   传输层（用例内被 `cl-letf' 覆盖，绝不触网）：
;;     (ths-info--http URL PARAMS CALLBACK)            -> cancel 句柄；CALLBACK 收 (BODY EXIT-STATUS)
;;       PARAMS = (:headers ALIST :coding SYMBOL :parser FUNCTION)
;;   STOCK 沿用项目惯例，接受个股 plist（与 `ths-data--market-symbol' 同样宽松）。
;;
;; 夹具来源：2026-10-23 对公开接口的真实探测（字段名、层级、单位取自实测响应；
;; 数值做了截断，结构保持等价）。所有用例完全离线。

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'ths-info nil t)

;; 测试隔离：不读写用户自选股，不自动联网。
(setq ths-watchlist-file nil
      ths-auto-fetch nil)

;; 下列变量由 ths-info.el / ths-ai.el 提供，红阶段尚不存在。先以无初值的
;; `defvar' 声明，使 `let' 在 lexical-binding 下产生动态绑定（否则会静默
;; 变成词法绑定，被测代码读不到测试设置的值）。
(defvar ths-info-timeout)
(defvar ths-info-cache-seconds)
(defvar ths-info-body-limit)
(defvar ths-ai-news-enabled)
(defvar ths-ai-announcements-enabled)
(defvar ths-ai-financials-enabled)
(defvar ths-ai-industry-enabled)
(defvar ths-ai-macro-enabled)

;;;; 固定夹具（2026-10-23 探测）

(defconst ths-info-test-search-jsonp
  "cb({\"code\":0,\"result\":{\"hitsTotal\":128,\"cmsArticleWebOld\":[\
{\"date\":\"2026-10-22 15:13:16\",\"mediaName\":\"证券时报\",\"title\":\"<em>600519</em> 贵州茅台三季度净利润同比增长 8.9%\",\"url\":\"https://finance.eastmoney.com/a/2026102234567890.html\"},\
{\"date\":\"2026-10-21 09:02:41\",\"mediaName\":\"上海证券报\",\"title\":\"白酒板块回调，<em>600519</em> 获北向资金增持\",\"url\":\"https://finance.eastmoney.com/a/2026102134567891.html\"},\
{\"date\":\"2026-10-20 18:30:05\",\"mediaName\":\"中国证券报\",\"title\":\"<em>600519</em> 公告：控股股东增持计划实施完毕\",\"url\":\"https://finance.eastmoney.com/a/2026102034567892.html\"}]}})"
  "东财搜索 JSONP 样本（2026-10-23 探测）。
外壳为 `cb({...})'；标题内的 `<em>' 是搜索高亮标签，解析后必须去掉。")

(defconst ths-info-test-ann-list-a
  "{\"success\":1,\"data\":{\"list\":[\
{\"art_code\":\"AN2026102200001\",\"title\":\"贵州茅台2026年第三季度报告\",\"notice_date\":\"2026-10-22 00:00:00\",\"codes\":[{\"stock_code\":\"600519\",\"short_name\":\"贵州茅台\"}]},\
{\"art_code\":\"AN2026101500002\",\"title\":\"贵州茅台2026年半年度权益分派实施公告\",\"notice_date\":\"2026-10-15 00:00:00\",\"codes\":[{\"stock_code\":\"600519\",\"short_name\":\"贵州茅台\"}]},\
{\"art_code\":\"AN2026093000003\",\"title\":\"贵州茅台关于回购股份进展的公告\",\"notice_date\":\"2026-09-30 00:00:00\",\"codes\":[{\"stock_code\":\"600519\",\"short_name\":\"贵州茅台\"}]}],\
\"total_hits\":1074}}"
  "A 股公告列表样本（2026-10-23 探测：`ann_type=A' 当日 1074 条）。")

(defconst ths-info-test-ann-list-us-empty
  "{\"success\":1,\"data\":{\"list\":[],\"total_hits\":0}}"
  "美股公告列表样本（2026-10-23 探测：该端点对美股返回 200 + 空数组）。")

(defconst ths-info-test-ann-body
  "{\"success\":1,\"data\":{\"art_code\":\"AN2026102200001\",\"page_size\":1,\"notice_content\":\"\
贵州茅台酒股份有限公司（以下简称“公司”）2026年第三季度报告全文：报告期内，公司实现营业总收入922.78亿元，\
同比增长9.16%；实现归属于上市公司股东的净利润461.00亿元，同比增长8.90%；基本每股收益36.72元。\
经营活动产生的现金流量净额为人民币512.34亿元，同比下降2.11%。报告期末公司总资产3,120.45亿元，\
归属于上市公司股东的所有者权益2,480.11亿元。公司表示，报告期内主营业务保持稳定，产品结构持续优化，\
直销渠道占比提升。特此公告。\"}}"
  "A 股公告正文样本（2026-10-23 探测：`page_size' 为 1，正文数百字）。")

(defconst ths-info-test-ann-body-hk-paged
  "{\"success\":1,\"data\":{\"art_code\":\"AN2026102200001H\",\"page_size\":380,\"notice_content\":\"\
貴州茅台酒股份有限公司截至二零二六年六月三十日止六個月之中期業績公告：本期間收入人民幣89,500百萬元，\
同比增長8.4%；本公司擁有人應佔溢利人民幣42,000百萬元，同比增長7.1%。\"}}"
  "港股公告正文样本（2026-10-23 探测：港股 `page_size' 是**总页数** 380，正文为繁体）。")

(defconst ths-info-test-fin-a
  "{\"success\":1,\"result\":{\"pages\":1,\"data\":[\
{\"SECURITY_CODE\":\"600519\",\"REPORTDATE\":\"2026-06-30 00:00:00\",\"TOTAL_OPERATE_INCOME\":92278072083.21,\"PARENT_NETPROFIT\":46100000000.0,\"YSTZ\":9.16,\"SJLTZ\":8.9,\"BASIC_EPS\":36.72,\"WEIGHTAVG_ROE\":24.5,\"XSMLL\":91.5},\
{\"SECURITY_CODE\":\"600519\",\"REPORTDATE\":\"2026-03-31 00:00:00\",\"TOTAL_OPERATE_INCOME\":51443000000.0,\"PARENT_NETPROFIT\":26847000000.0,\"YSTZ\":10.4,\"SJLTZ\":11.2,\"BASIC_EPS\":21.37,\"WEIGHTAVG_ROE\":13.1,\"XSMLL\":92.0}]}}"
  "A 股财报样本（2026-10-23 探测：`reportName=RPT_LICO_FN_CPD'，单位元，累计口径）。
报告期字段是 `REPORTDATE'（无下划线，实盘如此）；排序列与行内字段同名。
字段映射：TOTAL_OPERATE_INCOME→:revenue、PARENT_NETPROFIT→:net-profit、
YSTZ→:revenue-yoy、SJLTZ→:profit-yoy、BASIC_EPS→:eps、
WEIGHTAVG_ROE→:roe、XSMLL→:gross-margin。")

(defconst ths-info-test-fin-hk
  "{\"success\":1,\"result\":{\"pages\":1,\"data\":[\
{\"SECUCODE\":\"00700.HK\",\"REPORT_DATE\":\"2026-06-30T00:00:00\",\"OPERATE_INCOME\":364052000000.0,\"HOLDER_PROFIT\":107845000000.0,\"OPERATE_INCOME_YOY\":14.2,\"HOLDER_PROFIT_YOY\":16.7,\"BASIC_EPS\":11.31,\"ROE_AVG\":21.4,\"GROSS_PROFIT_RATIO\":56.3,\"CURRENCY\":\"CNY\"},\
{\"SECUCODE\":\"00700.HK\",\"REPORT_DATE\":\"2025-12-31T00:00:00\",\"OPERATE_INCOME\":660257000000.0,\"HOLDER_PROFIT\":194073000000.0,\"OPERATE_INCOME_YOY\":9.8,\"HOLDER_PROFIT_YOY\":12.1,\"BASIC_EPS\":20.44,\"ROE_AVG\":24.8,\"CURRENCY\":\"CNY\"}]}}"
  "港股财报样本（2026-10-23 探测：`reportName=RPT_HKF10_FN_MAININDICATOR'）。
字段映射：OPERATE_INCOME→:revenue、HOLDER_PROFIT→:net-profit、
OPERATE_INCOME_YOY→:revenue-yoy、HOLDER_PROFIT_YOY→:profit-yoy、
BASIC_EPS→:eps、ROE_AVG→:roe、GROSS_PROFIT_RATIO→:gross-margin。
第二期缺 GROSS_PROFIT_RATIO，用于断言「缺失即 nil，不填 0」。")

(defconst ths-info-test-fin-us
  "{\"success\":1,\"result\":{\"pages\":1,\"data\":[\
{\"SECUCODE\":\"AAPL.O\",\"REPORT\":\"2026/Q9\",\"ITEM_NAME\":\"营业总收入\",\"AMOUNT\":391035000000.0,\"YOY_RATIO\":6.1},\
{\"SECUCODE\":\"AAPL.O\",\"REPORT\":\"2026/Q9\",\"ITEM_NAME\":\"净利润\",\"AMOUNT\":93736000000.0,\"YOY_RATIO\":-3.4},\
{\"SECUCODE\":\"AAPL.O\",\"REPORT\":\"2026/Q9\",\"ITEM_NAME\":\"基本每股收益\",\"AMOUNT\":6.13,\"YOY_RATIO\":-2.1},\
{\"SECUCODE\":\"AAPL.O\",\"REPORT\":\"2026/Q9\",\"ITEM_NAME\":\"净资产收益率\",\"AMOUNT\":157.4,\"YOY_RATIO\":4.2},\
{\"SECUCODE\":\"AAPL.O\",\"REPORT\":\"2026/Q9\",\"ITEM_NAME\":\"毛利率\",\"AMOUNT\":46.2,\"YOY_RATIO\":0.8},\
{\"SECUCODE\":\"AAPL.O\",\"REPORT\":\"2025/Q9\",\"ITEM_NAME\":\"营业总收入\",\"AMOUNT\":368472000000.0,\"YOY_RATIO\":2.0},\
{\"SECUCODE\":\"AAPL.O\",\"REPORT\":\"2025/Q9\",\"ITEM_NAME\":\"净利润\",\"AMOUNT\":97007000000.0,\"YOY_RATIO\":-0.5},\
{\"SECUCODE\":\"AAPL.O\",\"REPORT\":\"2025/Q9\",\"ITEM_NAME\":\"基本每股收益\",\"AMOUNT\":6.26,\"YOY_RATIO\":0.4},\
{\"SECUCODE\":\"AAPL.O\",\"REPORT\":\"2025/Q9\",\"ITEM_NAME\":\"毛利率\",\"AMOUNT\":45.8,\"YOY_RATIO\":1.1}]}}"
  "美股财报样本（2026-10-23 探测：`reportName=RPT_USF10_FN_INCOME' 长表）。
数值列是 `AMOUNT'（不是 `ITEM_VALUE'，实盘 `ITEM_VALUE' 为 null）。
长表按 REPORT 分组、按 ITEM_NAME 映射：营业总收入→:revenue、净利润→:net-profit、
基本每股收益→:eps、净资产收益率→:roe、毛利率→:gross-margin，
同比一律取同一指标的 YOY_RATIO。`2025/Q9' 组缺「净资产收益率」。
报告期保留源标签 `YYYY/QN'（累计口径），不伪造日期。")

(defconst ths-info-test-industry-html
  (concat "<div class=\"nav\"><ul><li><a href=\"/corp/go.php/vCI_CorpOtherInfo\">"
          "所属行业</a></li></ul></div>\n"
          "<script type=\"text/template\"><tr><td class=\"ct\">@open@</td></tr></script>\n"
          "<table class=\"comInfo1\">"
          "<tr><td class=\"ct\" align=\"center\">所属行业板块：</td>"
          "<td class=\"ct\" align=\"center\">白酒</td></tr>"
          "<tr><td class=\"ct\" align=\"center\">上市日期：</td>"
          "<td class=\"ct\" align=\"center\">2001-08-27</td></tr></table>")
  "新浪 corpOther 行业片段（2026-10-23 探测：页面为 GBK，所属行业单元格是申万名「白酒」）。
前置导航（`所属行业'）与 JS 模板单元格（`@open@'）是实盘结构：旧解析取
「所属行业」后第一个 `<td>'，命中的正是 `@open@'。此处为已解码后的 UTF-8 文本；
GBK 解码链路由 `ths-info-gbk-decode' 单独覆盖。")

(defconst ths-info-test-thshy-list
  "<table class=\"m-table\"><tbody>
<tr><td><a href=\"http://q.10jqka.com.cn/thshy/detail/code/881273/\">白酒</a></td><td>2.54</td><td>881273</td></tr>
<tr><td><a href=\"http://q.10jqka.com.cn/thshy/detail/code/881155/\">银行</a></td><td>-0.31</td><td>881155</td></tr>
<tr><td><a href=\"http://q.10jqka.com.cn/thshy/detail/code/881121/\">半导体</a></td><td>1.08</td><td>881121</td></tr>
</tbody></table>"
  "同花顺行业列表样本（2026-10-23 探测：51 行、GBK；与「白酒」同粒度的申万二级名）。
此处为已解码文本：每行「行业名（锚文本） → 当日涨跌幅%」。")

(defconst ths-info-test-hq-macro
  "var hq_str_fx_susdcny=\"17:29:58,6.6702,6.6710,6.6680,6.6900,6.6600,6.6721,6.6702,美元人民币,2026-10-23\";
var hq_str_fx_shkdcny=\"17:29:58,0.8504,0.8506,0.8501,0.8530,0.8490,0.8512,0.8504,港元人民币,2026-10-23\";
var hq_str_DINIW=\"美元指数,101.8130,101.7900,101.9500,101.7000,101.8500,2026-10-23,15:30:00\";
var hq_str_hf_CL=\"101.031,0.512,0.51%,20:15:00,101.500,101.900,102.100,100.800,101.031,101.040,2026-10-23,原油,101.2,101.3,101.4,101.5\";
var hq_str_hf_GC=\"4039.155,12.340,0.31%,20:15:00,4040.000,4050.000,4060.000,4020.000,4039.155,4039.500,2026-10-23,黄金,1,2,3,4\";
var hq_str_hf_CHA50CFD=\"12996.640,-45.200,-0.35%,20:14:00,13040.000,13050.000,13100.000,12950.000,12996.640,12997.000,2026-10-23,富时A50,1,2,3,4\";
var hq_str_hf_HSI=\"23060.420,-212.500,-0.91%,20:15:00,23270.000,23300.000,23400.000,23000.000,23060.420,23061.000,2026-10-23,恒指期货,1,2,3,4\";
var hq_str_int_dji=\"道琼斯,46245.42,-123.45,-0.27\";
var hq_str_int_nasdaq=\"纳斯达克,20418.66,88.13,0.43\";
var hq_str_int_sp500=\"标普500,6624.71,-9.88,-0.15\";"
  "新浪 hq 宏观样本（2026-10-23 探测，需 Referer）。
索引口径：`fx_s*' 索引 1 为最新价；`DINIW' 索引 1；`hf_*' 15 字段索引 0 为最新价；
`int_*' 4 字段（名称/点位/涨跌额/涨跌幅%）。")

(defconst ths-info-test-hq-index
  (concat "var hq_str_sh000001=\"上证指数,3900.123,3880.000,3912.456,3920.000,3875.000,0.000,0.000,"
          "41000000000,412345678901.5,"
          (mapconcat #'identity (make-list 20 "0.000") ",")
          ",2026-10-23,15:00:00,00\";\n"
          "var hq_str_sz399001=\"深证成指,12900.100,12850.000,12980.500,13010.000,12820.000,0.000,0.000,"
          "52000000000,587654321098.5,"
          (mapconcat #'identity (make-list 20 "0.000") ",")
          ",2026-10-23,15:00:00,00\";")
  "新浪 hq 指数样本（2026-10-23 探测）：索引 9 为成交额（元）。
两市之和＝412345678901.5＋587654321098.5＝1.0e12，便于断言。")

(defconst ths-info-test-industry-html-gbk
  (concat (string-to-unibyte "<td class=\"ct\" align=\"center\">")
          (unibyte-string #xB0 #xD7 #xBE #xC6) ; 「白酒」的 GBK 字节
          (string-to-unibyte "</td>"))
  "GBK 非 UTF-8 样本：以 unibyte 字符串构造，「白酒」只以 GBK 字节存在。
用例内用 `decode-coding-string' + `gb18030' 解码后再解析，不依赖外部文件。")

;;;; 测试辅助

(defvar ths-info-test--http-log nil
  "逆序记录被拦截的请求，元素为 (CATEGORY . URL)。")

(defvar ths-info-test--http-plan nil
  "各类请求的预设行为：alist CATEGORY → `:ok' / `:fail' / `:empty' / `:silent'。
未列出的类别按 `:ok' 处理。")

(defvar ths-info-test--network-violations nil
  "记录绕过 `ths-info--http' 的真实网络/子进程调用；非空即用例失败。")

(defconst ths-info-test--bodies
  `((news . ,ths-info-test-search-jsonp)
    (ann-list . ,ths-info-test-ann-list-a)
    (ann-body . ,ths-info-test-ann-body)
    (financials . ,ths-info-test-fin-a)
    (industry-name . ,ths-info-test-industry-html)
    (industry-change . ,ths-info-test-thshy-list)
    (index . ,ths-info-test-hq-index)
    (macro . ,ths-info-test-hq-macro))
  "请求类别 → 响应体夹具。")

(defconst ths-info-test--stock
  '(:symbol "sh600519" :code "600519" :name "贵州茅台" :close 1400.0 :price 1420.0)
  "个股夹具，结构同 `ths-data-stocks' 的元素；collect 只应依赖 :symbol/:code。")

(defun ths-info-test--category (url)
  "Classify an intercepted URL into a fetch category.
The order matters: the announcement body lives under `/api/content/ann' and the
announcement list under `/api/security/ann'; both hosts belong to eastmoney, so
the specific paths are matched before the generic host."
  (cond
   ((string-match-p "jsonp" url) 'news)
   ((string-match-p "content/ann" url) 'ann-body)
   ((string-match-p "security/ann" url) 'ann-list)
   ((string-match-p "datacenter\\.eastmoney\\.com" url) 'financials)
   ((string-match-p "CorpOtherInfo" url) 'industry-name)
   ((string-match-p "thshy" url) 'industry-change)
   ((string-match-p "sh000001" url) 'index)
   ((string-match-p "hq\\.sinajs\\.cn" url) 'macro)
   ((string-match-p "qt\\.gtimg\\.cn" url) 'macro)
   (t 'other)))

(defun ths-info-test--network-violation (&rest args)
  "Record ARGS as a real network/subprocess attempt and return nil."
  (push args ths-info-test--network-violations)
  nil)

(defun ths-info-test--mock-http (url _params callback)
  "Stand-in for `ths-info--http' that never leaves the process.
URL is classified by `ths-info-test--category'; the behaviour comes from
`ths-info-test--http-plan' and the body from `ths-info-test--bodies'.  The
callback is invoked from a 0 s timer, i.e. asynchronously like the real
transport, so a collect implementation that assumes synchronous callbacks
fails here instead of in production."
  (let* ((category (ths-info-test--category url))
         (mode (or (cdr (assq category ths-info-test--http-plan)) :ok)))
    (push (cons category url) ths-info-test--http-log)
    (pcase mode
      (:ok (let ((body (cdr (assq category ths-info-test--bodies))))
             (run-at-time 0 nil (lambda () (funcall callback body 0)))))
      (:fail (run-at-time 0 nil (lambda () (funcall callback nil 1))))
      (:empty (run-at-time 0 nil (lambda () (funcall callback "" 0))))
      (:silent nil))
    (lambda () nil)))

(defun ths-info-test--call-count (category)
  "Return how many intercepted requests were classified as CATEGORY."
  (let ((n 0))
    (dolist (entry ths-info-test--http-log n)
      (when (eq (car entry) category) (setq n (1+ n))))))

(defun ths-info-test--total-calls ()
  "Return the number of intercepted requests."
  (length ths-info-test--http-log))

(defmacro ths-info-test--with-http (plan &rest body)
  "Run BODY with the transport stubbed according to PLAN.
PLAN is an alist of category → `:ok'/`:fail'/`:empty'/`:silent'.  Every
network primitive is also stubbed so that a source escaping `ths-info--http'
is recorded in `ths-info-test--network-violations' and fails the test."
  (declare (indent 1))
  `(let ((ths-info-test--http-log nil)
         (ths-info-test--http-plan ,plan)
         (ths-info-test--network-violations nil)
         (ths-info-timeout 1)
         (ths-info-cache-seconds 0))
     (cl-letf (((symbol-function 'ths-info--http)
                (symbol-function 'ths-info-test--mock-http))
               ((symbol-function 'make-process)
                (symbol-function 'ths-info-test--network-violation))
               ((symbol-function 'url-retrieve)
                (symbol-function 'ths-info-test--network-violation))
               ((symbol-function 'url-retrieve-synchronously)
                (symbol-function 'ths-info-test--network-violation))
               ((symbol-function 'shell-command)
                (symbol-function 'ths-info-test--network-violation))
               ((symbol-function 'shell-command-to-string)
                (symbol-function 'ths-info-test--network-violation)))
       ,@body
       (should-not ths-info-test--network-violations))))

(defun ths-info-test--await (predicate &optional seconds)
  "Wait until PREDICATE returns non-nil, advancing timers, up to SECONDS.
Returns PREDICATE's last value.  In batch, `accept-process-output' advances
timers, so the deferred mock callbacks run without real sleeping."
  (let ((deadline (+ (float-time) (or seconds 2.0)))
        (result nil))
    (while (and (not (setq result (funcall predicate)))
                (< (float-time) deadline))
      (accept-process-output nil 0.02))
    result))

(defun ths-info-test--error-note (errors key)
  "Return the error string recorded for KEY in ERRORS, or nil.
Both shapes are accepted — keyword (`:news') as used by INFO keys and plain
symbol (`news') — so that the lookup never depends on a naming detail that
the contract leaves open."
  (let ((hit (or (assq key errors)
                 (assq (intern (concat ":" (symbol-name key))) errors))))
    (cdr hit)))

(defmacro ths-info-test--with-switches (off &rest body)
  "Run BODY with every info switch on, except the symbols in OFF.
OFF is a list of symbols such as `(ths-ai-macro-enabled)'."
  (declare (indent 1))
  `(let ((ths-ai-news-enabled (not (memq 'ths-ai-news-enabled ,off)))
         (ths-ai-announcements-enabled (not (memq 'ths-ai-announcements-enabled ,off)))
         (ths-ai-financials-enabled (not (memq 'ths-ai-financials-enabled ,off)))
         (ths-ai-industry-enabled (not (memq 'ths-ai-industry-enabled ,off)))
         (ths-ai-macro-enabled (not (memq 'ths-ai-macro-enabled ,off))))
     ,@body))

;;;; 组 1：无关网络的纯函数

(ert-deftest ths-info-map-exit-status ()
  "Curl 退出码 → 错误文案：0 是成功，63 是响应体超限，其余是普通失败。"
  (should-not (ths-info--map-exit-status 0))
  (should (equal "响应过大" (ths-info--map-exit-status 63)))
  (should (equal "HTTP 请求失败 (1)" (ths-info--map-exit-status 1)))
  (should (equal "HTTP 请求失败 (28)" (ths-info--map-exit-status 28))))

(ert-deftest ths-info-strip-tags ()
  "标题里的搜索高亮标签必须去掉，纯文本原样返回。"
  (should (equal "600519 贵州茅台" (ths-info--strip-tags "<em>600519</em> 贵州茅台")))
  (should (equal "无标签标题" (ths-info--strip-tags "无标签标题")))
  (should (equal "600519 公告" (ths-info--strip-tags "<em>600519</em> 公告"))))

(ert-deftest ths-info-symbol-market ()
  "三市场的市场标识判定；个股 plist 与字符串两种入参都要接受。"
  (should (equal "a" (ths-info--symbol-market "sh600519")))
  (should (equal "a" (ths-info--symbol-market "sz000001")))
  (should (equal "a" (ths-info--symbol-market "bj920001")))
  (should (equal "hk" (ths-info--symbol-market "hk00700")))
  (should (equal "us" (ths-info--symbol-market "usAAPL")))
  ;; 项目惯例（同 `ths-data--market-symbol'）：collect 收到的是个股 plist。
  (should (equal "a" (ths-info--symbol-market (list :symbol "sh600519" :code "600519")))))

(ert-deftest ths-info-news-url-encodes-query ()
  "新闻 URL 指向东财搜索 JSONP，keyword 用六位代码，类型与条数显式给出。"
  (let ((url (ths-info--news-url "sh600519")))
    (should (stringp url))
    (should (string-match-p "\\`https://search-api-web\\.eastmoney\\.com/search/jsonp" url))
    (should (string-match-p "keyword=600519" url))
    (should (string-match-p "cmsArticleWebOld" url))
    (should (string-match-p "pageSize" url))))

(ert-deftest ths-info-news-parse-jsonp-and-tags ()
  "JSONP 剥壳 + 去标签：3 条，标题无 <em>，时间保留 YYYY-MM-DD HH:MM:SS，来源非空。"
  (let ((items (ths-info--news-parse ths-info-test-search-jsonp)))
    (should (listp items))
    (should (= 3 (length items)))
    (dolist (item items)
      (should (stringp (plist-get item :title)))
      (should-not (string-match-p "[<>]" (plist-get item :title)))
      (should (string-match-p
               "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}\\'"
               (plist-get item :time)))
      (should (and (stringp (plist-get item :source))
                   (not (string-empty-p (plist-get item :source))))))
    (should (equal "600519 贵州茅台三季度净利润同比增长 8.9%"
                   (plist-get (car items) :title)))
    (should (equal "2026-10-22 15:13:16" (plist-get (car items) :time)))
    (should (equal "证券时报" (plist-get (car items) :source)))))

(ert-deftest ths-info-news-parse-bad-json ()
  "解析失败或空响应返回 nil，不抛错（降级由调用方记录 ERRORS）。"
  (should-not (ths-info--news-parse "<html><body>404</body></html>"))
  (should-not (ths-info--news-parse "cb()"))
  (should-not (ths-info--news-parse ""))
  (should-not (ths-info--news-parse "cb({\"code\":0,\"result\":{\"cmsArticleWebOld\":[]}})")))

(ert-deftest ths-info-announcements-parse-a ()
  "A 股公告列表：3 条，art-code 非空，时间保留源格式。"
  (let ((items (ths-info--announcements-parse ths-info-test-ann-list-a)))
    (should (listp items))
    (should (= 3 (length items)))
    (should (equal "AN2026102200001" (plist-get (car items) :art-code)))
    (should (equal "贵州茅台2026年第三季度报告" (plist-get (car items) :title)))
    (should (equal "2026-10-22 00:00:00" (plist-get (car items) :time)))
    (dolist (item items)
      (should (and (stringp (plist-get item :art-code))
                   (not (string-empty-p (plist-get item :art-code))))))))

(ert-deftest ths-info-announcements-parse-us-empty ()
  "200 + 空数组（美股）必须降级为 nil，不能当成功发空小节。"
  (should-not (ths-info--announcements-parse ths-info-test-ann-list-us-empty))
  (should-not (ths-info--announcements-parse
               "{\"success\":1,\"data\":{\"list\":[]}}")))

(ert-deftest ths-info-announcement-body-pages ()
  "正文 + 分页：A 股 page_size=1；港股 page_size=380 是总页数（不是字数）。"
  (let ((a (ths-info--announcement-body-parse ths-info-test-ann-body))
        (hk (ths-info--announcement-body-parse ths-info-test-ann-body-hk-paged)))
    (should (equal 1 (plist-get a :pages)))
    (should (stringp (plist-get a :content)))
    (should (string-match-p "第三季度报告" (plist-get a :content)))
    (should (equal 380 (plist-get hk :pages)))
    (should (> (plist-get hk :pages) 1))
    (should (string-match-p "貴州" (plist-get hk :content)))))

(ert-deftest ths-info-financials-parse-a ()
  "A 股财报：报告期归一为 YYYY-MM-DD，营收/净利为 number，同比字段齐全。"
  (let* ((rows (ths-info--financials-parse "a" ths-info-test-fin-a))
         (latest (car rows)))
    (should (= 2 (length rows)))
    (should (equal "2026-06-30" (plist-get latest :period)))
    (should (equal "2026-03-31" (plist-get (cadr rows) :period)))
    (should (numberp (plist-get latest :revenue)))
    (should (< (abs (- 92278072083.21 (plist-get latest :revenue))) 0.01))
    (should (numberp (plist-get latest :net-profit)))
    (should (< (abs (- 46100000000.0 (plist-get latest :net-profit))) 0.01))
    (should (< (abs (- 9.16 (plist-get latest :revenue-yoy))) 1e-6))
    (should (< (abs (- 8.9 (plist-get latest :profit-yoy))) 1e-6))
    (should (< (abs (- 36.72 (plist-get latest :eps))) 1e-6))
    (should (< (abs (- 24.5 (plist-get latest :roe))) 1e-6))
    (should (< (abs (- 91.5 (plist-get latest :gross-margin))) 1e-6))
    ;; 空列表 → nil，不伪造条目。
    (should-not (ths-info--financials-parse
                 "a" "{\"success\":1,\"result\":{\"data\":[]}}"))))

(ert-deftest ths-info-financials-parse-hk ()
  "港股财报：指标名映射到同一套 key；缺失字段保持 nil（不得用 0 顶替）。"
  (let* ((rows (ths-info--financials-parse "hk" ths-info-test-fin-hk))
         (latest (car rows))
         (older (cadr rows)))
    (should (= 2 (length rows)))
    (should (equal "2026-06-30" (plist-get latest :period)))
    (should (numberp (plist-get latest :revenue)))
    (should (< (abs (- 364052000000.0 (plist-get latest :revenue))) 1.0))
    (should (< (abs (- 107845000000.0 (plist-get latest :net-profit))) 1.0))
    (should (< (abs (- 14.2 (plist-get latest :revenue-yoy))) 1e-6))
    (should (< (abs (- 16.7 (plist-get latest :profit-yoy))) 1e-6))
    (should (< (abs (- 11.31 (plist-get latest :eps))) 1e-6))
    (should (< (abs (- 21.4 (plist-get latest :roe))) 1e-6))
    (should (< (abs (- 56.3 (plist-get latest :gross-margin))) 1e-6))
    ;; 第二期没有毛利率：nil（注意 0 在 elisp 里是真值，`should-not' 能抓住 0）。
    (should-not (plist-get older :gross-margin))))

(ert-deftest ths-info-financials-parse-us ()
  "美股财报：长表按 REPORT 分组、按 ITEM_NAME 映射；缺项为 nil。"
  (let* ((rows (ths-info--financials-parse "us" ths-info-test-fin-us))
         (latest (car rows))
         (older (cadr rows)))
    (should (= 2 (length rows)))
    (should (string-match-p "\\`2026/Q9\\'" (plist-get latest :period)))
    (should (string-match-p "\\`2025/Q9\\'" (plist-get older :period)))
    (should (< (abs (- 391035000000.0 (plist-get latest :revenue))) 1.0))
    (should (< (abs (- 93736000000.0 (plist-get latest :net-profit))) 1.0))
    (should (< (abs (- 6.1 (plist-get latest :revenue-yoy))) 1e-6))
    (should (< (abs (- -3.4 (plist-get latest :profit-yoy))) 1e-6))
    (should (< (abs (- 6.13 (plist-get latest :eps))) 1e-6))
    (should (< (abs (- 46.2 (plist-get latest :gross-margin))) 1e-6))
    (should (numberp (plist-get latest :roe)))
    (should-not (plist-get older :roe))))

(ert-deftest ths-info-financials-sort-column-is-reportdate ()
  "A 股财报排序列必须是 `REPORTDATE'：源侧拒收 `REPORT_DATE'（2026-10-23 实测）。"
  (let ((url (ths-info--financials-url "sh600519")))
    (should (string-match-p "sortColumns=REPORTDATE" url))
    (should-not (string-match-p "REPORT_DATE" url))
    ;; 单参派生（市场 + 代码）与显式两参形式必须一致。
    (should (equal url (ths-info--financials-url "a" "600519")))
    ;; 港股报告确实用下划线拼写，保持 `REPORT_DATE'。
    (should (string-match-p "sortColumns=REPORT_DATE"
                            (ths-info--financials-url "hk" "00700")))
    ;; 美股长表按 `REPORT' 排序，不受影响。
    (should (string-match-p "sortColumns=REPORT&"
                            (ths-info--financials-url "us" "AAPL")))))

(ert-deftest ths-info-financials-us-reads-amount ()
  "美股长表的数值在 `AMOUNT'：每期不得只剩 `:period'。"
  (let* ((rows (ths-info--financials-parse "us" ths-info-test-fin-us))
         (latest (car rows)))
    (should (numberp (plist-get latest :revenue)))
    (should (< (abs (- 391035000000.0 (plist-get latest :revenue))) 1.0))
    ;; 旧拼写 `ITEM_VALUE' 仍被接受，源侧换拼写时不至于整表全空。
    (let* ((legacy (concat "{\"success\":1,\"result\":{\"data\":["
                           "{\"REPORT\":\"2026/Q9\",\"ITEM_NAME\":\"营业总收入\","
                           "\"ITEM_VALUE\":1314000000,\"YOY_RATIO\":1.5}]}}"))
           (row (car (ths-info--financials-parse "us" legacy))))
      (should (= 1314000000 (plist-get row :revenue)))
      (should (< (abs (- 1.5 (plist-get row :revenue-yoy))) 1e-9)))))

(ert-deftest ths-info-industry-parse-name ()
  "新浪 corpOther：取「所属行业板块」单元格，返回申万细分名。"
  (let ((info (ths-info--industry-parse ths-info-test-industry-html)))
    (should (listp info))
    (should (equal "白酒" (plist-get info :name)))
    ;; 前置导航里的 `所属行业' 与 JS 模板 `@open@' 都不得被当作行业名。
    (should-not (string-match-p "@" (plist-get info :name))))
  ;; 页面结构不符 → nil，不是空字符串。
  (should-not (ths-info--industry-parse "<html><body>没有行业单元格</body></html>")))

(ert-deftest ths-info-industry-parse-skips-template ()
  "锚定「所属行业板块」表格：跳过导航文字与 `@open@' 模板占位符。"
  (let* ((html (concat "<div class=\"nav\"><ul><li>所属行业</li></ul></div>"
                       "<script><tr><td class=\"ct\">@open@</td></tr></script>"
                       "<table><tr><td class=\"ct\">所属行业板块：</td>"
                       "<td class=\"ct\">白酒Ⅱ</td></tr></table>"))
         (info (ths-info--industry-parse html)))
    (should (listp info))
    (should (equal "白酒Ⅱ" (plist-get info :name)))
    (should-not (string-match-p "@" (plist-get info :name))))
  ;; 整页只有占位符 → nil，而不是 `@open@'。
  (should-not (ths-info--industry-parse
               "<table><tr><td class=\"ct\">@open@</td></tr></table>")))

(ert-deftest ths-info-industry-change-match ()
  "同花顺行业列表按名字匹配当日涨跌幅；匹配不到返回 nil。"
  (let ((hit (ths-info--industry-change ths-info-test-thshy-list "白酒")))
    (should (listp hit))
    (should (equal "白酒" (plist-get hit :name)))
    (should (numberp (plist-get hit :change)))
    (should (< (abs (- 2.54 (plist-get hit :change))) 1e-6)))
  (should-not (ths-info--industry-change ths-info-test-thshy-list "光伏")))

(ert-deftest ths-info-macro-parse-values ()
  "宏观 8 项取值正确；缺失项为 nil（不填 0）。"
  (let ((macro (ths-info--macro-parse ths-info-test-hq-macro))
        (partial (ths-info--macro-parse
                  "var hq_str_fx_susdcny=\"17:29:58,6.6702,6.6710\";")))
    (dolist (key '(:fx-usdcny :fx-hkdcny :dollar-index :oil :gold :a50 :hsi-future))
      (should (numberp (plist-get macro key))))
    (should (< (abs (- 6.6702 (plist-get macro :fx-usdcny))) 1e-9))
    (should (< (abs (- 0.8504 (plist-get macro :fx-hkdcny))) 1e-9))
    (should (< (abs (- 101.8130 (plist-get macro :dollar-index))) 1e-9))
    (should (< (abs (- 101.031 (plist-get macro :oil))) 1e-9))
    (should (< (abs (- 4039.155 (plist-get macro :gold))) 1e-9))
    (should (< (abs (- 12996.640 (plist-get macro :a50))) 1e-9))
    (should (< (abs (- 23060.420 (plist-get macro :hsi-future))) 1e-9))
    (let ((overnight (plist-get macro :overnight)))
      (should (listp overnight))
      (should (< (abs (- 46245.42 (plist-get overnight :dji))) 1e-6))
      (should (< (abs (- 20418.66 (plist-get overnight :nasdaq))) 1e-6))
      (should (< (abs (- 6624.71 (plist-get overnight :sp500))) 1e-6)))
    ;; 只有汇率时其余全部 nil。
    (should (< (abs (- 6.6702 (plist-get partial :fx-usdcny))) 1e-9))
    (should-not (plist-get partial :gold))
    (should-not (plist-get partial :dollar-index))
    (should-not (plist-get partial :overnight))))

(ert-deftest ths-info-turnover-parse-sums ()
  "两市成交额按索引 9（元）求和。"
  (let ((sum (ths-info--turnover-parse ths-info-test-hq-index)))
    (should (numberp sum))
    (should (< (abs (- sum 1.0e12)) 1.0))))

(ert-deftest ths-info-gbk-decode ()
  "GBK unibyte → gb18030 解码 → 中文可读 → 行业解析命中。"
  (let* ((decoded (decode-coding-string ths-info-test-industry-html-gbk 'gb18030))
         (info (ths-info--industry-parse decoded)))
    (should (multibyte-string-p decoded))
    (should (string-match-p "白酒" decoded))
    (should (equal "白酒" (plist-get info :name)))))

(ert-deftest ths-info-macro-url-honours-custom-symbols ()
  "宏观 URL 读 `ths-ai-macro-symbols'，不再用硬编码常量。
定制过的代码列表必须真的改变请求，否则该 defcustom 是死选项。"
  (let ((ths-ai-macro-symbols "fx_susdcny"))
    (should (equal "https://hq.sinajs.cn/list=fx_susdcny"
                   (ths-info--macro-url))))
  ;; 未定制时用默认清单：三份默认值（`ths-ai-macro-symbols'、
  ;; `ths-info--macro-symbols' 与这里的断言）必须一致，含港股汇率。
  (should (string-match-p "fx_shkdcny" (ths-info--macro-url))))

(ert-deftest ths-info-cache-prunes-expired ()
  "写入新条目时清扫过期条目，长会话不会无界增长。
TTL 只决定是否复用，从不删除；没有清扫时缓存表会随会话无限增长。"
  (let ((ths-info-cache-seconds 120)
        (now (float-time)))
    (clrhash ths-info--cache)
    (unwind-protect
        (progn
          ;; 两倍 TTL 以上 → 应被清扫；TTL 附近 → 保留。
          (puthash 'stale (cons (- now 1000) 'old) ths-info--cache)
          (puthash 'acceptable (cons (- now 200) 'kept) ths-info--cache)
          (should (equal 'stored (ths-info--cache-put 'fresh 'stored)))
          (should-not (gethash 'stale ths-info--cache))
          (should (equal 'kept (cdr (gethash 'acceptable ths-info--cache))))
          (should (equal 'stored (cdr (gethash 'fresh ths-info--cache)))))
      (clrhash ths-info--cache))))

;;;; 组 2：异步编排（`ths-info--http' 全程被 mock，零真实请求）

(ert-deftest ths-info-collect-calls-all-sources ()
  "五类源全部发起：news 1、公告 1+1、财报 1、行业 1+1、宏观 1、成交额 1，INFO 齐全。"
  (ths-info-test--with-http nil
    (ths-info-test--with-switches nil
      (let ((calls 0)
            (info nil)
            (errors 'unset))
        (ths-info-collect ths-info-test--stock
                          (lambda (i e)
                            (setq calls (1+ calls) info i errors e)))
        (should (ths-info-test--await (lambda () (> calls 0))))
        (should (= 1 calls))
        (should-not errors)
        (should (= 1 (ths-info-test--call-count 'news)))
        (should (= 1 (ths-info-test--call-count 'ann-list)))
        (should (= 1 (ths-info-test--call-count 'ann-body)))
        (should (= 1 (ths-info-test--call-count 'financials)))
        (should (= 1 (ths-info-test--call-count 'industry-name)))
        (should (= 1 (ths-info-test--call-count 'industry-change)))
        (should (= 1 (ths-info-test--call-count 'macro)))
        (should (= 1 (ths-info-test--call-count 'index)))
        (should (= 0 (ths-info-test--call-count 'other)))
        (should (= 8 (ths-info-test--total-calls)))
        ;; INFO 结构
        (should (= 3 (length (plist-get info :news))))
        (should (= 3 (length (plist-get info :announcements))))
        (should (= 2 (length (plist-get info :financials))))
        (should (equal "白酒" (plist-get (plist-get info :industry) :name)))
        (should (< (abs (- 2.54 (plist-get (plist-get info :industry) :change))) 1e-6))
        (should (numberp (plist-get (plist-get info :macro) :fx-usdcny)))
        (should (< (abs (- 1.0e12 (plist-get info :turnover))) 1.0))
        ;; 重复调用各自独立：第二次仍回调自己的 callback。
        (let ((second 0))
          (ths-info-collect ths-info-test--stock
                            (lambda (_i _e) (setq second (1+ second))))
          (should (ths-info-test--await (lambda () (> second 0))))
          (should (= 1 second)))))))

(ert-deftest ths-info-collect-body-keeps-cache-object-clean ()
  "正文走 INFO 独立键 `:announcement-body'，命中的公告列表缓存对象永不被改写。
往缓存列表的条目前追加正文键（`setcar'）会让第二次命中在旧条目上再追加一遍，
`:content'/`:pages' 因此重复累积；独立键只读列表，缓存条目保持解析出来的原样。"
  (ths-info-test--with-http nil
    (ths-info-test--with-switches nil
      (let ((ths-info-cache-seconds 3600)
            (first nil)
            (second nil)
            (calls 0))
        (clrhash ths-info--cache)
        (unwind-protect
            (progn
              (ths-info-collect ths-info-test--stock
                                (lambda (info _e) (setq first info calls (1+ calls))))
              (should (ths-info-test--await (lambda () (> calls 0))))
              (setq calls 0)
              (ths-info-collect ths-info-test--stock
                                (lambda (info _e) (setq second info calls (1+ calls))))
              (should (ths-info-test--await (lambda () (> calls 0))))
              ;; 第二次全走缓存：公告列表与正文都不再发起请求。
              (should (= 1 (ths-info-test--call-count 'ann-list)))
              (should (= 1 (ths-info-test--call-count 'ann-body)))
              ;; 两次的 INFO 结构相同：正文只出现在独立键上，条目里没有正文键。
              (dolist (info (list first second))
                (should (stringp (plist-get (plist-get info :announcement-body) :content)))
                (should (= 3 (length (plist-get info :announcements))))
                (dolist (item (plist-get info :announcements))
                  (should-not (plist-member item :content))
                  (should-not (plist-member item :pages))))
              ;; 两次拿到的是同一个缓存对象，且它仍是干净的三条。
              (should (eq (plist-get first :announcements)
                          (plist-get second :announcements)))
              (let ((cached (ths-info--cache-get (list :announcements "sh600519"))))
                (should (consp cached))
                (should (= 3 (length cached)))
                (dolist (item cached)
                  (should-not (plist-member item :content))
                  (should-not (plist-member item :pages))))
              ;; 缓存里的公告列表等价于解析结果：没有键累积。
              (should (equal (ths-info--announcements-parse ths-info-test-ann-list-a)
                             (plist-get second :announcements))))
          (clrhash ths-info--cache))))))

(ert-deftest ths-info-collect-degrades-single-source ()
  "单源失败只把该因子置 nil 并写入 ERRORS，其余因子照常返回。"
  (ths-info-test--with-http '((news . :fail))
    (ths-info-test--with-switches nil
      (let ((calls 0)
            (info nil)
            (errors nil))
        (ths-info-collect ths-info-test--stock
                          (lambda (i e)
                            (setq calls (1+ calls) info i errors e)))
        (should (ths-info-test--await (lambda () (> calls 0))))
        (should (= 1 calls))
        (should-not (plist-get info :news))
        (should (stringp (ths-info-test--error-note errors 'news)))
        (should (string-match-p "HTTP 请求失败 (1)"
                                (ths-info-test--error-note errors 'news)))
        (should (= 3 (length (plist-get info :announcements))))
        (should (= 2 (length (plist-get info :financials))))
        (should (equal "白酒" (plist-get (plist-get info :industry) :name)))
        (should (numberp (plist-get (plist-get info :macro) :fx-usdcny)))
        (should (numberp (plist-get info :turnover)))))))

(ert-deftest ths-info-collect-honours-switches ()
  "开关关闭的类别既不请求也不出现在 INFO 中。"
  (ths-info-test--with-http nil
    (ths-info-test--with-switches '(ths-ai-news-enabled ths-ai-macro-enabled)
      (let ((calls 0)
            (info nil))
        (ths-info-collect ths-info-test--stock
                          (lambda (i _e) (setq calls (1+ calls) info i)))
        (should (ths-info-test--await (lambda () (> calls 0))))
        (should (= 1 calls))
        (should (= 0 (ths-info-test--call-count 'news)))
        (should (= 0 (ths-info-test--call-count 'macro)))
        (should (= 0 (ths-info-test--call-count 'index)))
        (should (= 1 (ths-info-test--call-count 'ann-list)))
        (should (= 1 (ths-info-test--call-count 'financials)))
        (should-not (plist-get info :news))
        (should-not (plist-get info :macro))
        (should-not (plist-get info :turnover))
        (should (plist-get info :announcements))))))

(ert-deftest ths-info-collect-timeout-partial ()
  "总超时：回调仍被调用一次，已完成的因子保留，未完成的置 nil。"
  (ths-info-test--with-http '((ann-list . :silent)
                              (ann-body . :silent)
                              (financials . :silent)
                              (industry-name . :silent)
                              (industry-change . :silent)
                              (macro . :silent)
                              (index . :silent))
    (ths-info-test--with-switches nil
      (let ((ths-info-timeout 0.05)
            (calls 0)
            (info nil))
        (ths-info-collect ths-info-test--stock
                          (lambda (i _e) (setq calls (1+ calls) info i)))
        (should (ths-info-test--await (lambda () (> calls 0)) 3.0))
        (should (= 1 calls))
        (should (= 3 (length (plist-get info :news))))
        (should-not (plist-get info :announcements))
        (should-not (plist-get info :financials))
        (should-not (plist-get info :industry))
        (should-not (plist-get info :macro))
        (should-not (plist-get info :turnover))))))

(ert-deftest ths-info-collect-returns-cancel ()
  "返回 cancel 函数；取消后到点也不再回调，且不抛错。"
  (ths-info-test--with-http '((news . :silent)
                              (ann-list . :silent)
                              (ann-body . :silent)
                              (financials . :silent)
                              (industry-name . :silent)
                              (industry-change . :silent)
                              (macro . :silent)
                              (index . :silent))
    (ths-info-test--with-switches nil
      (let ((ths-info-timeout 5)
            (calls 0)
            cancel)
        (setq cancel (ths-info-collect ths-info-test--stock
                                       (lambda (_i _e) (setq calls (1+ calls)))))
        (should (functionp cancel))
        (should-not (condition-case err (progn (funcall cancel) nil) (error err)))
        ;; 取消后即使等到超时点也不得再回调。
        (should-not (ths-info-test--await (lambda () (> calls 0)) 0.5))
        (should (= 0 calls))))))

(ert-deftest ths-info-collect-nil-stock-fetches-macro-only ()
  "无个股（盘面分析）时仍抓宏观与两市成交额，其余四类跳过且不记 ERRORS。
宏观面板与成交额是全市场读数，与标的无关：`ths-ai--analyze-one' 对
`key='market' 传的正是 nil stock，若也放在 symbol 判空之内，盘面事实的
`:macro'/`:turnover' 恒空，B5 的盘面宏观小节在生产路径上永远不渲染。
跳过其余四类是因为没有标的可查，不是失败，因此 ERRORS 必须为空。"
  (ths-info-test--with-http nil
    (ths-info-test--with-switches nil
      (let ((calls 0)
            (info nil)
            (errors 'unset))
        (ths-info-collect nil
                          (lambda (i e)
                            (setq calls (1+ calls) info i errors e)))
        (should (ths-info-test--await (lambda () (> calls 0))))
        (should (= 1 calls))
        ;; 恰好两个请求：宏观面板（macro）＋ 两市成交额（URL 含 sh000001，归 index 类）。
        (should (= 2 (ths-info-test--total-calls)))
        (should (= 1 (ths-info-test--call-count 'macro)))
        (should (= 1 (ths-info-test--call-count 'index)))
        (dolist (category '(news ann-list ann-body financials
                            industry-name industry-change other))
          (should (= 0 (ths-info-test--call-count category))))
        ;; INFO 只有宏观与成交额。
        (should (numberp (plist-get (plist-get info :macro) :fx-usdcny)))
        (should (< (abs (- 1.0e12 (plist-get info :turnover))) 1.0))
        (dolist (key '(:news :announcements :financials :industry))
          (should-not (plist-get info key)))
        ;; 没有标的 ≠ 抓取失败：ERRORS 保持为空。
        (should-not errors)))))

(defun ths-info-test--drop-http-advices ()
  "Remove every advice on `ths-info--http' and return the removed entries.
`tests/ths-ai-tests.el' 在同一个 batch 进程里给 `ths-info--http' 装了 `:override'
advice（同步失败的离线桩），它的 `cl-letf' 用户靠替换 `symbol-function' 绕开该
advice；要验证**真实**传输层（`--max-filesize' / 延迟交付）的用例必须先把 advice
摘掉，否则测到的是桩。返回值为 (FUNCTION . PROPS) 列表，供恢复使用。"
  (let (entries)
    (advice-mapc (lambda (fn props) (push (cons fn props) entries))
                 'ths-info--http)
    (dolist (entry entries)
      (advice-remove 'ths-info--http (car entry)))
    entries))

(defun ths-info-test--restore-http-advices (entries)
  "Re-install ENTRIES returned by `ths-info-test--drop-http-advices'."
  (dolist (entry entries)
    (advice-add 'ths-info--http :override (car entry))))

(ert-deftest ths-info-collect-http-failure-records-all-sources ()
  "传输层整体失败（`make-process' 抛错）时 ERRORS 记录全部已开启因子。
`ths-info--http' 的错误分支必须延迟交付：同步回调会让 collect 在装配其余请求
之前就 finish，ERRORS 里只剩第一个因子，其余被静默吞掉。"
  (let ((advices (ths-info-test--drop-http-advices)))
    (unwind-protect
        (cl-letf (((symbol-function 'make-process)
                   (lambda (&rest _args) (error "make-process failed")))
                  ((symbol-function 'url-retrieve)
                   (symbol-function 'ths-info-test--network-violation))
                  ((symbol-function 'url-retrieve-synchronously)
                   (symbol-function 'ths-info-test--network-violation))
                  ((symbol-function 'shell-command)
                   (symbol-function 'ths-info-test--network-violation))
                  ((symbol-function 'shell-command-to-string)
                   (symbol-function 'ths-info-test--network-violation)))
          (let ((ths-info-test--network-violations nil)
                (ths-info-timeout 5)
                (ths-info-cache-seconds 0))
            (ths-info-test--with-switches nil
              (let ((calls 0)
                    (info 'unset)
                    (errors nil))
                (ths-info-collect ths-info-test--stock
                                  (lambda (i e)
                                    (setq calls (1+ calls) info i errors e)))
                (should (ths-info-test--await (lambda () (> calls 0))))
                (should (= 1 calls))
                ;; 六个独立请求各自失败：新闻、公告列表、财报、行业名、宏观、成交额。
                (should (= 6 (length errors)))
                (dolist (key '(:news :announcements :financials :industry
                               :macro :turnover))
                  (should (string-match-p "HTTP 请求失败 (1)"
                                          (ths-info-test--error-note errors key))))
                (should-not info)
                (should-not ths-info-test--network-violations)))))
      (ths-info-test--restore-http-advices advices))))

(provide 'ths-info-tests)
;;; ths-info-tests.el ends here
;; ths-info-tests.el ends here
