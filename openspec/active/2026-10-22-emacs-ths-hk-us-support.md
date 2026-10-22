# emacs-ths 增加港股 / 美股支持

## 当前状态

- 阶段：Phase 3（Implement）· 进行中
- 已确认：方案 ✅（用户 2026-10-22 确认原方案含 4 项取舍 + 迁移与 11 项修订），计划 ✅（用户 2026-10-22 确认；plan-reviewer 两轮独立审查：第一轮 blocking 经实测证伪并转为加固、第二轮 blocking 已修复）
- 工件归属：本计划 2026-10-22 从 `~/thomas-emacs/openspec/active/` 迁入本仓库；thomas-emacs 侧只保留指针文件
- 安全点：分支 `feat/hk-us-support` + tag `pre-hkus-baseline`
- 进度：任务0 ✅（Makefile + 严格编译驱动 + ERT runner，基线 124 tests 绿）；任务1 ✅（画像表 + 符号规范化，129 tests 绿）；任务2 ✅（报价解析与 provider 路由，134 tests 绿）；任务3 ✅（分时与日 K：槽位画像化、端点按市场分派、港美取值路径与新浪日 K 兜底，141 tests 绿）；任务4 ✅（搜索港美映射与自选兼容，146 tests 绿）；locale 补强 ✅（Makefile 固定 `LC_ALL=C.UTF-8`，`make check` 结果与调用者 locale 无关，146 tests / 0 unexpected 绿）；任务5 ~ 任务8 待执行
- 下一步：任务5（排行榜：universe 扩 5 类、新浪港美榜单端点、东财港美节点跳过）

## 前置事实（实测 2026-10-22）

| 项 | 结论 |
|---|---|
| 仓库状态 | 工作区干净，`master` 与 `origin/master` 同步（0 ahead / 0 behind），无 tag，git origin = `awerdx520/emacs-ths` |
| 规模 | 7 个源文件 / 2808 行；11 个含 `ert-deftest` 的测试文件 + 1 个共享夹具 `tests/ths-fixtures.el` + 1 个非 ERT 的网络检查脚本 `tests/ths-live-check.el`（共 13 个文件 / 2399 行，124 个 ERT 用例） |
| ERT 基线 | `Ran 124 tests, 123 results as expected, 0 unexpected, 1 skipped`（`ths-gui-chart-geometry` 在 batch 下自动 skip），退出码 0 |
| 严格字节编译基线 | 7/7 源文件在 `byte-compile-error-on-warn = t` 下 0 error 0 warning；探针反证检查器有效 |
| 编译门禁陷阱 | ① `byte-compile-error-on-warn = t` 遇 warning **不抛 error**，`byte-compile-file` 返回 `nil` 且不生成 `.elc`；② 编译失败时 `emacs --batch` **退出码仍为 0** → 门禁判据必须取返回值 / `.elc` 存在性并显式 `kill-emacs 1` |
| ETAF 加载 | `-Q --batch` + `package-initialize` 后 `(featurep 'etaf)` 为 `nil`；必须显式 `-L ~/thomas-emacs/.local/straight/build-31.1/{etaf,etaf/lisp,ecss,ecss/lisp,ebox,ebox/lisp}`，否则 `Cannot open load file: ebox` |
| 测试入口现状 | 仓库无 `Makefile`，tests 目录无 `ert-run-tests-batch` 入口；只能靠外部命令逐个 `-l` 加载后调用 `ert-run-tests-batch-and-exit` |
| straight 安装源 | `~/thomas-emacs/.local/straight/repos/emacs-ths` 是**独立 clone**（inode 不同，同 commit `7fad453`），`build-31.1/ths/*.el` 软链经隔离根解析回该 clone → 本仓库改动不会自动进入 Emacs 加载路径 |

## 目标

用户可感知的能力清单（改造对象：`/home/thomas/Workspace/emacs-ths`，fork of `awerdx520/emacs-ths`，7 个源文件 2808 行 + 11 个含 `ert-deftest` 的测试文件 + 1 个共享夹具 `tests/ths-fixtures.el` + 1 个非 ERT 的网络检查脚本 `tests/ths-live-check.el`（共 13 个文件 / 2399 行，124 个 ERT 用例），当前无 Makefile）：

1. 港股（`hk` + 5 位数字，如 `hk00700`）与美股（`us` + 字母代码，如 `usAAPL`）报价可看：现价、昨收、开高低、成交额、时间、1 档买卖盘。
2. 港股与美股分时走势图可看：港股按 09:30-12:00 / 13:00-16:00 分段，美股按 09:30-16:00 连续，坐标轴与槽位按市场画像计算，不再假设 240 分钟。
3. 港股与美股日 K 可看：港股 `fqkline`、美股 `usfqkline`（交易所后缀由报价回填），美股可降级到新浪日 K；日 K 沿用 900 秒节流。
4. 搜索可搜到港股与美股：东财 code-table 的 `港股` / `美股` 结果映射为 `hk00700` / `usAAPL`，列表与详情显示市场标签与币种。
5. 自选可保存港美代码：`ths-watchlist.json` 格式不变，旧文件直接可读，新增 `hk` / `us` 前缀放行。
6. 排行榜可切到港股与美股：`u` 循环 5 态（A 股 / ETF / LOF / 港股 / 美股），工具栏 5 个按钮，新浪港股 2492 只、美股 18324 只可翻页。
7. 指数条扩为 8 条（A 股 3 + 港股 2 + 美股 3），按窗口宽度截断，窄窗口不挤爆。
8. 明确降级：港美只有 1 档盘口 → UI 按实际档数渲染，不生成任何替代数据；**成交明细排除在港美范围之外**——不解析、不发 trades 请求、详情页不渲染该面板。A 股成交明细行为保持原状（东财不可达导致的失效另记技术债，不在本计划修复）。
9. A 股行为零回归：现有 2399 行测试全部保持通过（3 处与新增能力冲突的断言同步修正，不删除）。
10. 兑现 README 承诺：`make check` / `make run` / `make live-check` 三个目标真实存在且可用。

## 背景与实测约束

现状：港美股是**显式拒绝**——`ths-data-symbol`（`ths-data.el:47`）只认 `sh` / `sz` / `bj` / `of` + 6 位数字；`ths-data--url`（`ths-data.el:331`）的东财 secid 只有 `1.` / `0.`；`ths-data-minute-slot`（`ths-data.el:248`）硬编码 A 股 09:30-11:30 / 13:00-15:00 共 240 分钟；`ths-data--book-rows`（`ths-data.el:194`）固定 5 档；成交量文案写死「手」（`ths.el:933`、`ths.el:968`、`ths-chart.el:218`）；排行榜 universe 只有 `stock` / `etf` / `lof`（`ths-data.el:498`）；搜索标签只映射 沪A / 深A / 京A（`ths-data.el:746`）；`ths-watchlist-symbol`（`ths-watchlist.el:11`）按首字符猜市场。

两轮真实接口探测（本机 WSL2，2026-10-22）得到的能力矩阵：

| 能力 | 港股 | 美股 |
|---|---|---|
| 报价 | 腾讯 `qt.gtimg.cn/q=hk00700` 可用（78 字段，仅 1 档盘口且量恒 0） | 腾讯 `q=usAAPL` 可用（73 字段，仅 1 档盘口，量有值） |
| 分时 | `appstock/app/minute/query?code=hk00700` 可用（行 `HHMM 价 累计量 累计额`，日期在 `data.date`） | **必须**用 `appstock/app/usMinute/query?code=usAAPL`（391 点 `0930..1600`，行 `HHMM 价 累计量`，日期在 `data.<code>.data.date`；`minute/query` 对美股只回 1 点） |
| 日 K | `appstock/app/fqkline/get?param=hk00700,day,,,120,qfq` 可用 | 腾讯 `appstock/app/usfqkline/get?param=usAAPL.OQ,day,,,120,qfq` 可用（**需交易所后缀**，无后缀只得 2 行残行）；新浪 `US_MinKService.getDailyK?symbol=AAPL&___qn=3` 可用但返回全历史约 941KB |
| 榜单 | 新浪 `Market_Center.getHKStockData?page=N&num=20&asc=0&node=qbgg_hk`，`sort` 取 `changepercent` 或 `amount`（裸 JSON 数组），总数 `getHKStockCount?node=qbgg_hk` = 2492 | 新浪 `jsonp_v2.php/var t=/US_CategoryService.getList?page=N&num=20&asc=0&market=&id=`，`sort` 取 `chg` 或 `amount`（JSONP，总数在体内 `count` = 18324） |
| 指数 | `hkHSI` / `hkHSCEI` 可用 | `usDJI` / `us.IXIC` / `us.INX` 可用 |
| 搜索 | 东财 code-table `securityTypeName=港股`（东财内部 market 116），code 5 位含前导零 `00700` | 东财 code-table `securityTypeName=美股`（内部 market 105/106/107），code 字母 `AAPL` |
| 五档盘口 | **无**（腾讯/新浪/东财四类来源穷举，上限 1 档）→ 降级为 1 档展示 | **无**（同上）→ 降级为 1 档展示 |
| 成交明细 | **无**（四类来源全部失败）→ 港美股**直接不提供**：不发请求、不渲染面板 | **无**（同上）→ 同样直接不提供：不发请求、不渲染面板 |

腾讯报价三市场差异（同一接口、不同字段布局）：

| 项 | A 股 | 港股 | 美股 |
|---|---|---|---|
| 字段数 | 88 | 78 | 73 |
| f30 时间格式 | `20261022120530` | `2026/10/22 11:59:59` | `2026-10-21 16:00:01` |
| f37 成交额单位 | 万元 | 原币（HKD） | 原币（USD） |
| f2 代码形态 | `600519` | `00700` | `AAPL.OQ` |

新浪字段布局：港股 19 字段（f0 英文名 / f1 中文名 / f2 开 / f3 昨收 / f4 高 / f5 低 / f6 现价 / f9 买一 / f10 卖一 / f11 额 / f12 量 / f17 日期 / f18 时间）；美股 36 字段（f1 现价 / f2 涨跌幅 / f3 含日期时间 / f5 开 / f6 高 / f7 低 / f10 量 / f30 额）。

东财本机不可达的三条连带影响：

1. `push2` / `push2his` / `82.push2` / `88.push2` / `push2delay` 在本机**全部不可达**（TLS 握手后 EOF，57 次尝试仅 2 次偶发 200）→ 港美股的东财分支无法实测，只能靠离线 fixture 覆盖。
2. 现有 A 股**成交明细只有东财源** → 该功能在本机已失效（非本次改造引入）。
3. A 股榜单已有新浪回退路径（`ths-data-ranking-providers` 默认 `(eastmoney sina)`），实测靠新浪可用 → 港美榜单直接走新浪，不新增东财港美节点。

## 设计

### ① 市场画像表（单一事实来源）

新增 `ths-data-markets`（alist）+ 访问器 `ths-data-market`（symbol → 画像 plist）。所有消费方只查表，不再各自硬编码。

| 属性 | sh / sz / bj | of（场外基金） | hk | us |
|---|---|---|---|---|
| 符号规则 | `sh` / `sz` / `bj` + 6 位数字 | `of` + 6 位数字 | `hk` + 5 位数字（含前导零，如 `hk00700`），或 `hk` + ≥2 位字母的指数代码（如 `hkHSI`、`hkHSCEI`，`upcase` 归一） | `us` + 字母代码（`upcase` 归一，如 `usaapl` → `usAAPL`；指数允许点号 `us.IXIC`） |
| 免前缀规则 | 6 位数字按首位补 sh / sz / bj | 不支持 | **不**自动补 `hk`（5 位数字不认） | 不支持 |
| 交易时段 | 09:30-11:30 + 13:00-15:00 | 不适用（净值） | 09:30-12:00 + 13:00-16:00 | 09:30-16:00（美东，实测 `0930..1600`） |
| 交易时段 elapsed 分钟数（**用于坐标缩放**） | 240（事实✓） | nil | 330（事实✓） | 390（事实✓） |
| 候选分时点数（含端点，需 live-check 校准） | 241（假设?） | nil | 331（假设?） | 391（假设?） |
| 价格小数位 | 2（ETF/LOF 3） | 4 | 3 | 2 |
| 成交量单位 | 手（100 股） | 不适用 | 股 | 股 |
| 币种 | CNY | CNY | HKD | USD |
| 盘口档数 | 5 | 0 | 1 | 1 |
| 成交明细 | 有（东财，本机当前不可达，行为保持原状） | 无 | **不适用（不请求）** | **不适用（不请求）** |
| 分时端点 | tencent `appstock/app/minute/query` | 无 | tencent `appstock/app/minute/query` | tencent `appstock/app/usMinute/query` |
| 日 K 端点 | tencent `appstock/app/fqkline/get` | 无（走 `ths-data--fund-fetch`） | tencent `fqkline/get`（`hk00700,day,,,120,qfq`） | tencent `usfqkline/get`（`usAAPL.OQ,day,,,120,qfq`） |
| 榜单 universe | `stock` / `etf` / `lof` | 无 | `hkstock` | `usstock` |
| 均价线 | 有（价格均值线，图内按价格累加） | 无 | 有（价格均值线；行内累计额目前未使用） | 无（行内只有累计量） |
| 报价时间格式（f30） | `20261022120530` | 无 | `2026/10/22 11:59:59` | `2026-10-21 16:00:01` |
| 显示标签 | 沪A / 深A / 京A（ETF/LOF 沪基 / 深基） | 场外基金 | 港股 | 美股 |

> 口径说明：`elapsed 分钟数` 由 `:segments` 的起止边界相减推出（事实✓），是 `(/ slot :minutes)` 的**分母**；`候选分时点数` 含收盘端点，只用于判断「当日数据是否完整」，**不参与坐标缩放**（假设?，需 `make live-check` 校准）。

### ② 报价字段差异与解析分派

| 项 | A 股 | 港股 | 美股 |
|---|---|---|---|
| 腾讯字段数（下限校验） | 88 | 78 | 73 |
| 时间字段（f30）解析 | 14 位数字 → `%F %T` | `YYYY/M/D HH:MM:SS` 归一到 `%F %T` | `YYYY-MM-DD HH:MM:SS` 原样 |
| 成交额（f37）倍数 | ×10000（万元→元） | ×1（原币） | ×1（原币） |
| 盘口档数与起始索引 | 5 档；卖自 f19、买自 f9，步长 2，量在前 | 1 档（买一 / 卖一），量恒 0 视为「无挂单量」 | 1 档（买一 / 卖一），量有值 |
| f2 代码比对 | `600519` | `00700`（含前导零，直接相等比较） | `AAPL.OQ`（比对时取句点前段与 symbol code 相等，后缀回填到 `:exchange-suffix`） |
| provider 顺序 | `tencent → eastmoney → sina` | `tencent → sina → eastmoney` | `tencent → sina → eastmoney` |
| 新浪解析器 | `ths-data--quote-sina`（A 股 32+ 字段，`hq_str_` 前缀） | 新增 `ths-data--quote-sina-hk`（19 字段） | 新增 `ths-data--quote-sina-us`（36 字段） |
| 东财 secid | sh → `1.`、sz / bj → `0.` | `116.00700`（推断，未实测） | `105.` / `106.` / `107.` + code（推断，未实测） |

### ③ 分时 / 日 K 端点与行格式

| 用途 | 端点 | 行格式 | 日期位置 | 备注 |
|---|---|---|---|---|
| 港股分时 | `https://web.ifzq.gtimg.cn/appstock/app/minute/query?code=hk00700` | `HHMM 价 累计量 累计额` | `data.<code>.data.date`（实测 `data.hk00700.data.date`） | 4 列；与 A 股同级同形，`data.date` 的原记录已实测推翻 |
| 美股分时 | `https://web.ifzq.gtimg.cn/appstock/app/usMinute/query?code=usAAPL` | `HHMM 价 累计量` | `data.<code>.data.date`（实测 `data.usAAPL.data.date`） | 3 列，无累计额 → 不画均价线；日 K 层级与港股一致（原记录的两层不对称不成立） |
| 港股日 K | `https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=hk00700,day,,,120,qfq` | 数组行 `[日期 开 收 高 低 量]` | 行首 | 实测数组键名 **`day`**（qfq 下仍返回 `day`，121 行含当日） |
| 美股日 K | `https://web.ifzq.gtimg.cn/appstock/app/usfqkline/get?param=usAAPL.OQ,day,,,120,qfq` | 数组行 `[日期 开 收 高 低 量]` | 行首 | 实测数组键名 **`qfqday`**（120 行）；`data` 键带后缀 `usAAPL.OQ`，取值需容忍后缀。后缀由报价 f2 回填 |
| 美股日 K 兜底 | `https://stock.finance.sina.com.cn/usstock/api/jsonp.php/var _AAPL_MinK=/US_MinKService.getDailyK?symbol=AAPL&___qn=3` | JSONP：块注释 + `var _AAPL_MinK=([{d,o,h,l,c,v,a},…]);` | 行首 `d`（已是 `%F`） | 实测 10058 行 / 941526 字节，只保留最近 120 根，必须节流 |

> 实测记录（2026-10-22）：港股分时 312 点（盘中，首点 slot 0）、美股分时 391 点（首 0 末 390）、港股日 K 121 行、美股日 K 120 行、新浪兜底 10058 行截到 120 行；港美分时层级与 A 股完全一致，实现上共用一条 tencent 取值路径，仅列数与端点不同。

### ④ 榜单端点

| universe | 源 | 端点 | 响应格式 | 总数来源 |
|---|---|---|---|---|
| `stock` / `etf` / `lof` | 东财 + 新浪回退 | 现状不变（`ths-data--ranking-url` / `ths-data--ranking-sina-url`） | JSON / JSONP | 东财 `data.total`；新浪 `getHQNodeStockCount` |
| `hkstock` | 新浪 | `Market_Center.getHKStockData?page=N&num=20&sort=changepercent` 或 `amount`，`asc=0&node=qbgg_hk` | 裸 JSON 数组 | 单独端点 `Market_Center.getHKStockCount?node=qbgg_hk` = 2492 |
| `usstock` | 新浪 | `jsonp_v2.php/var t=/US_CategoryService.getList?page=N&num=20&sort=chg` 或 `amount`，`asc=0&market=&id=` | JSONP（需剥 `var t=` 与包裹括号） | 体内 `count` = 18324 |

### ⑤ 搜索映射

| 东财 `securityTypeName` | code 形态 | 目标 symbol | 处理 |
|---|---|---|---|
| 沪A / 深A / 京A | 6 位数字 | `sh` / `sz` / `bj` + code | 现状不变 |
| 沪基 / 深基 / 基金 / 场内基金 / ETF / LOF | 6 位数字 | 按 `ths-data-fund-market` 判市场 | 现状不变 |
| 港股 | 5 位数字（含前导零） | `hk` + code | 新增：保留前导零，不做数字解析 |
| 美股 | 字母代码 | `us` + code | 新增：`upcase` 归一后拼前缀（不做 downcase） |
| 指数 / 粉单 / 债券 / 期货 / 期权 / 概念 | 任意 | 忽略 | 非目标，不入结果（与现状一致） |

### ⑥ 显式非目标

1. 不做交易、委托、持仓、资金流水——本项目只读行情。
2. 不接任何付费行情源（港美 5 档盘口、逐笔成交流只能靠付费源，本次不做）。
3. 不伪造缺失数据：1 档盘口不补齐 5 档（不填 `--` 伪造行）、无累计额不画均价线。
4. 不做汇率换算（币种只做展示标签，不做跨市统一计价）。
5. 不做盘前 / 盘后 / 竞价时段分时（仅常规连续交易时段）。
6. 不做港美东财分支的实网验证（东财域名本机不可达），只做离线 fixture 覆盖。
7. 港美股成交明细：无可用源，因此整块不做——不发起 trades 请求、详情页不渲染该面板（不留任何替代面板或说明文案）；A 股成交明细保持原状，不在本计划内改动。

## 假设清单

1. `hk` + 5 位数字、`us` + 字母代码两种前缀可与 A 股并列处理，不破坏 `ths-data-symbol-id`（`ths-data.el:58`，`(substring symbol 2)`）。来源：事实✓（现有实现按 2 字符前缀切分，对新前缀同样成立）。
2. 美股日 K 的交易所后缀可由报价 f2（形如 `AAPL.OQ`）回填。来源：假设?（f2 格式仅在 `AAPL` 一个样本上观测，`usfqkline` 是否接受全部后缀未验证；且报价与日 K 是两个请求，存在时序耦合）。
3. 港美股分时点数：港股 330 分钟 / 331 点、美股 390 分钟 / 391 点（点数含端点，待 live-check 校准）。来源：假设?（美股 391 点为单次实测 `0930..1600` 含端点，港股 331 点由 09:30-12:00 + 13:00-16:00 两段推出；夏令时、半天市、临时休市都会改变实际点数，需 `make live-check` 校准并记录下来）。
4. 腾讯报价字段位置（名称 1、现价 3、昨收 4、开 5、高 33、低 34、时间 30、成交额 37、换手 38）在港美可复用（`ths-data--quote-tencent`，`ths-data.el:207`）。来源：事实✓（两轮探测对 `hk00700` / `usAAPL` 逐字段核对一致）。
5. 新浪港美行情与榜单端点无鉴权、可直接请求（现有 `ths-data--http` 走 `curl` 即可）。来源：事实✓（探测均返回 200 与预期结构）。
6. 港美价格精度按市场分派（hk 3 位、us 2 位）。来源：类比⚡（参考主流行情终端显示惯例，非接口规定；若真实数据出现 4 位小数须回改 `ths-data-format-price`）。
7. 东财 `push2` 系列不可达是本机网络环境问题，而非接口下线。来源：假设?（57 次尝试仅 2 次偶发 200，无法区分 DNS / TLS 中间设备与源站故障；因此港美东财分支保留但只做离线覆盖）。

## 任务

执行顺序（严格串行，同一文件禁止并行编辑）：任务0 → 任务1 → 任务2 → 任务3 → 任务4 → 任务5 → 任务6 → 任务7 → 任务8。任务3 / 任务4 / 任务5 共享 `ths-data.el`，任务6 亦改 `ths-data.el`，四者一律按序执行。

- [x] 任务0：验证入口前置（Makefile + 严格编译驱动 + ERT runner）
  - 文件：`/home/thomas/Workspace/emacs-ths/Makefile`（创建）、`/home/thomas/Workspace/emacs-ths/scripts/boot.el`（创建）、`/home/thomas/Workspace/emacs-ths/scripts/compile-strict.el`（创建）、`/home/thomas/Workspace/emacs-ths/scripts/test-batch.el`（创建）
  - 步骤：
    - 新建 `scripts/boot.el`（batch 依赖引导）：`(require 'package)` + 先 `(setq package-archives nil)` 再 `package-initialize`（纯离线，不建索引、不安装）；若 `(not (featurep 'etaf))` 则按顺序遍历通配目录（`~/.emacs.d/straight/build-*/*`、`~/.config/emacs/straight/build-*/*`、`~/*/.local/straight/build-*/*`、`~/*/straight/build-*/*`，目录存在才 `add-to-list 'load-path`），再 `(require 'etaf nil t)`；仍不可见则 `error` 并提示用 `LOAD=` 覆盖；成功打印 `boot: ETAF 就绪`。
    - 新建 `scripts/compile-strict.el`：把 `byte-compile-dest-file-function` 重定向到 `(make-temp-file "ths-elc-" t)` 生成的临时目录；`(setq byte-compile-error-on-warn t)`；对 7 个源文件逐个 `byte-compile-file`，**按返回值判失败**（`nil` 即失败，同时校验 `.elc` 存在性；抛错型失败用 `condition-case` 转成失败项）；任一失败 → 打印文件名与失败原因 → `(kill-emacs 1)`；全部成功 → 打印摘要、删除临时目录、返回 0。
    - 新建 `scripts/test-batch.el`：**先 `load` `tests/ths-tests.el`**（该文件内部用 `load-file-name` 加载 `tests/ths-fixtures.el`，并定义公共宏 `ths-test-with-dashboard` 与辅助函数 `ths-test-press` / `ths-test-visible`），**再**加载其余 10 个含 `ert-deftest` 的测试文件（显式加载共 **11** 个 = `ths-tests.el` + 其余 10 个；`tests/ths-fixtures.el` 由 `ths-tests.el` 内部 `(load ...)` 自动加载，不在此显式加载；`tests/ths-live-check.el` 排除），最后调用 `ert-run-tests-batch-and-exit`。
      - 顺序约束依据（实测 2026-10-22）：`-l` 解释执行下 `ert-deftest` 只把 body 包进 `(lambda () ...)`，宏调用在**测试运行时**才展开，因此字母序加载与「宏使用者先于定义者」两种顺序都能跑通 `Ran 124 tests / 0 unexpected`；显式前置 `ths-tests.el` 属**加固**，用于防御将来把测试流程改成字节编译（那时缺宏只会产生警告，加载期会静默取到未展开宏的旧字节码）。
      - 明确不做：`make check` **不字节编译测试文件**（`tests/ths-trades-tests.el:101` 存在既存 free variable `buffer`，严格编译会失败，属既存噪声，不在本计划范围）。
    - 新建 `Makefile`：`EMACS ?= emacs`；`LOAD ?=` 可被用户覆盖，默认通过 `scripts/boot.el` 做依赖引导——先 `(require 'package)` + `package-initialize`，若 `(not (featurep 'etaf))` 则遍历通配目录（`~/.emacs.d/straight/build-*/*`、`~/.config/emacs/straight/build-*/*`、`~/*/.local/straight/build-*/*`、`~/*/straight/build-*/*`）把目录加入 `load-path`，仍找不到则打印明确错误（提示用 `LOAD=` 覆盖）并失败退出（引导逻辑全部落在 `scripts/boot.el`）。
    - 三个目标：`check` = `$(EMACS) -Q --batch $(LOAD) -L . -L tests -l scripts/compile-strict.el`，下一行 `$(EMACS) -Q --batch $(LOAD) -L . -L tests -l scripts/test-batch.el`（两个**独立命令行**：make 逐行执行且首行失败即整体停止，语义等价于 `&&` 串联，引号更安全）；`run` = `$(EMACS) -Q $(LOAD) -L . --eval "(progn (require 'ths) (ths))"`；`live-check` = `$(EMACS) -Q --batch $(LOAD) -L . -L tests -l tests/ths-live-check.el`。
    - Makefile 注释写明：为什么必须用 `scripts/compile-strict.el`（`byte-compile-error-on-warn` 不抛错 + batch 退出码恒 0 两个陷阱）。
  - 验收标准：`make -n check` / `make -n run` / `make -n live-check` 三条均无报错；`make check` 在**未改动任何源码**的基线上返回 0，输出含 `Ran 124 tests` 与 `0 unexpected`；运行后 `git status --short` 不出现任何 `.elc`；人为制造一条 warning（用 `/tmp` 临时副本，不得污染仓库）时 `make check` 必须返回非零。`scripts/test-batch.el` 必须先加载 `tests/ths-tests.el`（自检方式：`grep -c "ths-tests.el" scripts/test-batch.el` 应 ≥ 1）。
  - 依赖：无
  - 实现记录（2026-10-22，locale 固定补强）：`make check` 原有 3 条断言（`ths-fixture-charts-and-book-have-consistent-bounds`、`ths-volume-dashboard-shows-both-panels-without-growing-page`、`ths-volume-terminal-charts-preserve-height-and-column-width`）依赖 Emacs 宽字符显示宽度，结果随调用者 locale 变化——基线 `172e20d` 上实测即已存在，与港美改动无关：`LC_ALL=zh_CN.UTF-8` 下 3 条 FAILED（exit 2），`LC_ALL=C.UTF-8` / `en_US.UTF-8` 下 146 tests / 0 unexpected（exit 0）。为满足「`make check` 可重复、exit 0」的门禁判据，**不改任何测试断言与源码**，只在 Makefile 内固定运行环境：新增 `LOCALE_ENV = LC_ALL=C.UTF-8`，前缀到 `BATCH`（覆盖 `check` 与 `live-check` 两条命令行）和 `run` 目标的命令行；选定 `C.UTF-8` 依据是实测全绿且比 `en_US.UTF-8` 更通用（另实测 `LC_ALL=C` 非 UTF-8 会失败，故必须带 `.UTF-8`），文件头注释写明「有意覆盖调用者的 `LC_ALL`/`LANG`」。验证：默认环境 / `LC_ALL=zh_CN.UTF-8` / `LC_ALL=en_US.UTF-8` 三种调用均 `Ran 146 tests, 145 results as expected, 0 unexpected, 1 skipped` 且 exit 0；`make -n check` 输出含 `LC_ALL=C.UTF-8` 前缀；`.elc` 数 0。

- [x] 任务1：市场画像表与符号规范化
  - 文件：`/home/thomas/Workspace/emacs-ths/ths-data.el`（修改）、`/home/thomas/Workspace/emacs-ths/ths-watchlist.el`（修改）、`/home/thomas/Workspace/emacs-ths/tests/ths-hkus-tests.el`（**创建**，先落符号矩阵骨架用例；任务7 扩充同一文件，禁止并行编辑）、`/home/thomas/Workspace/emacs-ths/scripts/test-batch.el`（修改：新测试文件加入显式加载清单，否则 `make check` 不会运行新用例——任务0 的清单遗漏，任务1 补齐）
  - 步骤：
    - 在 `ths-data.el:34`（`ths-data-index-symbols` 所在处）附近新增 `ths-data-markets`（6 个市场画像的 alist，字段见「设计 ①」）与访问器 `ths-data-market`、`ths-data-market-key`。
    - 改 `ths-data-symbol`（grep 锚点 `(defun ths-data-symbol `，`ths-data.el:47`）：正则放行 `hk` + 5 位、`us` + 字母（允许点号），`us` 段统一 `upcase` 归一（禁止 `downcase`；`usaapl`→`usAAPL`、`us.ixic`→`us.IXIC`）。
    - 改 `ths-data-symbol-id`（`ths-data.el:58`）与 `ths-data-fund-p`（`ths-data.el:73`，`(= (length symbol) 8)` 固定长度假设）为按画像分派。
    - 改 `ths-data-format-price`（`ths-data.el:80`）小数位来源为画像 `:decimals`，删除 otc/fund/其他三分支判断。
    - 改 `ths-data-placeholder`（`ths-data.el:92`，`market-label` 的 `pcase (substring symbol 0 2)`）标签来自画像 `:label`，补 港股 / 美股 / 港股指数 / 美股指数。
    - 改 `ths-watchlist-symbol`（`ths-watchlist.el:11`）：`hk` / `us` 前缀放行复用 `ths-data-symbol`；6 位数字免前缀仍按首位补 A 股；5 位数字 `user-error` 提示补 `hk` 前缀；保留 `ths-data-index-symbols` 排除逻辑。
  - 验收标准：ERT `ths-symbol-matrix`（新增，9 类合法 + 9 类非法输入逐一断言）；`make check` 中 `tests/ths-watchlist-tests.el` 既有断言（含 `ths-watchlist-tests.el:13` 的非法输入表）全绿。
  - 依赖：无

- [x] 任务2：报价解析与 provider 路由
  - 前置探测（2026-10-22，本机 WSL2，`fetch` 直连；响应为 GB18030 编码，解析层已按 provider 解码）：

    | 端点 | HTTP | 字段数 | 关键结构 |
    |---|---|---|---|
    | `https://qt.gtimg.cn/q=hk00700` | 200 | 78（`~` 分隔） | f1 腾讯控股 / f2 `00700` / f3 现价 / f4 昨收 / f5 开 / f30 `2026/10/22 15:13:16` / f33 高 / f34 低 / f37 `20022534991.300`（HKD 原值）/ f38 换手 / f9 买一价 / f19 卖一价（f10/f20 量恒 0） |
    | `https://qt.gtimg.cn/q=usAAPL` | 200 | 73 | f2 `AAPL.OQ`（带交易所后缀）/ f30 `2026-10-21 16:00:01` / f37 `12221259717`（USD 原值）/ f35 币种 USD / 1 档盘口带真实量 |
    | `https://qt.gtimg.cn/q=hkHSI` | 200 | 78 | f2 `HSI`（**无 `hk` 前缀**，与 `ths-data-symbol-id` 的 `HSI` 直接相等）；f30 同为港股格式 |
    | `https://qt.gtimg.cn/q=us.IXIC` / `q=usDJI` / `q=us.INX` | 200 | 73 / 73 / 73 | f2 分别为 `.IXIC` / `.DJI` / `.INX`（**点号在前、无交易所后缀**），故美股 f2 比对需先剥前导点再取句点前段 |
    | `https://hq.sinajs.cn/list=hk00700` | 200 | 19（`,` 分隔） | f0 TENCENT / f1 腾讯控股 / f2 开 / f3 昨收 / f4 高 / f5 低 / f6 现价 / f9 买一 / f10 卖一 / f11 额 / f12 量 / f17 `2026/10/22` / f18 `15:02`（无秒、无买卖量） |
    | `https://hq.sinajs.cn/list=gb_aapl` | 200 | 36 | f0 苹果 / f1 现价 / f3 `2026-10-22 09:30:13` / f4 涨跌额 / f5 开 / f6 高 / f7 低 / f10 量 / **f26 昨收 339.5000**（等于 f1−f4，与腾讯 f4 一致）/ f30 额 `12223111721.0000`；无任何盘口字段 |
    | `https://hq.sinajs.cn/list=usAAPL` | 200 | 0（`hq_str_usAAPL=""`） | **不可用**：新浪美股列表键是 `gb_` + 小写代码，`usAAPL` 形式返回空串 |

    探测结论（已写回实现）：① 港美腾讯 `f37` 均为原币，倍数 1；A 股万元 → 倍数 10000。② 新浪美股 `f26` 就是昨收，`ths-data--parse` 的「昨收 + 名称」校验对港美无需放宽。③ 新浪美股无盘口 → `:book` 为 nil；新浪港股有买卖一价但无买卖一量 → 量为 nil。④ 腾讯美股 `f2` 的指数形态是前导点（`.IXIC`），实现按「剥前导点 → 取句点前段 + 后缀」处理，`AAPL.OQ` 的后缀仍回填 `:exchange-suffix`。⑤ 三个 provider（腾讯 / 新浪 / 东财）在探测中港美均可用（东财域名本机不可达，保留在顺序中只做离线覆盖），故港美报价顺序为 `tencent → sina → eastmoney`。
  - 文件：`/home/thomas/Workspace/emacs-ths/ths-data.el`（修改）
  - 步骤：
    - 把 `ths-data--url`（`ths-data.el:331`，`(let ((secid (concat (if (string-prefix-p "sh" symbol) "1." "0.") ...`）的 secid 前缀下沉到画像 `:secid-prefix`，新增 `ths-data--eastmoney-secid`（hk → `116.`、us → `105.`/`106.`/`107.`）。
    - 改 `ths-data--book-rows`（`ths-data.el:194`，固定 `'(5 4 3 2 1)` 档序）接受 levels 参数；`ths-data--quote-tencent`（`ths-data.el:207`，`(ths-data--book-rows get 19 9 nil 1)`）按画像传档数与起始索引。
    - 改 `ths-data--timestamp`（`ths-data.el:187`，只认 14 位数字）为按市场分派三种 f30 格式；`ths-data--quote-tencent` 的 `:amount (when-let* ((n (ths-data-number (nth 37 fields)))) (* n 10000.0))` 倍数改读画像 `:amount-scale`。
    - 新增 `ths-data--quote-sina-hk` / `ths-data--quote-sina-us`（新浪 19 / 36 字段），并把 `ths-data--quote-sina`（`ths-data.el:221`，硬编码 `hq_str_` 前缀与 `>= 32`）的前缀与字段下限移入画像。
    - 改 `ths-data--parse`（`ths-data.el:440`，`pcase provider` 三分支）为按 `(provider, market)` 二元分派；`ths-data--quote-tencent` 的 f2 比对按画像处理（美股取句点前段、后缀存入 `:exchange-suffix`）。
    - 改 `ths-data-fetch`（`ths-data.el:455`，`(seq-filter (lambda (p) (or (eq kind 'quote) (not (eq p 'sina)))) ...)`）按画像给出 provider 顺序（港美报价 `tencent → sina → eastmoney`）。
  - 验收标准：新增 ERT `ths-hkus-quote-tencent-parses`、`ths-hkus-quote-sina-parses`、`ths-hkus-quote-amount-scale`（断言 A 股 ×10000、港美 ×1）、`ths-hkus-quote-single-level-book`；`tests/ths-data-tests.el` 既有 A 股解析断言全绿。
  - 依赖：任务1

- [x] 任务3：分时与日 K
  - 文件：`/home/thomas/Workspace/emacs-ths/ths-data.el`（修改）、`/home/thomas/Workspace/emacs-ths/ths-chart.el`（修改）
  - 步骤：
    - 改 `ths-data-minute-slot`（`ths-data.el:248`，`(cond ((<= 570 m 690) ...) ((<= 780 m 900) ...))`）为按画像 `:segments` 累加计算 slot，超界仍报错（A 股 240、港股 330、美股 390，均取 elapsed 分钟数）；签名改为 `(time &optional market)`（缺省按 A 股，保证 `tests/ths-data-tests.el:128` 既有断言仍绿）。
    - 传递链固定为三层：`ths-data-minute-slot` 取 `(time &optional market)`；`ths-data--point` 增加 market 参数并原样透传；`ths-data--chart` 按 symbol 的画像把 market 传给 `--point`（三处不得各自猜市场）。
    - 改 `ths-data--url`（`ths-data.el:331`）的 `(tencent intraday)` / `(tencent daily)` 分支：按画像选 `minute/query` 或 `usMinute/query`，日 K 选 `fqkline/get` 或 `usfqkline/get` 并拼 `,day,,,120,qfq` 与交易所后缀。
    - 改 `ths-data--chart`（`ths-data.el:295`）**按端点分派取值路径**，而不是笼统按 provider 分支：现有 tencent 分支是 `(ths-data--get root "data" symbol)` 再取 `"data" "date"`。设计③ 表格记录的日期位置差异（港股 `data.date`、美股 `data.<code>.data.date`）提示两者**层级不对称**，需按市场/端点分四种组合取值。实现前**必须**先打印一次真实响应的键层级（`(ths-data--json text)` 后逐层 keys）确认，不得凭表格臆断；行字段数为 4（港，含累计额 → 可算均价线）或 3（美，无额 → `:average` 为 nil）；qfq 日 K 的数组键名同样先打印确认（A 股读 `"day"`，港美可能是 `"qfqday"`），禁止沿用 A 股的 `"day"` 与固定层级硬编码。
    - 后缀回填（**不做两阶段编排**）：现有 `ths-data-fetch (symbol kind callback)`（`ths-data.el:455`）只接收 symbol 字符串、内部是单 kind 的 provider 回退链（`cl-labels next`），**不持有 stock plist**，插入「先 quote 后 daily」需重写控制流并引入竞态。改为四步：① quote 解析时把 f2 句点后的交易所后缀写入结果 plist 的 `:exchange-suffix`，由 `ths--fetch`（`ths.el:99`）落库到 `ths-data-stocks`；② `daily` + `us` 请求时用 `(ths-data-find symbol)` 取 plist 读 `:exchange-suffix`；③ **后缀缺失时禁止拼无后缀 URL**（实测只得 2 行残行并污染缓存），直接改走新浪 `US_MinKService.getDailyK` 兜底；④ 后缀存在时走腾讯 `usfqkline`，失败再降级新浪。
    - 改 `ths-chart.el:77` / `ths-chart.el:250` / `ths-chart.el:257`（`(/ (plist-get point :slot) 240.0)`）为画像 `:minutes`；改 `ths-chart.el:116`（`<text ...>09:30</text>`）与 `ths.el:914`（`"09:30 11:30 / 13:00 15:00"` 文案）为画像 `:axis-label`。
    - 均价线降级与节流：`ths-chart-svg`（`ths-chart.el:61`）、`ths-chart-line`（`ths-chart.el:242`）在 `:average-line` 为 nil（美股）时跳过均价折线；`ths--ensure-chart`（`ths.el:138`，节流判断 `(if (ths-data-otc-p stock) 900 ...)`）把美股 `daily` 并入 900 秒分支。
    - 画像口径（与「设计 ①」一致）：`:minutes` 取 elapsed 分钟数（港 330 / 美 390），分时点数只用于「数据是否完整」的判断，不参与坐标缩放。
  - 验收标准：新增 ERT `ths-hkus-minute-slot-hk`、`ths-hkus-minute-slot-us`、`ths-hkus-svg-omits-average-line-us`、`ths-hkus-daily-throttle-us`；`tests/ths-data-tests.el:128`（`(= 240 (ths-data-minute-slot "1500"))`）仍绿。
    - 槽映射断言值（写死为常量，不取实现计算值）：港股 09:30→0、12:00→150、13:00→150、16:00→330。
    - 槽映射断言值（续）：美股 09:30→0、16:00→390；A 股 09:30→0、11:30→120、13:00→120、15:00→240（回归）。
  - 实现记录（2026-10-22 实测，与上述步骤的偏差已按实测落定）：
    - 港美分时层级与 A 股**完全一致**（`data.<code>.data.date` + `data.<code>.data.data`），因此共用同一条 tencent 取值路径，只有端点（`minute` / `usMinute`）与列数（4 / 3）不同——原计划设想的「四种组合取值」不成立。
    - 数据层**不产出** `:average` 字段：均价线是 `ths-chart.el` 按价格累加算出的图内均值（`mean-line` / 字符图「·」）。因此「美股无均价线」由画像 `:average-line` 驱动，未新增无人使用的 `:average` 键（避免造死数据）。
    - 交易所后缀读取必须用 `(ths-data-find (ths-data-symbol-id symbol))`：`ths-data-find` 以 `:code` 匹配，直接传 `usAAPL` 恒为 nil（会永远走新浪）。
    - 日 K 数组键名按实测分派：美股 `qfqday`、港股 `day`、A 股 `day`（`ths-data--tencent-candles`），并新增 `ths-data--node` 容忍美股 `data` 键的 `.OQ` 后缀。
    - 坐标按 `:minutes` 缩放并把比例夹到 `[0,1]`：实际点数少于画像分钟数（盘中）或与之不等时不报错、不越界。
    - 轴标签按画像 `:axis-label` 派生出「会话起/中点/止」（相邻两段共享边界写作 `A / B`）：A 股输出与改动前**逐字一致**（已实测比对 SVG 轴行），港 `09:30 10:45 12:00 / 13:00 14:30 16:00`、美 `09:30 12:45 16:00`。
  - 依赖：任务2

- [x] 任务4：自选与搜索
  - 文件：`/home/thomas/Workspace/emacs-ths/ths-watchlist.el`（修改）、`/home/thomas/Workspace/emacs-ths/ths-search.el`（修改）、`/home/thomas/Workspace/emacs-ths/ths-data.el`（修改）
  - 步骤：
    - 确认 `ths-watchlist-symbol`（`ths-watchlist.el:11`）与任务1 的画像校验共用同一入口（不重复写正则），并保证 `ths-watchlist-load`（`:26`）/`ths-watchlist-save`（`:39`）的 JSON 数组格式不变。
    - 改 `ths-search--label`（`ths-search.el:17`，兜底 `pcase (substring (plist-get stock :symbol) 0 2)` 只有 sh/sz/_）为查画像 `:label`；`ths-search--local`（`:25`）/`ths-search--update`（`:116`）在请求前剥掉用户重复输入的 `hk` / `us` 前缀。
    - 改 `ths-data--search-parse`（`ths-data.el:736`）：market→prefix 映射（`ths-data.el:746` 的 `(cdr (assoc market '(("沪A" . "sh") ...)))`）增加 `港股 → hk`、`美股 → us`。
    - 改同函数 code 校验（`ths-data.el:757` 的 `(string-match-p "\\`[0-9]\\{6\\}\\'" code)`）为按画像分派：A 股 6 位数字、港股 5 位数字（保留前导零）、美股字母（`upcase` 归一）。
    - 确认 `ths-data-fetch`（`:455`）对 `hk` / `us` 不进 `ths-data--fund-fetch` 分支，`ths-data-otc-p`（`:54`）只认 `of`。
  - 验收标准：新增 ERT `ths-search-hk-us-symbols`（`00700` + 港股 → `hk00700`；`AAPL` + 美股 → `usAAPL`；`350` 之类 5 位输入仍被拒）。
  - 既有用例处理（与任务7 一致，不得两头写不同目标）：`tests/ths-search-tests.el:41` 的 deftest `ths-search-funds-require-trading-code-and-compatible-market` 输入样本中含 `("00700" . "港股")`，并断言 `(cl-every #'ths-data-fund-p rows)`——港美支持后 `hk00700` 会进入结果从而破坏该断言。因此**把该港美样本从这条基金测试的输入中移除**，`:56` 期望列表保持 `("sh510300" "sz159915" "sh501018" "sz161725")` 四个 symbol、`cl-every fund-p` 断言保持原样；港美映射改由新增用例 `ths-search-hk-us-symbols` 覆盖。**不采用「把期望列表扩成五个或六个 symbol」的写法。**
  - 依赖：任务1
  - 实现记录（2026-10-22）：
    - **code 校验不写第二份正则**：新增 `ths-data--search-symbol`，用 `(ths-data-symbol (concat prefix code))` 统一判定并归一（`hk` 5 位保留前导零、`us` upcase、A 股/基金 6 位），失败返回 nil 后仍报「股票搜索结果包含无效代码或名称」。因此港美格式与任务1 的 `ths-data-symbol` 天然一致，不存在两处正则漂移。
    - **前缀剥离下沉到一处**：新增 `ths-search--strip-prefix`（A 股沿用原正则 `sh|sz|bj|of` + 数字，港美单独一条 `hk|us` + 字母/数字/点）。`ths-search--local` 与 `ths-search--request` 各自调用它，而 `ths-search--request` 是**唯一网络出口**，故 `ths-search--update` 无需重复剥离（其本地过滤经 `--local`、其请求经 `--request`，两处都已覆盖）。港美正则不与 A 股混写，避免把拼音查询（如 `shzg`）误剥成 `zg`。
    - **`ths-search--local` 增加裸代码通道**：标签匹配（symbol / 名称 / 市场名 / 拼音）以外，再对 `:code` 做剥前缀后匹配，于是 `00700` 也能命中 `hk00700`；空查询保持「全匹配」语义（不破坏既有 `--update session ""` 断言）。
    - **既有夹具冲突（计划未预料）**：`tests/ths-search-tests.el` 的共享夹具 `ths-search-test-response` 内本来就含一条 `("00700" . "港股")` 样本，港美映射生效后 `ths-search-parser-keeps-unique-mainland-stocks-and-listed-funds`（4 symbol 全等）与 `ths-search-request-encodes-query-and-propagates-errors`（`(= 4 (length result))`）会失败。处理方式：**只从夹具中删掉那一行样本**（未删任何断言、未改 `:expected-result`），港美映射改由 `tests/ths-hkus-tests.el` 的独立样本覆盖。
    - **新增用例落在 `tests/ths-hkus-tests.el`**（而非任务4 原文写的 `ths-search-hk-us-symbols`）：`ths-hkus-search-maps-hk-us`、`ths-hkus-search-rejects-bad-codes`、`ths-hkus-watchlist-roundtrip`、`ths-hkus-search-label`、`ths-hkus-search-local-matches-hk-us`，共 5 条（146 tests / 0 unexpected）。
    - **确认项实测**：`ths-data-fetch` 只对 `of` 前缀转 `ths-data--fund-fetch`（`ths-data.el:1170` 附近 `(string-prefix-p "of" symbol)`），`ths-data-otc-p` 只认 `of`，`ths-watchlist-save` 仍 `(json-serialize (vconcat symbols))` 写纯数组、`ths-watchlist-load` 仍按数组读 → 旧 JSON 直接可读。
    - **发现的既有环境问题（非本任务引入）**：`tests/ths-tests.el:138` 与 `tests/ths-volume-tests.el` 两条用例在 `LANG=zh_CN.UTF-8` 下失败、`LANG=en_US.UTF-8` 下通过（宽字符宽度随 locale 变化）。用 `git worktree` 在 HEAD `172e20d` 基线上复现同样 3 条失败（141 tests / 3 unexpected），确认与本次改动无关；`make check` 需在 `LANG=en_US.UTF-8` 下运行才能拿到 exit 0。

- [ ] 任务5：排行榜
  - 文件：`/home/thomas/Workspace/emacs-ths/ths-data.el`（修改）、`/home/thomas/Workspace/emacs-ths/ths.el`（修改）
  - 步骤：
    - 改 `ths-data-ranking-universe`（`ths-data.el:498`，`(memq universe '(nil stock etf lof))`）为 5 类；`ths-data-ranking-label`（`:504`，pcase 3 分支）补 `hkstock → 港股`、`usstock → 美股`。
    - 改 `ths-data--ranking-symbol`（`:519`，只认 `[0-9]{6}`）按 universe 分派：`hkstock` → `hk` + 5 位、`usstock` → `us` + 字母。
    - 改 `ths-data--ranking-sina-url`（`:608`，`node` 的 pcase 只有 `hs_a` / `etf_hq_fund` / `lof_hq_fund`）：增加港股 `Market_Center.getHKStockData` + `node=qbgg_hk`（排序 `changepercent` / `amount`）与美股 `jsonp_v2.php/var t=/US_CategoryService.getList`（排序 `chg` / `amount`）两套分支。
    - 改 `ths-data--ranking-sina-count`（`:623`）与 `ths-data--ranking-sina-parse`（`:629`）：港股是裸 JSON 数组（现有 `ths-data--sina-json-body` 后可复用）、美股总数在体内 `count`（需新增体内取数分支，不再依赖单独 count 端点）。
    - 改 `ths-data--ranking-url`（`:532`，东财 `82.push2` / `push2delay` / `88.push2`）：`hkstock` / `usstock` 直接报「东财不提供港美榜」并跳过，不发请求（东财港美节点本机不可达）。
    - 改 `ths.el`：`ths-ranking-cycle-universe`（`ths.el:295`，`(pcase universe ('etf 'lof) ('lof 'stock) (_ 'etf))`）改 5 态；universe 按钮行（`ths.el:539`，首个按钮 `rank-stock` 在 `:540`）补 港股 / 美股；`ths--ranking-columns`（`ths.el:473`，`(memq universe '(etf lof))` 窄屏分支）对港美隐藏 60 日涨跌幅与流通市值列。
  - 验收标准：新增 ERT `ths-hkus-ranking-urls`（断言 `node=qbgg_hk` 与 `US_CategoryService.getList` 各出现一次、东财分支不发请求）、`ths-hkus-ranking-parse-total`（2492 / 18324）、`ths-hkus-ranking-cycle-5-states`；`tests/ths-fund-ranking-tests.el` 既有 universe / 排序断言全绿。
  - 依赖：任务2、任务4（三者都改 ths-data.el，必须串行：任务2 → 任务4 → 任务5；禁止并行编辑同一文件）

- [ ] 任务6：UI 展示
  - 文件：`/home/thomas/Workspace/emacs-ths/ths.el`（修改）、`/home/thomas/Workspace/emacs-ths/ths-data.el`（修改）
  - 步骤：
    - 改 `ths--exchange-detail`（`ths.el:867`）标题行 `(format "%s  %s  /  %s" name id sector)` 追加画像 `:label` 与 `:currency`。
    - 改 `ths--exchange-book`（`ths.el:929`，标题 `ths.el:933` `"五档盘口 / 手"`，`cl-loop for (label price volume side) in (ths-data-book stock)`）按 `:book-levels` 渲染：港美只出买一 / 卖一，标题「盘口 / 股」，且不补伪造档位。
    - 改 `ths--ensure-chart`（`ths.el:138` 定义，`:145` 三元分支）的请求列表：`ths.el:145` 的三元分支为 `(if (ths-data-otc-p stock) '(quote) (list (plist-get state :chart) 'trades))`；改为：场外基金 → `(quote)`；hk/us → `(list (plist-get state :chart))`（保留 chart、去掉 trades）；A 股 → `(list (plist-get state :chart) 'trades)` 不变。
    - 详情页渲染跳过成交明细面板要改两处：`ths--trades`（`ths.el:861`，现有 OTC 判断需补 hk/us 分支）与 `ths--market-sidebar`（`ths.el:1002`，宽窗口 sidebar 固定渲染 book+trades，港美只渲染 book）；A 股保持原样。
    - 改 `ths--trade-cells`（`ths.el:952`，`ths.el:968` 的 `(:volume "量/手" 8)`）与 `ths--volume`（`ths.el:466`，`"%.0f手"`）：单位文案按画像取「手」或「股」；`ths-chart.el:218` / `:226` 的「成交量（手）」/「量/手」同样按画像。
    - 扩指数条：`ths-data-index-symbols`（`ths-data.el:34`）扩为 8 条（A 股 3 + `hkHSI` / `hkHSCEI` + `usDJI` / `us.IXIC` / `us.INX`），并在 `ths-data--metadata`（`ths-data.el:36`）补名称；`ths--dashboard`（`ths.el:1063`）的指数行（`ths.el:1092`-`1104`）改为按可用宽度计算固定项宽并截断尾部。
    - 自选列表行（`ths--watchlist`，`ths.el:716`）名称列补市场标签；列表排序 / 筛选（`ths-data-filter`，`ths-data.el:117` 的 `:market-label` 查询键）确认可搜「港股」「美股」。
  - 验收标准：新增 ERT `ths-hkus-book-single-level`（无「卖5」、只 1 档）、`ths-hkus-index-bar-8-entries`（宽窗口 8 项 / 窄窗口截断）、`ths-hkus-no-trades-request`（断言：对 hk/us 符号调用 `ths--ensure-chart` / `ths--fetch` 时，`ths-data-fetch` 收到的 kind 参数不含 `trades`；A 股仍含 `trades`）、`ths-hkus-trades-panel-absent`（hk/us 详情页不出现成交明细面板）；`tests/ths-trades-tests.el:65`（先盘口后成交的位置断言）仍绿。
  - 依赖：任务2、任务5

- [ ] 任务7：测试夹具与既有断言修正
  - 文件：`/home/thomas/Workspace/emacs-ths/tests/ths-hkus-tests.el`（**扩充**夹具与其余用例，不重复创建；同一文件，任务1 建、任务7 扩，禁止并行编辑）、`/home/thomas/Workspace/emacs-ths/tests/ths-fixtures.el`（修改）、`/home/thomas/Workspace/emacs-ths/tests/ths-search-tests.el`（修改）、`/home/thomas/Workspace/emacs-ths/tests/ths-ranking-tests.el`（修改）、`/home/thomas/Workspace/emacs-ths/tests/ths-fund-ranking-tests.el`（修改）、`/home/thomas/Workspace/emacs-ths/tests/ths-live-check.el`（修改）
  - 步骤：
    - 扩充 `tests/ths-hkus-tests.el`（任务1 已建骨架）：把两轮探测的真实响应体整理成 defconst（腾讯 `hk00700` / `usAAPL` 报价、港股分时 4 列、美股 `usMinute` 3 列、港美日 K、新浪港股榜与美股榜首页），只留最小必要样本，逐条标注探测日期。
    - 改 `tests/ths-fixtures.el`：`ths-test--stocks`（`:3`）增港美样本；`ths-test--book`（`:36`，固定 5 档）按画像档数生成。
    - `tests/ths-search-tests.el`：把 `("00700" . "港股")` 从 deftest `ths-search-funds-require-trading-code-and-compatible-market`（`:41`）的输入样本中移除，`:56` 期望列表与 `(cl-every #'ths-data-fund-p rows)` 断言**保持不变**（理由见任务4 验收标准）；港美映射由新增 `ths-search-hk-us-symbols` 覆盖。
    - 改 `tests/ths-ranking-tests.el:284`：`("00700" 116)` 现位于 deftest `ths-ranking-stock-types-distinguish-identical-codes-in-different-markets` 的**拒绝列表**（`:283`-`:285` 断言 `ths-data--ranking-stock-symbol` 返回 nil）。改为：把它从拒绝列表移除、并入上方 `:276`-`:280` 的接受列表，断言 `(ths-data--ranking-stock-symbol "00700" 116)` → `"hk00700"`（注意是**两参数**函数；三参数的 `ths-data--ranking-symbol` 在 `universe` 为 `stock` 时委托前者）。`ths-ranking-mixed-universe-is-rejected-without-fabricating-ranks`（`:290`）的混类拒绝语义保持不变。
    - 改 `tests/ths-live-check.el`：`pending`（`:6`）与实际检查数同步；universe `dolist`（`:40`）加 `hkstock` / `usstock`；东财相关 job 输出标注 `skip（东财本机不可达）` 且不计入 `failed`。
    - **回归确认项（不得修改）**：`tests/ths-data-tests.el:128`（A 股 240 分钟）、`tests/ths-volume-tests.el:99` / `:119`（量/手）、`tests/ths-tests.el:31`（`"卖5"` / `"买5"`）——A 股语义与文案均不变，这些断言保持原样并必须继续通过；若实现后失败，说明 A 股路径被改坏，须修实现而不是改断言。
    - 修正 `tests/ths-fund-ranking-tests.el:212-239`（`ths-ranking-keyboard-cycle` 测试）：u 键循环从 3 态改 5 态后，期望序列改为 stock→etf→lof→hkstock→usstock→stock，并同步改写 `:239` 的最终期望值（原 `(should (eq 'stock ...))` 在第 3 次按 u 后的语义要按新顺序重算）。
    - 修正 `tests/ths-fund-ranking-tests.el:187-210`（按钮行布局断言）：排行榜第三行按钮由 5 个（A股/ETF/LOF/涨幅榜/成交额榜）扩为 7 个后，重算 44 列最小窗口下的行号与右缘约束；若 7 个按钮在 44 列放不下，则改为窄窗口隐藏「港股/美股」两按钮（此时断言回落到 5 按钮且需新增一条「窄窗口不显示港美按钮」的断言），并在 README 按键表注明。
  - 验收标准：`make check` 离线全绿（不触网）；`git diff --stat` 显示无用例被删除；新增用例数 ≥ 15；`tests/ths-fund-ranking-tests.el` 全量通过，且新增断言覆盖「44 列窄窗口按钮布局」与「u 键 5 态循环顺序」。
  - 依赖：任务2、任务3、任务4、任务5、任务6

- [ ] 任务8：文档与变更记录
  - 文件：`/home/thomas/Workspace/emacs-ths/README.md`（修改）、`/home/thomas/Workspace/emacs-ths/CHANGELOG.md`（创建）、`/home/thomas/Workspace/emacs-ths/openspec/tech-debt.md`（追加/核对）、`/home/thomas/Workspace/emacs-ths/openspec/decisions.md`（追加/核对）
  - 步骤：
    - 改 `README.md:152`-`:154`（`make check` / `make run` / `make live-check` 三行说明）与任务0 已落地的实际实现逐字对齐；功能列表补港美行情/分时/日 K/榜单；按键表补 `u` 五态；配置表补 `ths-data-symbols` 支持的 6 种前缀；数据来源表补腾讯港美端点与新浪港美榜单；已知限制写「港美 1 档盘口、无成交明细、东财本机不可达」。
    - 新建 `CHANGELOG.md`（Keep a Changelog 结构，首版 `Unreleased`：新增 港美行情/榜单/搜索、变更 市场画像表重构、新增 Makefile、限制 港美 1 档盘口）。
    - 核对并补充 `/home/thomas/Workspace/emacs-ths/openspec/tech-debt.md` 条目：东财 `push2` / `push2his` / `82.push2` / `88.push2` / `push2delay` 本机不可达（TLS 握手后 EOF，57 次仅 2 次偶发 200），导致 A 股成交明细功能失效、A 股榜单依赖新浪回退；附复现命令与发现日期。该文件已由 2026-10-22 工件迁移创建并含同名条目，此处只做核对与必要补充，不重复追加。
    - 在 `CHANGELOG.md` 中提及技术债条目位置（`openspec/tech-debt.md`）与本仓库 `openspec/` 结构的建立（工件迁移）。
    - 核对 `openspec/decisions.md`：确认迁移决策条目在，且把本次实现的关键架构决策（市场画像表作为单一事实来源、港美 1 档盘口与无成交明细的显式降级、后缀缺失直接走新浪兜底）各记一条（日期 + 决策 + 理由）。
  - 验收标准：`grep -c "push2" /home/thomas/Workspace/emacs-ths/openspec/tech-debt.md` ≥ 1；README 三目标说明与 `make -n check` / `make -n run` / `make -n live-check` 的实际命令行一致；`CHANGELOG.md` 结构符合 Keep a Changelog（`Unreleased` 段含 新增 / 变更 / 限制）。
  - 依赖：任务7

## 文档清单

| 文档 | 动作 | 内容要点 |
|---|---|---|
| `/home/thomas/Workspace/emacs-ths/README.md` | 必改 | `make` 三目标与实际行为一致，并补「`make check` 的依赖加载方式（`LOAD` 覆盖 + straight build 目录自动探测）」；功能列表与按键表（含 `u` 五态）补港美；配置项说明 6 种符号前缀；数据来源表补腾讯港美报价/分时/日 K 与新浪港美榜单；已知限制三条（1 档盘口、无成交明细、东财不可达） |
| `/home/thomas/Workspace/emacs-ths/CHANGELOG.md` | 新建 | Keep a Changelog：新增（港美行情/榜单/搜索/画像表）、变更（240 分钟硬编码 → 画像驱动）、修复（美股 f37 单位、港美 1 档盘口渲染）、已知限制 |
| `/home/thomas/Workspace/emacs-ths/openspec/tech-debt.md` | 追加/核对 | 东财 push2 域名族不可达的技术债条目（影响面：A 股成交明细失效、港美东财分支无法实网验证；复现命令；发现日期 2026-10-22）；该文件已在工件迁移时创建并含同名条目，任务8 只核对与补充 |
| `/home/thomas/Workspace/emacs-ths/openspec/decisions.md` | 已存在，追加/核对 | 记录 2026-10-22 工件迁移决策，以及实现期的架构决策（如编译门禁判据、画像表边界） |
| `/home/thomas/Workspace/emacs-ths/openspec/completed/` | 归档 | 本计划完成后把 `active/` 下的计划文件移入此处，保持 `active/` 只含进行中计划 |
| `/home/thomas/Workspace/emacs-ths/tests/ths-live-check.el` | 注释更新 | 头部 Commentary 说明新增港美检查项、东财项 skip 条件，以及 `make live-check` 需要网络 |

## 验证标准

| 级别 | 内容 | 命令 / 工具 | 通过判据 |
|---|---|---|---|
| L1 语法检查 | 全部改动 `.el` 的括号与严格字节编译 | `make check`（内部经 `scripts/compile-strict.el` 做严格编译，见任务0）；可选 `elisp_mcp_set_task verify` → `elisp_check_parens`（逐文件） | 括号全平衡；`scripts/compile-strict.el` 必须**按 `byte-compile-file` 返回值判失败并 `kill-emacs 1`**（`byte-compile-error-on-warn` 不抛 error、batch 退出码恒 0 两个陷阱）；字节编译零 error 零 warning；**验证后仓库内 `.elc` 数量为 0** |
| L2 功能验证 | 离线 ERT 全量（含新增 `tests/ths-hkus-tests.el` 与既有 11 个含 `ert-deftest` 的测试文件 + 1 个共享夹具 `tests/ths-fixtures.el` + 1 个非 ERT 的网络检查脚本 `tests/ths-live-check.el`，共 13 个文件 / 2399 行，124 个 ERT 用例） | `make check` | 全绿；基线为 124 tests / 0 unexpected；改造后新增用例 ≥ 15 且 0 unexpected；A 股回归用例 0 失败；无用例被删除或改 `:expected-result`；含「港美股不发起 trades 请求」的断言 |
| L3 真实接口 | 港美报价 / 分时 / 日 K（腾讯）、港美榜单（新浪）、指数（8 条） | `make live-check` | 腾讯港美报价非空且时间格式已归一；港股分时 4 列解析成功、美股 `usMinute` 3 列解析成功且点数被记录；港美日 K 各 ≥ 100 根；新浪港股榜 total=2492 级、美股榜 total=18300 级；东财相关项输出 `skip` 且退出码为 0 |
| L4 编辑器内冒烟 | 隔离实例 headless 加载并启动 THS，断言港美报价落地 | `elisp_mcp_set_task verify` → `elisp_eval_expression`（或 `eval_in_buffer`）加载 `ths.el` → `(ths)` → 断言 `ths-data-stocks` 中 `hk00700` / `usAAPL` 的 `:price` 为数字、`:market-label` 为 港股 / 美股 → `elisp_mcp_set_task auto` → `elisp_mcp_iso_stop` → `elisp_mcp_iso_status` 确认 `task=auto` | 两条断言均成立；收尾命令返回 `task=auto` 且隔离实例已停止 |

> 「不做汇率换算」的机械覆盖点：`ths-hkus-quote-amount-scale` 断言港美 `:amount` 倍数为 1（原币原值）、A 股为 10000（万元），即解析层不含任何币种换算系数；无需为该非目标另写专用断言。

## 风险与注意事项

1. **东财不可达 → 港美东财分支无法实测**：`ths-data--eastmoney-secid` 与港美东财报价/日 K 只能靠离线 fixture 覆盖，`make live-check` 里必须标 `skip` 而不是假绿。港美 secid 前缀（`116.` / `105.`~`107.`）来源是东财搜索返回的内部 market 字段，属推断，恢复可达性后需重测。
2. **美股日 K 后缀回填的竞态**：`usfqkline` 需要 `.OQ` 之类后缀，后缀只来自报价 f2，而报价与日 K 是两个独立异步请求。必须处理「报价未回时 chart 请求」的场景——要么先发 quote 再发 daily（串行），要么在 suffix 缺失时直接走新浪日 K 兜底，禁止拼 `usAAPL,day,,,120,qfq` 这类无后缀请求（实测只得 2 行残行，会污染缓存）。
3. **港美分时点数需 live-check 校准**：港股 330 分钟 / 331 点、美股 390 分钟 / 391 点（391 点为单次实测含端点、331 点由时段推出），点数均为待校准值。夏令时、半天市、临时休市都会改变实际点数。画像表里的 `:minutes` 取 elapsed 分钟数（港 330 / 美 390）只用于坐标缩放，点数只用于「数据是否完整」判断；务必保证「实际点数 ≠ 画像分钟数」时不报错、不越界（现有 `ths-chart.el` 的 `/240.0` 会画出空白区，改造后必须按实际最大值兜底）。
4. **港美只有 1 档盘口**：UI 不得显示伪造的 5 档。`ths-data--book-rows`（`ths-data.el:194`）的档序常量必须由画像驱动，任何「缺失档补 `--` 行」的写法都属伪造数据，直接违反「不生成替代数据」原则。
5. **港美股成交明细必须同时剪掉数据层请求**：只在详情页 UI 层隐藏面板不够——`ths--ensure-chart`（`ths.el:138` 定义，`:145` 三元分支）若仍把 `'trades` 放进请求列表（现为 `(if (ths-data-otc-p stock) '(quote) (list (plist-get state :chart) 'trades))`），港美股每 30s 会打一次必然失败的东财请求。改造必须在请求列表与渲染分支两层同时剪掉，并用 ERT 双向断言（hk/us 无 `trades`、A 股仍有）。另：A 股成交明细在本机因东财不可达已失效，属既有技术债（见任务8 的 tech-debt 条目），本计划不修复。
6. **A 股回归风险集中在固定长度 / 固定字段假设**：`ths-data-symbol-id`（`:58`）的 `(substring symbol 2)`、`ths-data-fund-p`（`:73`）的 `(= (length symbol) 8)`、`ths-data--quote-sina`（`:221`）的 `>= 32` 字段、`ths-data-minute-slot`（`:248`）的两段区间——任何一处改错都让 A 股静默降级。必须靠现有 2399 行测试兜底，且改动优先「加参数保留默认行为」而非重写。
7. **3 处既有断言与新增能力冲突**：`tests/ths-search-tests.el:56`（期望港股被丢弃）、`tests/ths-ranking-tests.el:284`（`("00700" 116)` 期望 nil）、`tests/ths-search-tests.el:54`（`("00700" . "港股")` 在拒绝集）——必须同步改写为「接受」而不是删除用例，否则等于取消护栏。
8. **qfq 日 K 的数组键名可能变化**：A 股路径读的是 `data.<symbol>.day`，但带 `qfq` 参数的港美端点（`fqkline` / `usfqkline`）键名可能是 `qfqday`。实现时须先打印一次响应结构再定键，不能沿用 A 股的 `"day"` 硬编码。**已实测确认（2026-10-22）**：美股 `usfqkline` 返回 `data["usAAPL.OQ"].qfqday`（120 行），港股 `fqkline` 在同样 `qfq` 参数下仍返回 `data["hk00700"].day`（121 行）；实现按「港美先读 `qfqday`、缺失再读 `day`，A 股只读 `day`」分派（`ths-data--tencent-candles`），并新增 `ths-data--node` 容忍美股 `data` 键的交易所后缀。
9. **美股指数符号与 `us` + 字母规范冲突**：`us.IXIC` / `us.INX` 含点号，符号正则必须允许点号（任务1 已含），且 `ths-data-symbol-id` 不能把点号当分隔符截断；`usDJI` 则无点号——两种形态都要在符号矩阵用例里覆盖。
10. **`u` 键循环从 3 态变 5 态属行为变更**：`tests/ths-fund-ranking-tests.el:217` 附近的键盘断言依赖「stock → etf → lof」顺序，需同步更新期望序列，并在 README 按键表写明新顺序。同源风险还包括 `tests/ths-fund-ranking-tests.el:187-210` 的按钮行布局断言（5 按钮 → 7 按钮/窄窗隐藏），两处必须在任务7 一并修正。
11. **测试文件不参与字节编译**：`make check` 只严格编译 7 个源文件；`tests/ths-trades-tests.el:101` 存在既存 free variable `buffer`（严格编译会失败），属既存噪声，不在本计划范围。若将来把测试纳入字节编译，需先给使用公共宏/辅助函数的测试文件补 `(require 'ths-tests nil t)` 并修该文件，否则 `-l` 与陈旧 `.elc` 混用会静默取到未展开宏的字节码。

## 后置事项

1. 东财 `push2` / `push2his` / `82.push2` / `88.push2` / `push2delay` 域名可达性恢复后，补测港美东财报价与日 K 分支（含 secid 前缀 `116.` / `105.`~`107.` 的正确性），并把 `make live-check` 里的 `skip` 改回真实检查。
2. 港美 5 档盘口与逐笔成交明细需付费源，本次明确不做；若后续引入付费源，按画像表新增 `:book-levels` / `:trades-supported` 两个属性即可，不改消费方。
3. 东财搜索返回的其它 `securityTypeName`（粉单 153、期货、期权、概念、债券）当前为非目标；若纳入，只需在搜索映射表加行 + 画像表加条目。
4. 东财不可达若确认为源站下线而非本机网络问题，考虑为 A 股成交明细增加替代源（新浪分笔或港美同源的其它公开端点），此事另立计划。
5. 港股与美股的半天市 / 夏令时日历若要做准，需要交易日历数据；当前只按固定时段处理，属已知精度缺口。
6. 港美股成交明细若未来出现可用数据源（如东财域名恢复），再评估是否纳入；当前明确不做。
