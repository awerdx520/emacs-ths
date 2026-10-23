# ADR 0002：AI 分析的外部信息源与模块边界

- 状态：已接受（2026-10-23）
- 决策者：项目维护者 + Plan Agent
- 相关计划：`openspec/active/2026-10-23-ths-ai-info-factors.md`

## 背景

现有 AI 分析（`ths-ai.el`，见 ADR 0001）的输入只有本地行情快照：报价、分时、日 K、五档盘口、成交记录、指数。据此产出的结论本质是**技术性观察**（趋势、位置、量能、风险位），既不含信息面（新闻、公告）也不含基本面（财报、行业定位），更没有宏观与外围市场的参照。

用户要求在同一套分析里补齐这几个维度：**新闻、公告（含解读）、财报、所属行业**，并把**宏观 / 外围因子**做成可选开关。

2026-10-23 对候选源做了两轮真实探测（非文档推断），可用性差异极大：

| 能力 | 实测可用端点 | 关键约束 |
|---|---|---|
| 个股新闻 | 东财 `search-api-web.eastmoney.com/search/jsonp` | JSONP 需剥壳；A 股 600519 / 港股 00700（hits 953）/ 美股 AAPL（hits 108）三市场均可用 |
| 公告列表 / 正文 | 东财 `np-anotice-stock.eastmoney.com` + `np-cnotice-stock.eastmoney.com` | `ann_type` 取 `A`（1074 条）/ `H`（1506 条）可用，**`US` 返回空数组**；正文单页 5000 字封顶需翻页 |
| 财报 | 东财 `datacenter.eastmoney.com/api/data/v1/get` | A 股 `RPT_LICO_FN_CPD`、港股 `RPT_HKF10_FN_MAININDICATOR`、美股 `RPT_USF10_FN_INCOME` 三套 reportName 均可用，是**唯一**可用的财报源 |
| 行业 | 新浪 `vip.stock.finance.sina.com.cn` corpOtherInfo（所属行业）+ 同花顺行业列表 ajax（当日涨跌） | 新浪 corpOther **仅 A 股**；同花顺行业列表 51 行、粒度与「白酒」这一申万二级名**同粒度** |
| 宏观 / 外围 | 腾讯 `qt.gtimg.cn` 8 个指数；新浪 `hq.sinajs.cn` 汇率与 `DINIW`/`hf_*`/`int_*` | `hq.sinajs.cn` **必须带** `Referer: https://finance.sina.com.cn`，否则取不到数据 |
| 全市场涨跌家数 | 无 | 没有单端点提供，不实现 |

同时被证伪、不得作为备选的源：`datacenter-web.eastmoney.com` 与 `emweb.securities.eastmoney.com`（9 s 超时）、`push2` 族（连接层抛错）、财联社 3 路径、腾讯新闻 4 路径、雪球 quote（需 cookie）、新浪 `vFD_FinanceSummary`（47 KB JS 壳）、同花顺 `finance.html`（466 KB 壳）、美股新浪 JSONP 系列（`Service not valid`）。`hf_DINIW` / `hf_DX` / `fx_sdxy` 返回空串，也不可用。

## 决策

1. **由仓库自抓公开接口，不把检索交给模型。** 数据必须可缓存、可离线单测、结果可复现：模型侧联网在部分后端不可用（现有代码显式绑定 `gptel-use-tools=nil`），且「模型检索到了什么」无法断言，测试无从下手。自抓后每类源都能用固定响应夹具做 ERT，失败语义也由本项目定义。

2. **新增独立模块 `ths-info.el`，与行情层 `ths-data.el` 分离。** 两者生命周期不同：行情是秒级刷新 + 多 provider 回退链（`ths-data--providers`），信息面是分钟级缓存 + 单源降级；失败语义也不同（行情失败要回退到另一服务商，信息面失败只是把该因子置 nil）。混在一处会让 `ths-data.el` 继续膨胀（其行数已达 1402 行，`ths-ai.el` 达 1586 行），而信息面新增的五类抓取、编码/剥壳差异与缓存逻辑与行情毫无重叠。

3. **单源失败降级，不阻塞分析。** `ths-info-collect` 设硬超时（`ths-ai-info-timeout`，默认 8 秒）；任一类来源失败只写入 `ERRORS` 并把该因子置 nil，分析请求照常发出，报告对应小节写「数据不足」。若改成「任一源失败即整体失败」，网络稍差时 `A` 键形同失效——用户按一次没有任何反应，也无法知道是哪个源的问题。

4. **宏观 / 外围因子默认关闭（`ths-ai-macro-enabled` 默认 `nil`）。** 用户明确要求做成可选项。这类数据的时效与口径不一致（汇率、美元指数、原油、黄金、A50、恒指期货、隔夜美股分属不同市场与交易时段），默认开启会让每份报告都掺入与个股无关的噪音，且读数的时间戳与本地行情并不可比。

5. **财报唯一源是东财 `datacenter.eastmoney.com`。** A / 港 / 美三套 `reportName` 均实测可用，其它候选（`datacenter-web` / `emweb` / 新浪 `vFD_FinanceSummary`）全部超时或返回 JS 壳，没有第二选择。接受这一单点依赖，并要求后续任务在 `openspec/tech-debt.md` 登记：该域失效时三市场财报同时不可用，只能显示「数据不足」。

6. **提示词用双围栏 + `ths-ai--field`（含围栏标记转义），`ths-ai--sanitise` 只在渲染层。** 两层职责不同：`ths-ai--field` 负责控制字符折叠、宽度截断与围栏序列打断（`<<<INFO` → `<< <INFO`），防的是提示注入与围栏逃逸；`ths-ai--sanitise` 负责危险 org scheme 的中和，防的是报告可点击执行（见 2026-10-22 决策）。混用会破坏 JSON 契约里的正常文本——`sanitise` 会把正文里的 `:` 改写成 ` :`，模型据此拼出的 API 名、时间、指标名都会走样。

7. **信息数据加短 TTL 缓存（`ths-info-cache-seconds` 默认 120 秒）。** 缓存判定必须先算 `:info-digest`（新闻首条时间 + 条数、公告头两条 `art_code`、财报最新报告期与营收、行业当日涨跌幅），而 digest 依赖 info 数据，所以连按 `A` 时「先 collect 再判缓存」的顺序不可避免。120 秒的内存缓存让连续按 `A` 时 info 走缓存、不发网络请求，避免每次按键都把五类源重抓一遍。

## 备选方案

| 方案 | 放弃原因 |
|---|---|
| 交给模型联网检索（gptel tools / provider web search） | 不可复现、无法离线测试；部分后端不支持；现有代码显式绑定 `gptel-use-tools=nil`，启用需改既有传输契约 |
| 引入付费数据源 | 成本与账号依赖，违背项目「无需 API Key」的定位；且港美行业 / 公告本身在公开源里已部分可得 |
| 只做新闻不做财报 / 公告 | 用户明确要求财报与公告解读 |
| 复用 `ths-data--http` 作统一 HTTP 封装 | 其 `--referer` 按 provider 写死（`_` 分支固定带 `https://gu.qq.com/`），与「仅 `hq.sinajs.cn` 带新浪 Referer、其余不带」的**源级**策略冲突；且它没有 `--max-filesize`，无法给响应体设 2 MiB 上限 |
| 用 `url-retrieve`（与 AI HTTP 通道一致） | 信息源无需密钥，curl 子进程能直接用 `--fail` / `--max-time` / `--max-filesize` 与退出码判定失败，更贴合现有 `ths-data` 风格；`url-retrieve` 的错误路径需要另写一套解析 |

## 后果

- **新增网络依赖与失败面**：五类源任一失效，都会让报告对应小节显示「数据不足」。已用降级矩阵约束（单源失败 / 总超时 / 空数组 / 编码失败 / 超 2 MiB / 解析失败各有明确行为），但不改变「外部源的可用性不由本项目控制」这一事实。
- **外发数据范围扩大**：新闻标题/来源/时间、公告标题与正文片段、财报指标、行业名与涨跌幅、宏观读数将发送给所配置的模型。README 的「发送范围」与免责声明必须同步改写，否则文档与真实行为不符。
- **提示注入面扩大**：外部文本第一次进入提示词，靠双围栏标注 + 围栏序列转义 + `ths-ai--field` 宽度截断防护；模型仍可能被内容误导，报告措辞与免责声明需要覆盖这一点。
- **测试成本上升**：`tests/ths-info-tests.el` 需要五类真实响应夹具（东财 JSONP、公告 JSON、财报 JSON、GBK HTML、新浪/腾讯文本行），并覆盖降级与超时；live-check 增加真网依赖，不可达项按 skip 处理。
- **单点依赖**：东财 `datacenter.eastmoney.com` 失效则三市场财报同时不可用；同花顺行业列表失效则行业涨跌只有名称没有涨跌幅。本计划的后续任务需把这两条登记进技术债（`openspec/tech-debt.md` 当前尚无此条目）。
