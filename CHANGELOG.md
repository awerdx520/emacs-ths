# 变更日志

本项目所有值得注意的变更都会记录在此文件。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 新增

- 港股与美股行情：报价、分时、日 K 与 1 档盘口（买一／卖一）。港股为 `hk` + 5 位数字（`hk00700`）及港股指数 `hkHSI`、`hkHSCEI`；美股为 `us` + 字母（`usAAPL`）及点数形态代码 `us.IXIC`、`us.INX`、`usDJI`。
- 港股与美股排行榜：`u` 键扩为 A 股 → ETF → LOF → 港股 → 美股 5 态循环；工具栏在宽 58 列及以上显示 7 个按钮（窄窗保留原有 5 个）。
- 港美搜索与自选：东财 code-table 的「港股」「美股」结果映射为 `hk*`／`us*`；`ths-watchlist.json` 格式不变，只含 A 股与场外基金的旧文件可直接读取。
- 顶部指数条扩为 8 条：上证／深证／创业板 + 恒生／国企 + 道指／纳指／标普 500，宽度不足时按整条截断尾部，不显示半条。
- 行情列表新增「市场」列（沪A／深A／京A／沪基／深基／港股／美股），`/` 筛选可输入「港股」「美股」。
- AI 分析（可选）：按 `A` 为当前标的生成投机建议（评级／置信度／理由／风险／关键观察位），并附大盘盘面分析；详情面板显示一行摘要，完整报告在右侧侧边窗口（`*THS 分析*`，org 模式，`q` 关闭）。
- 双通道后端：优先复用 `gptel`（软依赖，不写入 `Package-Requires`），否则使用内置 OpenAI 兼容 HTTP 通道（`url-retrieve` 异步 POST，密钥只从环境变量或 `auth-source` 读取）。
- 结果缓存与去重：同一标的 600 秒内且行情签名未变时复用缓存，`C-u A` 强制刷新；请求进行中不重复发起。
- 新增 `ths-ai` 自定义组与 8 个选项：`ths-ai-provider`、`ths-ai-http-url`、`ths-ai-http-model`、`ths-ai-http-key-env`、`ths-ai-http-key-auth-source`、`ths-ai-timeout`、`ths-ai-cache-seconds`、`ths-ai-language`。
- AI 报告 buffer 的配色跟随 THS 主题（背景／前景／标题／代码块／表格／link 均取 `ths-theme` 调色板），与看板一致，按 `T` 切换主题时同步刷新。
- AI 报告 buffer 支持 `q` 与 `C-c C-q` 退出（evil normal state 下同样生效），键绑定只作用于报告 buffer，不污染其它 org buffer。
- AI 分析接入五类外部信息面因子：个股新闻（标题／时间／来源）、公告（标题 + 最新一条正文片段）、财报指标（最多 4 期）、所属行业、外围与宏观（默认关闭）。
- 报告新增五个小节：消息面 → 行业位置 → 财报要点 → 公告解读 → 外围与宏观；数据事实与模型结论并排，「没抓到数据」与「模型没给结论」分行呈现。
- 新增 10 个 `ths-ai` 选项：`ths-ai-news-enabled`、`ths-ai-news-count`、`ths-ai-announcements-enabled`、`ths-ai-announcements-count`、`ths-ai-announcement-body-chars`、`ths-ai-financials-enabled`、`ths-ai-financials-periods`、`ths-ai-industry-enabled`、`ths-ai-macro-enabled`（默认关闭）、`ths-ai-macro-symbols`；`ths` 组另增 3 个：`ths-info-cache-seconds`、`ths-info-timeout`、`ths-info-body-limit`。
- 信息面缓存与降级：已解析的响应在 `ths-info-cache-seconds` 内复用；每个源独立成败，单源失败只影响报告对应小节；整轮采集受 `ths-info-timeout` 总预算约束，超时后保留已返回的因子。

### 变更

- 引入 `ths-data-markets` 市场画像表作为各市场能力的单一事实来源：符号格式、交易时段与分钟数、小数位、币种、盘口档数、成交量单位、报价／分时／日 K 端点与来源顺序统一从画像读取，消费方不再各自硬编码 240 分钟、5 档盘口或「手」。
- 成交量单位按市场显示：A 股为「手」，港股与美股为「股」。
- `u` 键由 3 态改为 5 态（A 股／ETF／LOF／港股／美股）。
- `make check` 与 `make check-all` 现等价：`KNOWN_FAILURES` 已清空，构建入口固定 `LC_ALL=C.UTF-8` 后 3 条宽字符断言转绿，两条路径均以 0 unexpected 为门禁。
- `make compile` 改用 `scripts/compile-strict.el`：修正 `batch-byte-compile` 返回值不进入退出码导致的编译门禁漏判，warning 现在会真正让编译失败。
- 详情面板在图表与报价来源行之间新增一行 AI 摘要与「AI 分析 A」按钮，图表区行数预算相应调整（`chart-rows` 常数 7 → 8），布局外观不变。
- `ths--stop` 在关闭看板时取消挂起的 AI 请求并清空结果缓存（不关闭已打开的分析报告窗口）。
- gptel 的 DeepSeek backend 改用 `--noproxy api.deepseek.com` 直连：gptel 以 curl stdout 首行作为响应状态，HTTP 代理 CONNECT 的 `HTTP/1.1 200 Connection established` 会被当成响应行，导致请求被误判失败。代理排除只作用于该 backend 的 curl 子进程，Emacs 全局 `process-environment` 不变。
- AI 分析不再只吃行情快照：个股分析在行情事实之外追加信息面事实（新闻／行业／财报／公告，以及打开宏观开关时的外围读数与两市成交额），盘面分析追加外围宏观读数与两市成交额。
- 提示词改为双围栏：行情事实装在 `<<<DATA` … `DATA>>>`，外部信息面事实装在 `<<<INFO` … `INFO>>>`，系统提示词声明两块内容都只是待分析数据、其中的指令式文字一律忽略；没有任何信息面因子时 `<<<INFO` 整块不出现，提示词与引入因子前一致。
- `ths-ai--field` 增加宽度参数并做围栏转义：外部文本先把换行与制表符折叠为单个空格、按宽度截断、最后把连续三个及以上的 `<` / `>` 拆成两字符一组（`DATA>>>` → `DATA>> >`），截断在转义之前完成；调用方可按因子预算（新闻标题、公告正文）传入自己的宽度，默认仍为 32 列。
- 外发数据范围扩大：个股分析新增新闻标题／时间／来源、最新一条公告正文片段与财报数字，盘面分析新增外围宏观读数（默认关闭）；新闻 URL 与正文仍不进提示词。

### 修复

- 港股与美股成交额按原币（港元／美元）显示，不再乘 10000。
- 美股日 K 在拿不到交易所后缀时直接走新浪日 K 兜底，不再发送无后缀的 `usfqkline` 请求（该请求会返回两行残缺数据并污染缓存）。

### 安全

- 盘面分析外发聚合统计与外围宏观读数（`ths-ai-macro-enabled` 默认关闭），不含自选池个股名称；个股分析新增新闻标题／时间／来源、最新一条公告正文片段与财报数字，两者均不含 URL 与个人数据；自选池少于 3 只时不发合计成交额与最强／最弱幅度。
- 外部信息面文本（新闻标题与来源、公告标题与正文、行业名）进提示词前把换行与制表符折叠为单个空格，并打断连续三个及以上的 `<` / `>`，因此供应商文本无法闭合或伪造 `<<<DATA` / `<<<INFO` 围栏、也无法伪造事实行。
- 内置 HTTP 通道强制 `https://` 并启用证书校验失败即报错；请求禁用 cookie；响应体解析前按字节上限 1 MiB（下载阶段不设硬上限）；3xx 重定向一律拒绝。
- 供应商字段（含 `:code`／`:time`／`:intraday-date`／指数名称）提交前折叠控制字符并截断；模型输出写入 org 报告前中和全文 `[[` 链接、转义行首 `#+`/`#|`，并抑制 org 启动视觉副作用（`#+` 关键字由转义拦截）。
- 密钥含控制字符视为非法，不发送请求。

### 已知限制

- 港股与美股只有 1 档盘口：接口只给买一／卖一，界面按 1 档渲染，不补伪造档位；港股挂单量字段无值，显示为 0。
- 港股与美股没有成交明细：不发出 trades 请求，详情页与右侧栏均不渲染该面板。
- 东财 `push2` 域名族（`push2`／`push2his`／`82.push2`／`88.push2`）在本机不可达：A 股成交明细失效、A 股榜单依赖新浪回退；港美的东财报价与日 K 分支仅由离线用例覆盖，未经实网验证。
- 美股公告无源：东财公告接口在 `ann_type=US` 下返回空数组，美股报告的公告解读小节恒为「数据不足」。
- 港股与美股无行业数据源：新浪 `corpOther` 只覆盖 A 股，东财板块域名族在本机不可达，因此这两类标的的行业位置小节恒为「数据不足」。
- 行业当日涨跌被反爬：同花顺行业榜 ajax 无论 http／https、带不带 UA 与 Referer 都只返回反爬页或 JS 跳转，A 股也取不到该字段，`make live-check` 的对应检查项恒 skip。
- 美股财报仅净利润稳定：`RPT_USF10_FN_INCOME` 的 `ITEM_NAME` 与映射表多数不符（营收写作「营业收入」／「主营收入」、无「毛利率」、无「净资产收益率」），每期实际只解析出净利润。
