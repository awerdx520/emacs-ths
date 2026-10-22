# THS AI 投机建议与盘面分析

## 当前状态

- 阶段：Phase 4（Review & Document）· **已完成并归档**
- 已确认：方案 ✅、计划 ✅（用户 2026-10-22）
- 交付：`ths-ai.el`（新增）、`ths.el`（集成）、`tests/ths-ai-tests.el`（56 例）、README/CHANGELOG 更新
- 审查：plan-reviewer（1 轮需修订→修订）、code-reviewer（首轮需修订→复审通过）、security-reviewer（3 轮需修订→终审签核通过）
- 验证：全量离线 ERT `Ran 165, 162 expected, 3 unexpected`（3 例为 pre-existing 基线红，已登记 tech-debt）；字节编译/checkdoc/parens 全 0 警告
- 遗留：见 `openspec/tech-debt.md`（Makefile 缺失、3 例基线红、报告 buffer 悬空引用、scheme 匹配未跳过 http(s) URL 内部、`org-link-*-confirm-function` 旧别名）

### 审查修复记录（第 1 轮）

来源：安全审查 P0/P1（H1、M2、M3、M4、L6、L7、L8、L9）与代码审查 minor（session 校验、围栏剥离、`defvar-local`）。
全部验证在 `emacs -Q --batch`（pure 语义）下完成；`ths.el` 未改动。

| # | 修复项 | 落点（函数） | 对应测试 |
|---|---|---|---|
| H1 | 聚合行匿名：`:strongest`/`:weakest` 只发 `(:change NUMBER)`，不再带 `:name`；提示词标签改为「自选池最强/最弱个股（匿名）涨幅」 | `ths-ai--extreme-stock`、`ths-ai--market-facts`、`ths-ai--market-fact-order` | `ths-ai-market-facts-omit-symbol-names` |
| H1 | 个股事实保留 `:name`/`:code`/`:sector`（个股分析必需） | `ths-ai--stock-facts` | `ths-ai-stock-facts-summarises-quote-and-series`（既有，未放宽） |
| M3 | 强制 https：请求发出前校验端点前缀，不满足则同步失败且不发起请求 | `ths-ai--http-request` | `ths-ai-request-rejects-non-https-url` |
| M3 | 证书校验硬失败：`gnutls-verify-error` 绑定 `t` 包裹 `url-retrieve`；文件顶部加 `defvar` 声明 | `ths-ai--http-request`（+ 声明区） | 字节编译 0 警告 + L2 传输层用例 |
| M3 | 密钥净化：先 `string-trim`，残留 `[\r\n]` 视为无密钥并返回 nil（文案不回显密钥） | `ths-ai--clean-key`、`ths-ai--http-key` | `ths-ai-request-rejects-non-https-url`（密钥路径覆盖）+ 探针验证内联 CRLF 拒绝 |
| L6 | 禁用 cookie：`url-retrieve` 第 5 参数 `inhibit-cookies` 传 `t` | `ths-ai--http-request` | 字节编译 + 代码断言 |
| L7 | 响应体上限 1 MiB：超限返回失败「AI 响应过大，已丢弃」，不进入 `json-parse-string` | `ths-ai--http-body-limit`、`ths-ai--http-body`（返回 `(BODY . ERROR)`） | `ths-ai-http-body-rejects-oversized-response` |
| L8 | url-debug 抑制：请求期间从 `url-debug` 中 `delq` `http`，`*URL-DEBUG*` 不会记录 Authorization | `ths-ai--http-request` | 字节编译 + 代码断言 |
| M2/M4 | 供应商字段净化：`format` → 折叠 `[\r\n\t]+` → `string-trim` → 截断 32 列 | `ths-ai--field`（用于 `:name`/`:sector`/成交记录字符串字段） | `ths-ai-stock-facts-flatten-provider-strings` |
| M2/M4 | 提示词数据边界：事实块用 `<<<DATA`/`DATA>>>` 包裹；system 增加第 5 条硬约束（数据非指令） | `ths-ai--prompt`、`ths-ai--system` | `ths-ai-prompt-states-json-contract-and-disclaimer`（既有）+ 探针断言 |
| M2/M4 | 模型输出净化：行首 `#+`/`[[`/`#|` 加反斜杠转义；单行字段先折行；nil 与非字符串原样返回 | `ths-ai--sanitise`、`ths-ai--sanitise-line` | `ths-ai-report-neutralises-org-directives` |
| M2/M4 | 渲染层应用净化：`report`/`stock-section`/`market-section`/`bullet-list`/`summary-line`/`panel-line` | 同名函数 | `ths-ai-report-neutralises-org-directives`、`ths-ai-summary-line-truncates-to-width`（既有） |
| M2/M4 | org 启动副作用抑制：`(let ((org-inhibit-startup t)) (org-mode))` | `ths-ai--present` | `ths-ai-analyze-fills-results-and-report-buffer`（既有，未放宽） |
| minor | session 校验收紧为 `(and current (eq session current))`，与 `ths--fetch` 对齐 | `ths-ai--analyze-one` | 组 (b)/(c) 11 例全绿（无用例受影响，见下） |
| minor | 围栏剥离只删「整行即围栏」的行 | `ths-ai--strip-fence` | `ths-ai-parse-keeps-json-on-same-line-as-fence` |
| minor | `ths-ai--request-kind` 改 `defvar-local` | 同声明 | 字节编译 0 警告 |

**口径说明**

- H1 采用「只发聚合量」方案：`ths-ai--extreme-stock` 只返回涨跌幅，名称不出缓冲区；个股分析仍保留名称/代码/板块。
  README 中「最强 / 最弱」的表述将在**文档轮次**同步为「自选池最强/最弱个股（匿名）涨幅」。
- session 校验收紧后未出现新增红：组 (b)/(c) 全部用例都在 `ths-test-with-dashboard` 内运行，而该宏调用 `(ths)`，
  `ths.el:1237` 会把 `ths--session` 置为 `(list 'ths-session)`，故 `(and current (eq session current))` 成立；
  断言未放宽，亦无用例被改。
- `ths-ai--http-body` 的返回契约由「字符串或 nil」改为 `(BODY . ERROR)`：超限时 `car` 为 nil、`cdr` 为失败文案，
  `ths-ai--http-request` 的回调据此直接给出失败，不再落到 `json-parse-string`。唯一调用点已同步。

**本轮验证快照（2026-10-23，`emacs -Q --batch` + BOOT）**

- 组 (a) 选择器 `\\`ths-ai-\(stock-facts\|market-facts\|prompt\|parse\|summary-line\|report-includes\)`：`Ran 14, 14 expected, 0 unexpected`
  （原 11 例 + `stock-facts-flatten` + `market-facts-omit` + `parse-keeps-json`）。
- 组 (b)+(c) 选择器 `\\`ths-ai-\(analyze-\|request-\|panel-shows\|mode-map-binds\|report-window-closes\|fills-results\)`：
  `Ran 11, 11 expected, 0 unexpected`（原 6+4 + `request-rejects-non-https-url`）。
- `tests/ths-ai-tests.el` 全文件：`Ran 41, 40 expected, 1 unexpected`，唯一红 = 基线
  `ths-fixture-charts-and-book-have-consistent-bounds`（无新增 unexpected）。
- 11 文件全量离线套件：`Ran 150, 147 expected, 3 unexpected`，3 红与既有基线逐字一致。
- L1：`ths-ai.el` 严格字节编译（`byte-compile-error-on-warn t`）**0 警告**、checkdoc **0 警告**、
  `check-parens` OK；`tests/ths-ai-tests.el` `check-parens` OK（3 条 checkdoc 告警全部落在本轮未改动的
  fixture docstring，属既有问题）。测后 `rm -f *.elc` 无残留。


**验证快照（2026-10-22，T6 完成，`emacs -Q --batch`）**：组 (a) 11/11、组 (b) 6/6、组 (c) 4/4；
`ths-ai-tests.el` 全文件 35 例中 34 预期通过，唯一失败为 pre-existing 基线红
`ths-fixture-charts-and-book-have-consistent-bounds`。布局回归 `tests/ths-tests.el` + `tests/ths-layout-tests.el`
的 4 个 `ths-layout-*` 用例全绿（含 `...-uses-extra-height-for-chart-and-aligns-panel-bottoms` 与
`...-fits-window-height-with-long-lists-and-full-trades`）。11 文件全量离线套件 144 例 → 141 通过，
3 例失败全部是 pre-existing 基线红（见 tech-debt）。`ths.el` / `ths-ai.el` 字节编译严格 0 警告、checkdoc 0 警告
（`ths.el` 原有 3 条 checkdoc 警告一并清除，仅改 docstring）。冒烟（batch 内 mock 传输层）：`A` → `ths-ai-analyze`、
面板出现评级词、`*THS 分析*` 含免责声明、`q` 关闭后看板宽度恢复、`ths--stop` 清空 AI 状态。

**验证快照（2026-10-22，T7 完成，`emacs -Q --batch`；BOOT 把 `~/.local/straight/build-31.1` 全部子目录追加进
`load-path` 后再把仓库根提到最前）**：

- 全量离线 ERT（11 文件，`-l` 顺序与「验证标准」逐字一致）：`Ran 144 tests, 141 results as expected, 3 unexpected`
  （9.65 s；进程退出码 1 仅由基线红引起）。**skipped = 0**：日志含 144 条逐例进度行且无任何 `skipped` 行；
  两个 `skip-unless` 只在 `tests/ths-data-tests.el`（`executable-find curl`），实测 `/usr/sbin/curl` 存在，故不跳过。
- 3 个 unexpected 与已知基线红逐字一致，无第 4 个：`ths-fixture-charts-and-book-have-consistent-bounds`（定义在
  `tests/ths-tests.el`）、`ths-volume-dashboard-shows-both-panels-without-growing-page`、
  `ths-volume-terminal-charts-preserve-height-and-column-width`（后两者定义在 `tests/ths-volume-tests.el`）。
- 逐文件用例数基线（`ert-deftest` 数 / 实际 passed）：`ths-data-tests` 21/21、`ths-otc-tests` 8/8、
  `ths-ranking-tests` 29/29、`ths-fund-ranking-tests` 10/10、`ths-search-tests` 10/10、`ths-trades-tests` 7/7、
  `ths-volume-tests` 11/9（2 红）、`ths-watchlist-tests` 6/6、`ths-tests` 14/13（1 红）、`ths-layout-tests` 7/7、
  `ths-ai-tests` 21/21 —— 合计 144/141，与 ERT 汇总行互证。
- 窄窗/宽窗/side-window 专项（一次性 batch 脚本 `/tmp/ths-ai-layout-probe.el`，不写仓库、不联网，12 条断言全 OK、
  退出码 0）：`(160 . 40)` 行数 39（≤39）、`chart-region` 高度 21（>16）、`dashboard-body` 与 `detail-panel` 同为 35、
  `body(5+35)=trades(24+16)=40`；`(80 . 20)` 行数 19、detail 面板 `(78 . 16)` 且渲染「AI 分析」摘要；
  `(44 . 24)` 行数 23、detail 面板 `(42 . 20)` 且渲染「AI 分析」摘要；打开右侧 60 列 side window 后 refit `(100 . 40)`
  行数仍为 39、detail 摘要仍在，关闭窗口后无残留 job/buffer。
- L1：`check-parens` 覆盖 8 个根目录 `.el` + `tests/` **14 个** `.el`（共 22 个，全绿；`tests/` 实际为 14 个文件，
  比计划中的「12 个」多 `ths-gui-tests.el` 与 `ths-live-check.el`，纯文件级检查一并覆盖）；字节编译严格
  （`byte-compile-error-on-warn t`）对 8 个根目录文件 **0 警告**，测后 `rm -f *.elc` 无残留；checkdoc：
  `ths.el` / `ths-ai.el` **0 警告**，其余 6 条告警全部落在本次未改动的文件（`ths-chart.el:274`、
  `ths-data.el:274`、`ths-data.el:392`、`ths-search.el` / `ths-theme.el` / `ths-watchlist.el` 缺 `;;; Commentary:`），
  属既有问题、不属本次改动。
- 工作区：`git status --porcelain` 仅 ` M ths.el` 与 4 个 untracked（`docs/`、`openspec/`、`tests/ths-ai-tests.el`、
  `ths-ai.el`），本任务未新增任何仓库改动。

**事实修正（T3）**：计划里 T3 写的 `(require 'ths-tests)` 改为「`fboundp` 守卫 + 显式 `load`」，
原因：`tests/ths-tests.el` 没有 `(provide)`，`require` 会 file-missing；L2 全量运行时它已由 `-l` 加载，
守卫可保证「单独运行也不缺宏、全量运行不重复加载」。

**事实修正（T3 夹具）**：测试原按固定代码 `600519` 区分「个股 / 盘面」请求，但看板默认选中的是
fixture 第一只 `300033`（`ths-test-stocks` 顺序 + `ths--initial-state` 取 `(car ths-data-stocks)`），
正确实现下 300033 的提示词不会出现 600519。故 `ths-ai-test--json-for` 的判别改为个股提示词头部
「个股行情数据」，「签名变化重发」用例改为改动**当前选中**个股报价；断言本身未放宽。
用例 20 内联 lambda 的同类 `600519` 假设已在 T6 一并修掉（改为同一「个股行情数据」判别口径），断言仍要求面板出现「中性」。

**实现要点（T6）**：① 摘要行与 `AI 分析 A` 按钮共用 1 行，故 `ths--exchange-detail` 的 `chart-rows` 常数
`7`→`8`（`ths--fund-detail` 的 `7` 未动，场外基金不加摘要行），面板总高度与改动前逐行相等，
布局断言无需放宽；② 面板文本预算取 `(- width 14)`（面板 padding ch1×2 + 按钮 9 列 + item-gap 1 列），
窄窗 `(width = columns-2, columns ≥ 44)` 下仍 ≥ 28 列，不会为负；③ 新增的 `ths-ai--panel-line`
除四态分派外还校验缓存分析的 `:signature` 代码，避免切换个股后误显上一只的评级。

**实现要点（T5）**：① `gptel-request` 不在 gptel 的 autoload 里，可用性判定先探 `fboundp` 再按需
`require`，避免加载 gptel 覆盖调用方的桩；② `select-window` 会让报告 buffer 成为 current buffer，
故 `ths-ai-analyze` 的每一步都用 `with-current-buffer` 回到看板，否则盘面分析会读到空数据并触发
`etaf-reactive-error`；③ HTTP 通道失败串一律用固定中文文案，不含 `error-message-string`（可能回显 URL）。

### 审查修复记录（第 2 轮）

来源：第 2 轮审查（编排层 refit 失效、gptel 代际与超时、market 签名、报告装配、校验口径、失败条目绑定标的）。
第 1 轮为安全修复（隐私匿名、HTTPS、注入净化、响应上限、cookie、url-debug），第 2 轮为编排与渲染修复。

- refit 失效：`ths-ai--refit-dashboard` 接受可选 buffer；`ths-ai--present` 先捕获 dashboard 再 `select-window`；`ths-ai-quit-report` 的同类 no-op 一并修复（报告 buffer 内 dashboard 为 nil）。
- gptel 代际与超时：新增 `ths-ai--generation`；过期回复不 remhash、不写状态；gptel 通道补 `run-at-time` 超时与真正 cancel。
- market 签名：追加 `:up`/`:down`/`:flat`/`:average-change`（均值保留一位小数）。
- 报告装配统一：删除 `ths-ai--snapshot-line`；`ths-ai--report` 成为唯一装配点，签名扩为 `(analysis &optional facts market errors)`；`ths-ai--report-text` 只挑缓存条目与错误块。
- 校验口径统一：`reasons` 只要求非空（提示词改为「3 条为佳，至少 1 条」）；`levels` 宽松校验，非法时丢弃该键。
- 失败条目绑定标的：entry 带 `:code`，`ths-ai--panel-line` 与 `ths-ai--current-entry` 统一做 stale 判定。
- 新增 7 个用例（列名 + 结果）。

**收尾一致性修复**：`ths--exchange-detail` 的摘要行配色原先只看 `(plist-get entry :analysis)` / `:error`，
切换到另一只股票后，上一只的失败条目仍让文本变 warning，而 `ths-ai--panel-line` 已按 stale 显示占位 —— 文本与配色不一致。
现取 `(ths-ai--current-entry 'stock stock)`（`:code` 与 `ths-data-id` 不符即视为无条目），文本与配色共用同一判定。
用例：`ths-ai-panel-color-matches-stale-entry`。

**本轮验证快照（`emacs -Q --batch` + BOOT，pure 语义）**：`tests/ths-ai-tests.el` 全文件
`Ran 48, 47 expected, 1 unexpected`（唯一红 = 基线 `ths-fixture-charts-and-book-have-consistent-bounds`）；
布局专项（`-l tests/ths-tests.el -l tests/ths-ranking-tests.el -l tests/ths-layout-tests.el`）`Ran 50, 49 expected, 1 unexpected`，
`ths-layout-tests.el` 的 7 例全绿，唯一红仍是同一条基线；L1：`ths.el` / `ths-ai.el` 严格字节编译（`byte-compile-error-on-warn t`）
0 警告、checkdoc 0 警告、`check-parens` OK，测后无 `.elc` 残留。

### 计划审查记录

| 轮次 | 结论 | 主要修订 |
|---|---|---|
| 1 | 需修订 | T5 验收改为「缓存/传输层用例」并把 UI 集成用例下移 T6；finish 路径补 `ths--publish`；`ths-ai--parse` 增加 kind 参数与盘面校验；补「无后端立即失败」「in-flight 去重」；签名改用 `ths-data-change` 与末根 `:close`；摘要按宽度截断；报告 buffer 用 `inhibit-read-only` 写入；明确只改 ths.el:871；测试顶部 `(require 'ths-tests)`；补 `defgroup ths-ai` |
| 2 | 需求变更（用户） | 报告窗口改为右侧 side window（≈70 列、抢焦点、`q` 关闭并 refit）；T5/T6/T7/T8 验收同步；新增用例 21 |

## 目标

在 THS 看板中新增「AI 投机建议 + 大盘盘面分析」能力：

1. 选中个股时，把本地行情事实（报价 / 分时 / 日 K / 五档 / 成交记录）组装成提示词，经 AI 得到结构化结论（评级 + 置信度 + 理由 + 风险 + 关键观察位）。
2. 同时给出大盘盘面分析（三大指数、自选池涨跌家数与量能、当前个股相对大盘位置）。
3. 详情面板只展示 1 行摘要；完整报告写入独立 `*THS 分析*` org buffer（只读、含免责声明）。
4. 双通道接入：gptel（软依赖，优先）→ 内置 OpenAI 兼容 HTTP（`url-retrieve` 异步 POST，回退）。
5. 仅手动触发（`A` 键），带 TTL 缓存与数据签名去重，不随自动刷新消耗 token。

## 非目标

- 不新增数据源（资金流 / 龙虎榜 / 新闻 / 财务）
- 不做批量自选打分排序
- 不输出仓位比例、买卖指令、目标价
- 不做流式逐字渲染、不把分析结果持久化到磁盘

## 设计

### 模块边界

新增 `ths-ai.el`（唯一新模块），`ths.el` 只做最小集成。分层：

| 层 | 函数 | 性质 |
|---|---|---|
| 事实层 | `ths-ai--stock-facts`、`ths-ai--market-facts` | 纯函数，输入 stock plist / indices+stocks |
| 提示词层 | `ths-ai--system`、`ths-ai--prompt` | 纯函数，system 内写死 JSON 契约与免责约束 |
| 解析层 | `ths-ai--parse` | 纯函数，`(text kind)`，容错解析 + 按 kind 分别校验 |
| 渲染层 | `ths-ai--summary-line`、`ths-ai--report` | 纯函数，1 行摘要（可按宽度截断）/ org 报告 |
| 传输层 | `ths-ai-request`、`ths-ai--gptel-request`、`ths-ai--http-request` | 异步，统一契约 `CALLBACK(TEXT FAILURE)`，返回 cancel 函数 |
| 编排层 | `ths-ai-analyze`、`ths-ai--finish`、`ths-ai--cache-fresh-p`、`ths-ai--requests-table` | 缓存、签名去重、in-flight 去重、状态与报告 buffer |

编排层命名说明：计划初版的 `ths-ai--cached` / `ths-ai--pending` 为设计占位，实际实现已合并为
`ths-ai--cache-fresh-p`（缓存是否新鲜，`(entry kind)` 判定）与 `ths-ai--requests-table`（在途登记表，
替代 pending 概念，`remhash` 即取消登记）。

### 配置（defcustom）

    (defgroup ths-ai nil "AI analysis for the THS dashboard." :group 'ths)

| 变量 | 默认值 | 说明 |
|---|---|---|
| `ths-ai-provider` | `auto` | `auto` / `gptel` / `http` |
| `ths-ai-http-url` | `nil`（需显式配置） | OpenAI 兼容 `/chat/completions` 端点 |
| `ths-ai-http-model` | `nil` | 模型名 |
| `ths-ai-http-key-env` | `"OPENAI_API_KEY"` | 从该环境变量取密钥（优先） |
| `ths-ai-http-key-auth-source` | `nil` | 可选 `(host . user)`，回落 auth-source |
| `ths-ai-timeout` | `60` | 秒 |
| `ths-ai-cache-seconds` | `600` | 结果 TTL |
| `ths-ai-language` | `"中文"` | 输出语言 |

密钥纪律：不从文件读明文 key；不打印、不写入报告、不进入进程 argv。

### 输出契约

个股（kind = `stock`）：

    {"rating":"看多|偏多|中性|偏空|看空","confidence":0.0,"reasons":["…"],"risks":["…"],"levels":{"support":"…","resistance":"…"},"summary":"<=40 字"}

盘面（kind = `market`）：

    {"summary":"…","breadth":"…","highlights":["…"]}

`ths-ai--parse` 契约：签名 `(text kind)`。

1. 预处理：剥离 ```json 围栏 → 取首个 `{` 到末个 `}` 区间。
2. 解析：`json-parse-string`，`:object-type 'plist`、`:null-object nil`、`:false-object nil`。
3. 校验（kind = stock）：`rating` 属于五枚举；`confidence` 为 [0,1] 内 number；`reasons` 为非空 list；`risks` 为 list（可空）；`summary` 非空字符串。
4. 校验（kind = market）：`summary` 非空字符串；`highlights` 为 list（可空）；`breadth` 为字符串或 nil。
5. 任一不符返回 `(list nil ERROR)`；成功返回 `(list PLIST nil)`。
6. 失败降级：面板摘要位显示错误；报告 buffer 保留上次成功内容，不清空。

### 状态机（必须全部覆盖，T3 有对应用例）

| 状态 | 表现 |
|---|---|
| 未配置后端 | `auto` 且 gptel 不可用且 `ths-ai-http-url` 为 nil → 立即回调错误「未配置 AI 后端：请安装并配置 gptel，或设置 ths-ai-http-url」，不发起请求、不进入 pending |
| 请求中（in-flight） | `ths-ai--requests` 已有该 key → 直接返回，不重复请求；`C-u A` 先 cancel 旧的再发起 |
| 成功 | 存 `ths-ai--results`，记 `:generated-at` 与 `:signature`，`ths--publish` 重渲染，写报告 buffer |
| 失败 | 存 `:error`，保留上次 `:analysis` 与报告内容，`ths--publish` 让摘要位显示错误 |
| 缓存命中 | 签名未变且 `(float-time)` 与 `:generated-at` 差 < `ths-ai-cache-seconds` → 直接复用并刷新报告，不发请求 |
| 缓存过期 / 签名变化 | 重新请求 |

**重渲染不变量**：`ths-ai--finish` 必须在 `(buffer-live-p buffer)` 且 `(eq session ths--session)` 成立后，于 `with-current-buffer` 内存储结果并调用 `(ths--publish)`；否则 ETAF 不会重算摘要行。

### 缓存与去重

- buffer-local `ths-ai--results`、`ths-ai--requests`（hash-table，键 `'stock` / `'market`）。
- 签名（stock）：`(list :code :price (ths-data-change stock) :time :intraday-date :candle-close)`，其中 `:candle-close` 取 `(plist-get (car (last (plist-get stock :candles))) :close)`。
- 签名（market）：`(list :indices (mapcar 价格与涨跌幅) :count (length ths-data-stocks))`。
- 有意排除 `:book` / `:trades` / `:amount` / `:turnover`：盘口与成交每笔变动会击穿缓存，分析价值提升有限。
- `C-u A` 强制刷新。

### UI 集成（精确位置）

- `ths--exchange-detail`（ths.el:869 起）：在图表 node 之后、报价来源行之前插入 1 行摘要 + `AI 分析 A` 按钮（复用 `ths--button`）。摘要文本先 `(truncate-string-to-width SUMMARY (- width 14))` 截断，按钮用 `compact` 变体，保证窄窗不横向溢出。
- **只改 ths.el:871**（`ths--exchange-detail` 内 `chart-rows` 的常数 `7` → `8`）；**不得改 ths.el:785**（`ths--fund-detail` 的 `7`，场外基金不加摘要行）。
- `ths-mode-map`（ths.el:1182 起）：新增 `("A" . ths-ai-analyze)`；`ths--shortcut-hint` 不加按钮。
- `ths--stop`（ths.el:62）：取消 `ths-ai--requests` 全部在途请求，清 `ths-ai--results` 与 pending。
- `ths`（ths.el:1214 附近）：初始化 buffer-local `ths-ai--results`、`ths-ai--requests`。
- 报告 buffer：`*THS 分析*`，派生 `org-mode`，`read-only-mode`；写入用 `(let ((inhibit-read-only t)) (erase-buffer) (insert …))` 包裹，写完 `read-only-mode 1`（首载 `org-mode` 有一次性延迟，记录在代码注释中）。
- 弹出方式：右侧 side window，宽度取 `(min 70 (max 40 (/ (frame-width) 3)))`；调用形态为
  `(display-buffer-in-side-window BUF '((side . right) (slot . 0) (window-width . WIDTH) (window-parameters . ((no-delete-other-windows . t)))))`
  随后 `(select-window …)` 让焦点进入报告窗口。
- 关闭：报告 buffer 内 `(local-set-key (kbd "q") #'ths-ai-quit-report)`；`ths-ai-quit-report` 先 `quit-window`，再在 `ths-ai--dashboard-buffer` 内存活时回到看板 buffer 调用 `ths-refit`，使 ETAF 按恢复后的宽度重算布局。
  - `ths-ai--dashboard-buffer` **并非既有变量**，由 T6 在 `ths` 初始化时以 buffer-local 形式设置；`ths-ai-quit-report` 用它定位看板 buffer 并 refit。
- 打开 side window 后同样必须让看板 refit（看板宽度从 ≥136 缩到约 66，会退化到窄屏 section 模式），否则 ETAF 仍按旧 viewport 渲染。

## 任务

- [x] T1 初始化 OpenSpec 基础设施：`openspec/active/`、`openspec/completed/`、`openspec/decisions.md`、`openspec/tech-debt.md`（登记 README 引用 `make check` 但仓库无 Makefile 的债）。验收：目录与文件存在，tech-debt 含该条目。（依赖：无）
- [x] T2 写 `docs/adr/0001-ai-analysis-transport.md`：双通道传输与依赖策略，含背景 / 决策 / 备选 / 后果四节。验收：四节齐全，备选含「仅 gptel」「仅 HTTP」「纯本地规则」「curl」「:schema」及放弃原因。（依赖：T1）
- [x] T3 写 `tests/ths-ai-tests.el`（TDD 红阶段，已完成）。文件顶部：`(require 'ert)`、`(require 'ths-ai nil t)`、`(require 'ths-tests)`、`(setq ths-watchlist-file nil ths-auto-fetch nil)`，保证单文件运行也不缺宏。用例覆盖三组：
  (a) 纯函数：facts（个股 + 盘面）、prompt 含关键字段与免责约束、parse（合法 JSON / ```json 围栏 / 前后夹废话 / 非法 JSON / rating 越界 / kind=market 校验）、summary 截断、report 含免责；
  (b) 传输与状态：auto 分派三条路径（gptel 可用 / 不可用走 http / 都不可用报「未配置 AI 后端」）、in-flight 去重、TTL 命中不重发、签名变化重发、`C-u` 强制刷新；
  (c) 集成层 A（本阶段允许红）：直接调用 `ths-ai-analyze` 并 mock `ths-ai--http-request`，断言 `ths-ai--results` 被填充、`*THS 分析*` 含免责声明。
  验收：运行后失败，且失败原因为 `void-function` 或未实现断言，而非语法/加载错误。（依赖：T1）
- [x] T4 实现 `ths-ai.el` 的 defgroup/defcustom、事实层、提示词层、解析层、渲染层（`ths-ai--parse` 带 kind 参数）。验收：T3 组 (a) 全绿（已确认 11/11；T4 遗留的 3 处隐患——`ths-ai--candle-extreme` 的谓词调用、`ths-ai--summary-line` 的宽度兜底、`levels` 数值归一化——已在 T5 任务首步修复）。（依赖：T3）
- [x] T5 实现传输层与编排层：`ths-ai-request`（auto 分派 + 无后端立即失败）、`ths-ai--gptel-request`（`let` 绑定 `gptel-use-context`/`gptel-use-tools` 为 nil，传 `:system`/`:buffer`/`:context`）、`ths-ai--http-request`（`url-retrieve` 异步 POST，密钥取自 env 或 auth-source，超时用计时器取消）、缓存与签名、in-flight 去重、`ths-ai-analyze`（含 `C-u` 强制）、`ths-ai--finish`（含 `ths--publish`）、报告 buffer 渲染。验收：T3 组 (a)(b) 与集成层 A 全绿，全程无真实网络；`*THS 分析*` 以右侧 side window 出现（`(window-parameter window 'window-side)` 为 `right`），焦点位于报告窗口。（依赖：T4）
- [x] T6 `ths.el` 集成：`(require 'ths-ai)`、`ths--exchange-detail` 摘要行 + 按钮（宽度截断）、**仅** ths.el:871 常数 7→8、`ths-mode-map` 加 `A`、`ths--stop` 取消 AI 请求、`ths` 初始化 buffer-local 状态。验收：T3 组 (c) 全绿；`(key-binding (kbd "A"))` 为 `ths-ai-analyze`；`ths-test-press` 触发后 detail 面板出现摘要文本；`q` 关闭报告窗口后，看板窗口宽度恢复且 `A` 再次可用（`ths-ai-quit-report` 生效）。（依赖：T5）
- [x] T7 回归与布局：跑全量离线 ERT **并以「无新增 unexpected」为验收口径**——已知基线红为 3 个（均 pre-existing，见 tech-debt）：`ths-fixture-charts-and-book-have-consistent-bounds`、`ths-volume-dashboard-shows-both-panels-without-growing-page`、`ths-volume-terminal-charts-preserve-height-and-column-width`。另外断言：打开 side window 后看板退化布局仍满足 `count-lines ≤ height-1`；关闭后 `(160 . 40)` 下 chart 高度恢复 1:1 增长、面板底部对齐、`chart-height > 16`。验收：无新增 unexpected。（依赖：T6）
- [x] T8 文档：`README.md` 新增「AI 分析（可选）」章节 + `ths-ai-*` 配置表 + 免责声明 + `A` 键说明；新建 `CHANGELOG.md`。验收：README 配置表与 defcustom 名称一一对应；README 说明按 `A` 在右侧弹出分析窗口、`q` 关闭并恢复布局。（依赖：T6）
- [x] T9 终验：`check-parens` 覆盖全部 `.el`；字节编译严格（`byte-compile-error-on-warn`）；离线 ERT 全绿；checkdoc 对齐。验收：0 错误、0 警告。（依赖：T7, T8）

## 文档清单

| 文档 | 处理 |
|---|---|
| `README.md` | 新增「AI 分析（可选）」章节：双通道、配置表、`A` 键、免责声明、gptel 软依赖说明 |
| `CHANGELOG.md` | 新建（Keep a Changelog 中文），记录本次 Added |
| `openspec/decisions.md` | 记录 3 条决策（双通道、url-retrieve、不传 SCHEMA） |
| `openspec/tech-debt.md` | 登记「README 引用 make check 但仓库无 Makefile」 |
| `docs/adr/0001-ai-analysis-transport.md` | 传输与依赖策略 ADR |
| `preview/`、`LICENSE` | 不变 |

## 验证标准

L1：`elisp_check_parens` 覆盖 9 个 `.el`（7 个既有 + ths-ai.el + 新测试文件）；字节编译严格；checkdoc。

L2（离线 ERT，排除 GUI 与网络用例，完整可复制，含 BOOT 引导）：

    BOOT='(progn (package-initialize) (let ((dirs (directory-files "/home/thomas/thomas-emacs/.local/straight/build-31.1" t "\\`[^.]"))) (dolist (d dirs) (when (file-directory-p d) (add-to-list (quote load-path) d t)))) (setq load-path (cons (expand-file-name ".") (delete (expand-file-name ".") load-path))))'
    emacs -Q --batch -L . --eval "$BOOT" \
      -l tests/ths-data-tests.el -l tests/ths-otc-tests.el \
      -l tests/ths-ranking-tests.el -l tests/ths-fund-ranking-tests.el \
      -l tests/ths-search-tests.el -l tests/ths-trades-tests.el \
      -l tests/ths-volume-tests.el -l tests/ths-watchlist-tests.el \
      -l tests/ths-tests.el -l tests/ths-layout-tests.el -l tests/ths-ai-tests.el \
      -f ert-run-tests-batch-and-exit

BOOT 的作用：先 `package-initialize`，再把 straight 构建目录的全部子目录追加进 `load-path`（否则 `-Q`
下找不到 etaf），最后把仓库根提到 `load-path` 最前，确保加载的是当前检出源码。

说明：`tests/` 实际 14 个文件，其中 `ths-gui-tests.el`（需图形）与 `ths-live-check.el`（需网络）不在 L2 范围，
故 L2 只加载上列 11 个；BOOT 中的 `~/.local/straight/build-31.1` 需按本机实际路径替换（Emacs 版本号随安装不同）。

要求：无新增 unexpected（已知基线失败用例 3 个，均 pre-existing：`ths-fixture-charts-and-book-have-consistent-bounds`、`ths-volume-dashboard-shows-both-panels-without-growing-page`、`ths-volume-terminal-charts-preserve-height-and-column-width`）。加载顺序不可调换：`ths-tests.el` 定义 `ths-test-with-dashboard` 等宏，`ths-ranking-tests.el` 定义布局测试所需的 `ths-rank-test-data`，`ths-ai-tests.el` 必须最后。`tests/ths-gui-tests.el`（需图形）与 `tests/ths-live-check.el`（需网络）不在 L2 范围。

L3（可选，需网络与凭据）：`tests/ths-ai-live-check.el` 真实通道冒烟，可后置到后续计划。

## 注意事项

1. 布局最脆：新增摘要行后必须跑 `tests/ths-layout-tests.el`；窄窗断言失败时优先缩短摘要文本与按钮标签，不要删布局断言。
2. gptel 为软依赖：`(require 'gptel nil t)`，不得写入 `Package-Requires`；测试里 mock `gptel-request` 时需同时把 `ths-ai-provider` 设为 `gptel`。
3. 密钥只从环境变量或 auth-source 取；日志、报告、回显均不得出现 key。
4. 异步回调必须校验 buffer 存活与 session，并在 `with-current-buffer` 内 `ths--publish`。
5. 不要为跑测试新增 Makefile（已登记技术债，另议）。
6. 测试隔离：`(setq ths-watchlist-file nil)`、`ths-auto-fetch nil`，禁止真实网络（mock 传输层）。
7. `*THS 分析*` 写入必须用 `inhibit-read-only` 包裹；不要在 `ths--stop` 里 kill 报告 buffer（用户可能仍要阅读）。
8. side window 使用 `no-delete-other-windows` 与固定 `slot`，避免被 ETAF 重渲染时的窗口逻辑挤掉。
9. 打开/关闭报告窗口后必须显式 refit 看板（side window 改变 viewport，ETAF 不会自动重算列数）。
10. 报告 buffer 关闭时**不要** kill buffer（用户可能再次查看），只关窗口。
11. 计划内的 `ths.el:NNN` 行号为编写时的快照；实际实现后 `ths--exchange-detail` 起于 875 行、`chart-rows` 常数在 880 行。后续改动请以「函数名 + 唯一常数」锚定，不要依赖行号。

## 验证快照（T9，2026-10-22，`emacs -Q --batch`）

- **全量 ERT**（11 文件，命令与「验证标准」L2 逐字一致，BOOT 同上）：`Ran 144 tests, 141 results as expected,
  3 unexpected`（10.46 s；进程退出码 1 仅由基线红引起）。3 个 unexpected 与既有基线红逐字一致，**无第 4 个**：
  `ths-fixture-charts-and-book-have-consistent-bounds`、`ths-volume-dashboard-shows-both-panels-without-growing-page`、
  `ths-volume-terminal-charts-preserve-height-and-column-width`；日志无 `skipped` 行（skipped = 0）。
- **L1**：`check-parens` 覆盖 8 个根目录 `.el` + `tests/` **14 个** `.el`（共 22 个，全 OK）；字节编译严格
  （`byte-compile-error-on-warn t`）对 8 个根目录文件 **0 警告**，测后 `rm -f *.elc` 无残留；checkdoc：
  `ths.el` / `ths-ai.el` **0 警告**，其余 6 条告警全部落在本次未改动的文件（`ths-chart.el:274`、`ths-data.el:274`、
  `ths-data.el:392`、`ths-search.el` / `ths-theme.el` / `ths-watchlist.el` 缺 `;;; Commentary:`），属既有问题。
- **文档一致性**：README 的 8 行配置表与 `ths-ai.el` 的 8 个 defcustom 名称 + 默认值逐条一致（`auto` / `nil` /
  `nil` / `"OPENAI_API_KEY"` / `nil` / `60` / `600` / `"中文"`）；`("A" . ths-ai-analyze)` 已在 `ths-mode-map`
  （ths.el:1213），README 键位表与正文均有 `A` 键说明；CHANGELOG 的 4 条 Added 与代码事实一致（缓存 600 秒、
  `C-u A` 强制刷新经 `(interactive "P")` + `ths-ai-analyze(FORCE)` 实现并取消在途请求、8 个选项名称、双通道后端）。
- **密钥卫生**：`grep -rn "sk-\|Bearer [A-Za-z0-9]"` 无真实密钥命中（仅 `:ask-volume` / 「卖盘挂单」的 `sk-`
  子串误报）；`Bearer` 只在 ths-ai.el:658 的 `(concat "Bearer " key)` 拼接处出现，无字面量密钥；
  `ths-ai-http-key-env` 默认值是环境变量名 `"OPENAI_API_KEY"`、`ths-ai-http-key-auth-source` 默认 `nil`，
  两者都不含真实密钥值。
- **工作区**：` M README.md`、` M ths.el` 与 5 个 untracked（`CHANGELOG.md`、`docs/`、`openspec/`、
  `tests/ths-ai-tests.el`、`ths-ai.el`）；T9 未改动任何 `.el` 源码与测试文件。

## 安全复审修复（R1–R7，2026-10-22）

第二轮安全复审的 3 条必修 + 4 处措辞 + 1 条顺手项，全部落在 `ths-ai.el` 与其测试：

| # | 修复项 | 落点（函数） | 对应测试 |
|---|---|---|---|
| R1 | 行内 org 链接中和 + 拒绝自动重定向 | `ths-ai--neutralise-links`（新增，先于行首转义执行）、`ths-ai--sanitise`、`ths-ai--redirect-refused-p`（新增）、`ths-ai--http-request`（`url-max-redirections` 绑 0） | `report-neutralises-org-directives`（改）、`report-neutralises-inline-links`（新） |
| R2 | 身份键统一为 `ths-data-id` | `ths-ai--current-entry`、`ths-ai--panel-line`、`ths-ai--signature`、`ths-ai--finish`（参数 `id`，条目键 `:id`） | `identity-distinguishes-market-prefixed-symbols`（新）、3 个既有 stale 用例同步改 `:id` |
| R3 | 自选池 < 3 只时聚合退化 | `ths-ai--market-facts`（`:total-amount`/`:strongest`/`:weakest` 置 nil） | `market-facts-trim-single-symbol-pool`（新） |
| R4/R5 | 措辞与字节口径 | `ths-ai--present` 注释、`ths-ai--http-body`（`position-bytes` 差值） | `http-body-rejects-oversized-response`（既有，口径不变） |
| R6/R7 | 控制字符与字段净化全覆盖 | `ths-ai--clean-key`（`[[:cntrl:]]`）、`ths-ai--format-value`（字符串走 `ths-ai--field`） | `prompt-folds-newlines-in-identifying-fields`（新） |

兼容性：读条目时只有 `:code` 而无 `:id` 的旧内存条目一律视为 stale（返回 nil），不做迁移。

## 安全终审修复（R1-① 收敛 + 净化出口兜底 + 2 条防护 ERT，2026-10-22）

第三轮安全终审的阻断项与两条加固建议，全部落在 `ths-ai.el` / `tests/ths-ai-tests.el`：

| # | 问题 | 修复落点 | 对应测试 |
|---|---|---|---|
| R1-① | `ths-ai--neutralise-links` 单次替换**不收敛**：`[[[` → `[ [[` 重新造出 `[[`，3/5/7 连括号后仍残留可解析的 `elisp:` / `shell:` / `file:` 链接 | `ths-ai--neutralise-links` 改为「有 `[[` 就再替换」的循环，直到不动点；每轮缩短文本故必然终止，无 `[[` 的输入原样返回（幂等） | `report-handles-many-brackets`（新，覆盖 2/3/5/7 连括号） |
| 加固 1 | 报告里只有模型字段过 `ths-ai--sanitise`，快照/异常两段是裸插入 | `ths-ai--snapshot-section`（`:code` / `:name` / `:time` / `:intraday-date` 逐字段净化）、`ths-ai--error-section`（失败文案净化） | `report-neutralises-org-directives`、`report-handles-many-brackets` |
| 加固 1 | 缺少统一出口兜底 | 新增 `ths-ai--report-finalise`，`ths-ai--report` 在 string-join 之后整体再过一次链接净化 | 同上（语义断言 0 link） |
| 加固 2 | 密钥控制字符只覆盖 0–31 | `ths-ai--clean-key` 改用显式 `[\0-\x1f\x7f]`——Emacs 的 `[[:cntrl:]]` **不含 DEL**，裸 DEL 同样能提前结束 header 行 | `clean-key-rejects-control-characters`（新） |
| 加固 2 | 重定向谓词对 `url-http` 的裸符号形态会 `memq` 到非 list 而报错 | `ths-ai--redirect-refused-p` 同时接受裸符号与「list 内含符号」两种形态 | `redirect-refusal-detects-both-status-shapes`（新） |

出口兜底为什么只重跑链接净化、不重跑行首转义：`#+TITLE:` / `#+DATE:` 是报告自己的关键字，整段过
`ths-ai--sanitise` 会把它们转义掉、报告失去标题。行首转义仍由数据入口的 `ths-ai--sanitise` 负责（快照与异常
两段现已纳入），出口只保证「无论如何都不留可激活的 `[[`」。

测试断言口径：两个既有报告用例与新增用例的核心断言从「字符串不含 `[[`」改为**语义断言**——把报告插入
临时 buffer、开 `org-mode`、`org-element-parse-buffer` 后 link 元素类型列表必须为空；关键字注入则断言
`keyword` 元素里不得出现 `SETUPFILE` / `STARTUP`。

文档：README 的 `url-debug` 措辞改为「请求期间会关闭 `http` 类 URL 调试输出（当 `url-debug` 为 `t` 或整数时
等于全部关闭）」——与 `ths-ai--http-request` 里 `(if (listp url-debug) (delq 'http url-debug) nil)` 的实际行为对齐。

**验证**（`emacs -Q --batch`，BOOT 同 L2）：

- `-l tests/ths-ai-tests.el`：`Ran 55, 54 results as expected, 1 unexpected`（唯一红 = 基线
  `ths-fixture-charts-and-book-have-consistent-bounds`）。
- 布局专项（`-l tests/ths-tests.el -l tests/ths-ranking-tests.el -l tests/ths-layout-tests.el`）：
  `Ran 50, 49 results as expected, 1 unexpected`（layout 用例全绿）。
- 11 文件全量：`Ran 164, 161 results as expected, 3 unexpected`，3 红与既有基线逐字一致。
- 幂等实测：`report == finalise(report)` → t；`finalise` 再套一次 → t；`neutralise-links` 再套 → t；
  `sanitise` 再套 → t（8 连括号输入 `[[[[[[[[file:/x]]` 经两次净化完全相同）。
- L1：`ths-ai.el` 严格字节编译（`byte-compile-error-on-warn t`）0 警告、`checkdoc-file` 0 警告、
  `check-parens` OK，测后 `.elc` 已删除（0 个残留）。

**遗留（未修，需决策）**：org 除 bracket link 外还认**纯文本 link**——`file:/etc/passwd`、`shell:rm -rf ~`
即使括号被拆开仍是 `:format 'plain'` 的 link（实测 `("file" plain "file:/etc/passwd")`、
`("shell" plain "shell:rm")`）。括号中和只能拆掉 bracket link；要让报告里「0 个任意形态 link」，必须改写
正文（如 `file:` → `file :`），那会改变模型输出原文，属产品决策，本轮未做。因此新增语义断言只收集
`:format 'bracket' 的 link，与文本断言「全文无 `[[`」共同构成验收口径。

> 该遗留项已在下一节（安全加固（危险 scheme），2026-10-23）关闭：产品决策为「改写」，断言口径升级为
> 「解析出 0 个危险 scheme 的 link（bracket 与 plain 都算）」。

## 安全加固（危险 scheme，2026-10-23）

**事实（实测 `emacs -Q --batch` + `org-element-parse-buffer`）**：括号中和收敛到不动点后，报告里仍存在可跟随
链接——Org 除 bracket link 外还认 **plain link**，`file:/etc/passwd` / `shell:rm -rf ~` 即使没有括号、或括号
被拆成 `[ [ [file:...`，仍被解析为 `:format 'plain'` 的 link。实测样例：`"[ [ [file:/etc/passwd]]"` →
`(("file" plain "file:/etc/passwd"))`；`"详见file:/etc/passwd"`（前面直接跟中日韩字符）同样是 link。
另实测边界：`"SETUPFILE: /etc/passwd"`、`"profile:abc"`、`"Afile:/x"`、`"9file:/x"` **不是** link，而
`"_file:/x"`、`"-file:/x"`、`".file:/x"`、`"：file:/x"` 是 link——即 scheme 紧邻 ASCII 字母/数字时不构成
plain link，紧邻其它字符（下划线、标点、中日韩文字）时构成。

**两层防护**（两层都必需，任一层单独都不够）：

| 层 | 落点 | 作用 |
|---|---|---|
| ① 改写正文 | `ths-ai--neutralise-schemes`（新增，名单在 `ths-ai--dangerous-schemes`）、由 `ths-ai--sanitise` 与 `ths-ai--report-finalise` 在链接中和**之后**调用 | 危险 scheme 与其冒号之间插入一个空格（`shell:rm` → `shell :rm`），文本仍可读但不再匹配 Org 的 `scheme:` 形态；`https` / `http` 不在名单内故网页引用保持可点击；大小写不敏感并保留原大小写；紧邻 ASCII 字母/数字时跳过（避免把 `SETUPFILE:` 写成 `SETUPFILE :`） |
| ② 禁止确认 | `ths-ai--present` 的 `with-current-buffer` 内、`org-mode` 之后：`org-confirm-elisp-link-function` / `org-confirm-shell-link-function` 均设为 `(lambda (&rest _) nil)`（返回 nil = 拒绝执行） | 万一有链接漏过第 ① 层，报告 buffer 里也无法确认执行；文件顶部为这两个变量加了 `defvar` 声明避免编译警告 |

**测试口径升级**：核心断言从「字符串不含 `[[`」（文本级）改为「解析出 0 个危险 scheme 的 link」（语义级），
bracket 与 plain 两类形态都算。新辅助函数 `ths-ai-test--dangerous-links` 收集 `:type` 落在危险名单内的 link
（返回 `(TYPE RAW-LINK)` 便于失败定位），`ths-ai-test--link-types` 收集全部 link 类型用于确认 `https` 仍可用。
`report-neutralises-inline-links`、`report-handles-many-brackets`、`report-neutralises-org-directives` 三个既有
用例改用同一口径，新增 `report-neutralises-dangerous-schemes` 覆盖 `:reasons` / `:risks` / `:summary` 三个字段
与「7 连括号 + python:payload」「裸 plain：`详见 file:/etc/shadow 与 shell:curl evil.sh`」，并断言 `涨幅 3.2%`
这类中文与数字未被破坏、`[[https://example.com]]` 与裸 `https://example.com` 各解析出 1 个 https link。

**验证快照（2026-10-23，`emacs -Q --batch` + BOOT 同 L2）**：

- `-l tests/ths-ai-tests.el`：`Ran 56, 55 results as expected, 1 unexpected`（唯一红 = 基线
  `ths-fixture-charts-and-book-have-consistent-bounds`）。
- 11 文件全量：`Ran 165, 162 results as expected, 3 unexpected`，3 红与既有基线逐字一致。
- 布局专项：`Ran 50, 49 results as expected, 1 unexpected`（layout 7 例全绿）。
- 幂等：`report == finalise(report)` → t；`finalise` 再套 → t；`neutralise-schemes` 连做两次输出完全相同。
- L1：`ths-ai.el` 严格字节编译（`byte-compile-error-on-warn t`）0 警告、`checkdoc-file` 0 警告、
  `check-parens` OK（`ths-ai.el` 与 `tests/ths-ai-tests.el` 均 OK），测后 `.elc` 已删除。

文档：README「AI 分析（可选）」新增「报告安全」一段，说明危险链接被改写、报告 buffer 内禁用两类链接的确认
执行、`https` 保持可用。


