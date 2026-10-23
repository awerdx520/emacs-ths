# THS

在 Emacs 中查看 A 股、场内基金行情和场外基金净值、管理自选，以及浏览分类排行榜。基于 [ETAF](https://github.com/emacs-taf/etaf) 构建，支持鼠标操作和快捷键。

![THS 行情界面：股票列表、分时与成交量图、五档盘口及成交记录](preview/demo.png)

- 个股报价、三大指数与五档买卖盘。
- 分时图、日 K 和成交量副图；图形界面使用 SVG，终端使用字符图。
- 按名称或代码搜索股票、场内 ETF／LOF 和场外基金，添加、删除并保存自选。
- 场外基金单位／累计净值走势、日增长率和历史净值；货币基金万份收益／七日年化。
- A 股、ETF、LOF 分类排行榜，按涨幅或成交额排序，支持键盘选择和分页。
- 最近成交记录、定时刷新和数据源自动回退。
- 可选 AI 分析：按 `A` 为当前标的生成投机建议（评级／理由／风险／关键观察位），同时给出大盘盘面分析，结果在右侧窗口展示。

行情来自腾讯财经、东方财富和新浪财经的公开接口，无需 API Key。THS 提供行情展示，不包含交易功能。AI 分析是可选能力，需自行配置 gptel 或 OpenAI 兼容接口；行情数据本身仍无需任何密钥。

## 安装

以下配置使用 Emacs 30.1+ 内置 `use-package` 的 `:vc` 功能。需要安装 Git 和 curl，并确保 Emacs 能访问 GitHub 及行情服务。

请先安装 [ETAF](https://github.com/emacs-taf/etaf) 0.2.1+ 及其依赖，然后将以下 THS 配置加入初始化文件：

```elisp
(use-package ths
  :ensure nil
  :vc (:url "https://github.com/guidao/emacs-ths.git"
       :lisp-dir "."
       :main-file "ths.el"
       :rev :newest)
  :commands ths
  :init
  (setq ths-refresh-interval 30
        ths-data-ranking-providers '(eastmoney sina)))
```

THS 本身要求 Emacs 29.1+，上面的安装方式要求支持 `:vc` 的 `use-package`。

执行 `M-x ths` 打开界面，行情会在后台加载。使用 `M-x package-vc-upgrade-all` 更新通过 VC 安装的包，更新后重启 Emacs。

## 使用

第一行切换行情页和排行榜，第二行是可点击的快捷按钮，例如“刷新 r”“搜索 /”。点击按钮与按对应快捷键执行相同操作。

| 按键 | 操作 |
| --- | --- |
| `j` / `k` | 下一只／上一只股票；排行榜中移动选中行 |
| `TAB` / `S-TAB` | 移动控件焦点 |
| `RET` | 激活控件；在排行榜中打开股票详情 |
| `a` | 搜索并添加自选股 |
| `d` | 删除当前自选股 |
| `f` | 切换当前股票的自选状态 |
| `/` | 按代码、名称或本地行业标签筛选行情列表；留空清除 |
| `s` | 行情列表切换涨幅排序；排行榜切换涨幅／成交额 |
| `u` | 排行榜循环切换 A 股／ETF／LOF |
| `1` / `2` | 分时图／日 K；场外基金切换单位／累计净值，货币基金切换万份收益／七日年化 |
| `A` | 生成 AI 投机建议与盘面分析（右侧弹出，`q` 关闭） |
| `0` / `3` | 行情页／排行榜 |
| `n` / `p` | 下一页／上一页 |
| `r` | 刷新当前页面 |
| `T` | 切换亮色／暗色主题 |
| `g` | 重新适配窗口 |
| `q` | 退出当前窗口，保留会话和自动刷新 |

关闭 THS 缓冲区会停止定时刷新并取消请求。

默认使用暗色主题。按 `T` 或点击第二行的“主题 T”切换亮色，行情、排行榜、盘口及图表会一起更新，不影响当前选择和数据。窄窗口按钮显示为“主 T”。如需默认亮色，在配置中加入：

```elisp
(setq ths-theme 'light)
```

### 自选股

按 `a` 输入股票名称或部分代码，例如“茅台”“银行”“6005”。停顿后自动获取候选，按方向键选择、`RET` 添加。支持 Vertico，也可使用 Emacs 原生补全。

也可以直接输入六位股票代码，或带市场前缀的代码，例如 `sh600519`、`sz000001`、`bj920001`。在线搜索失败时仍可输入完整代码。

场内基金也通过 `a` 添加，例如 `510300`（沪市 ETF）、`159915`（深市 ETF）、`501018`（沪市 LOF）、`161725`（深市 LOF）。支持分时、日 K、成交量、五档盘口和最近成交记录；基金价格显示三位小数，接口缺失的数据显示为不可用。这里使用场内交易价格。

场外基金同样按 `a` 搜索名称或代码，选择标注“场外基金”的候选；也可以直接输入 `of005827`。`of` 前缀区分场外基金与同代码股票，例如 `of000001` 和 `sz000001` 可同时自选，六位代码直接输入仍按场内证券识别。

场外基金使用[天天基金](https://fund.eastmoney.com/)公布数据，显示四位小数、净值日期及最近 120 期走势；右侧显示基金信息和历史净值。按 `1`／`2` 切换单位／累计净值，货币基金则切换万份收益／七日年化。日增长率采用接口公布值，不根据分红前后净值简单相除。场外基金没有分时、日 K、盘口或成交量；数据是每日公布值，不是盘中估值，QDII 等基金的公布日期可能滞后。自动刷新每 15 分钟检查一次场外数据，`r` 可立即刷新，失败时保留上次数据。

自选默认保存在 `user-emacs-directory` 下的 `ths-watchlist.json`，每次增删立即保存。删除自选不会从当前会话的“全部”列表中移除股票。

### 排行榜

按 `3` 打开排行榜，点击第三行的「A股」「ETF」「LOF」或按 `u` 切换类别，按 `s` 切换涨幅榜和成交额榜。第二行保留快捷按钮。切换类别时保留排序方式，每个类别和排序组合会记住页码、可见段及选中项；回车打开对应股票或基金的行情。

类别筛选和排序由数据源服务端完成，与自选和行情列表筛选无关。三类榜单独立缓存，不混合股票、基金或指数。

表格按窗口宽度展示最新价、涨跌幅、成交量、成交额、流通市值、60 日涨跌幅和换手率。基金价格保留三位小数；基金窄屏优先展示价格和当前排序字段。接口每页 20 条；窗口较矮时分段显示，`n` / `p` 和 `j` / `k` 可以连续翻页，无需滚动。

默认先请求东方财富，失败后尝试备用节点和新浪。异常空榜也会触发回退。页面显示实际数据源；新浪暂不提供 60 日涨跌幅，该列显示 `--`。

### 图表与布局

分时图和日 K 下方均显示成交量，与价格共用时间轴。日 K 使用不复权价格；分时图的黄色线为分钟价格的累计算术平均，不是成交量加权均价。

建议使用图形版 Emacs 并启用 SVG 支持。窗口达到 136 列时展示股票列表、图表和盘口三栏；较窄窗口默认显示个股详情。高度充足时，盘口下方显示最近成交记录。界面随窗口和文字缩放调整，最低需要 44 列、20 行。

### AI 分析（可选）

AI 分析是本看板的可选能力，不安装、不配置时按 `A` 只会提示“未配置 AI 后端”，其它功能不受影响。

**定位与免责。** 分析仅基于本看板已有的行情快照：报价、分时、日 K、五档盘口、最近成交记录和三大指数，**不包含**新闻、公告、财务和资金流数据。因此结论是技术性观察，**不构成投资建议**，也不提供仓位、买卖指令或目标价。

**发送范围。** 发往模型的内容只有下列字段：

- 个股分析：该标的的代码、名称、行业，以及报价、分时、日 K、五档盘口与最近成交记录；
- 盘面分析：指数报价、涨跌家数、平均涨跌幅、合计成交额，以及自选池最强／最弱个股的**涨跌幅（不含名称）**；
- 自选池少于 3 只时不发送合计成交额与最强／最弱幅度，避免聚合值反推单只标的；
- 不发送自选文件名、文件路径或其它个人数据。

**触发方式。** 按 `A`，或点击详情面板的“AI 分析 A”按钮。分析只在手动触发时请求，不随 `r` 刷新或自动刷新产生费用。同一标的在 600 秒内且行情签名未变化时直接复用缓存结果；`C-u A` 取消在途请求、忽略缓存并强制刷新；相同标的的请求进行中不会重复发起。

**展示。** 详情面板在图表下方、报价来源行上方显示一行摘要（评级 · 置信度 · 观察位，按面板宽度截断）。完整报告（org 模式、只读）写入 `*THS 分析*` 缓冲区，以右侧侧边窗口弹出并取得焦点；按 `q` 关闭窗口后看板恢复原宽度并重新布局。报告不会自动写入磁盘。

**配色与退出。** 报告 buffer 的配色由 `ths-theme` 驱动，与看板取同一套调色板（背景、前景、标题、代码块、表格与 link），两块界面明暗一致；按 `T` 切换主题后报告 buffer 同步刷新，不需要重新生成。关闭报告用 `q` 或 `C-c C-q`，evil normal state 下同样生效；键绑定只写进报告 buffer 自己的键表，不会改动其它 org buffer 的 `C-c C-q`（`org-set-tags-command`）。

**报告安全。** 模型返回的文本按纯文本对待：报告中来自模型文本的 `elisp:` / `shell:` / `file:` 等危险链接会被改写为普通文本（连括号与裸写的 plain link 都算），同时报告 buffer 内禁用 `elisp` / `shell` 两类链接的确认执行；`https` 链接保留可用。`#+` 开头的指令行会被转义，因此模型无法在报告里注入 Org 关键字。

**两种后端（二选一，默认优先 gptel）。**

| 通道 | 需要做什么 | 说明 |
| --- | --- | --- |
| `gptel` | 安装并配置好 `gptel` 及其可用后端 | THS 不额外管理模型和密钥，直接复用 gptel 的配置 |
| 内置 OpenAI 兼容 HTTP | 设置 `ths-ai-http-url` 与 `ths-ai-http-model`，并提供密钥 | 密钥从 `ths-ai-http-key-env` 指定的环境变量读取，未命中时回落到 `ths-ai-http-key-auth-source` |

`ths-ai-provider` 默认 `auto`：有可用的 gptel 就用 gptel，否则回落到 HTTP 通道。HTTP 通道的密钥只从环境变量（默认 `OPENAI_API_KEY`）或 `auth-source` 读取，**不写入任何配置文件**，也不会出现在报告、日志或命令行参数里，请求期间会关闭 `http` 类 URL 调试输出（当 `url-debug` 为 `t` 或整数时等于全部关闭）。

**代理环境。** 若 Emacs 通过 HTTP 代理访问网络，DeepSeek 的请求由 gptel backend 自行直连：该 backend 注册时带 `:curl-args '("--noproxy" "api.deepseek.com")`，其 curl 命令行因此带 `--noproxy api.deepseek.com`。原因：gptel 用 curl `-D-` 时把 stdout 首行当作响应状态行，而代理 CONNECT 的应答 `HTTP/1.1 200 Connection established` 会被当成响应首行，请求因此被误判失败。代理排除只作用于该 backend 的 curl 子进程，不改动 Emacs 全局 `process-environment`。

内置 HTTP 通道**仅支持 `https://` 端点**，非 HTTPS 端点会被直接拒绝；证书校验失败即报错，3xx 重定向一律拒绝（不跟随，避免带同一把密钥二次请求别的 host），请求不携带 cookie；响应体**解析前**按字节上限 1 MiB，超限丢弃，下载阶段不设硬上限；gptel 通道的传输与校验由 gptel 自身决定。

**输出契约。** 个股分析返回评级（看多／偏多／中性／偏空／看空五档之一）、置信度（0–1）、理由（提示词要求「3 条为佳，至少 1 条」，代码只校验非空）、风险项、关键观察位（支撑／压力）和一句话摘要；盘面分析返回盘面结论、涨跌分布与亮点。模型未按契约输出时，面板显示失败原因并保留上一次的报告内容。

**依赖说明。** `gptel` 不是硬依赖，不进入 `Package-Requires`；未安装 `gptel` 且未配置 HTTP 通道时，按 `A` 只会提示“未配置 AI 后端”。

## 配置

在 `use-package ths` 的 `:init` 中设置选项，例如：

```elisp
(setq ths-data-providers '(tencent eastmoney sina)
      ths-data-ranking-providers '(sina eastmoney)
      ths-data-symbols '("sh600519" "sz000001" "sz300750")
      ths-refresh-interval 30
      ths-data-timeout 10)
```

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `ths-data-providers` | `(tencent eastmoney sina)` | 个股报价来源顺序；图表跳过新浪 |
| `ths-data-ranking-providers` | `(eastmoney sina)` | 排行榜来源顺序，独立于个股报价 |
| `ths-data-symbols` | 内置 8 支股票 | 初始行情列表，代码必须包含 `sh`、`sz` 或 `bj` 前缀 |
| `ths-refresh-interval` | `30` | 自动刷新间隔，单位秒，最短 5 秒；`nil` 关闭自动刷新 |
| `ths-data-timeout` | `10` | 每次 HTTP 请求的超时秒数 |
| `ths-auto-fetch` | `t` | 是否自动获取数据；`nil` 时仍可按 `r` 刷新 |
| `ths-data-curl-program` | `"curl"` | curl 命令名或绝对路径 |
| `ths-watchlist-file` | `user-emacs-directory` 下的 `ths-watchlist.json` | 自选保存位置；`nil` 表示仅保留在当前会话 |

更改来源顺序后按 `r` 生效。更改初始股票、自动刷新或自选文件设置后，关闭 THS 缓冲区并重新执行 `M-x ths`。

以下选项属于 `ths-ai` group，仅在首次使用 AI 分析前设置一次即可。

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `ths-ai-provider` | `auto` | 后端选择：`auto` 优先 gptel、否则用 HTTP；`gptel` / `http` 强制单一通道 |
| `ths-ai-http-url` | `nil` | OpenAI 兼容的 chat completions 端点；`nil` 表示 HTTP 通道未配置 |
| `ths-ai-http-model` | `nil` | 发送给 `ths-ai-http-url` 的模型名 |
| `ths-ai-http-key-env` | `"OPENAI_API_KEY"` | 存放 HTTP 通道密钥的环境变量名；请求时才读取，不缓存、不落盘 |
| `ths-ai-http-key-auth-source` | `nil` | 可选的 `(HOST . USER)`；环境变量无可用密钥时回落到 `auth-source` |
| `ths-ai-timeout` | `60` | 在途 AI 请求的超时秒数 |
| `ths-ai-cache-seconds` | `600` | 分析结果的有效期，单位秒；期内且行情签名未变时复用缓存 |
| `ths-ai-language` | `"中文"` | 要求模型使用的回答语言，会插入系统提示词 |

## 数据来源

| 数据 | 来源 | 说明 |
| --- | --- | --- |
| 股票、场内基金、指数报价与五档盘口 | 腾讯、东方财富、新浪 | 按配置顺序回退 |
| 分时与日 K | 腾讯、东方财富 | 包含成交量；日 K 不复权 |
| 分类排行 | 东方财富、新浪 | A 股／ETF／LOF，按涨幅或成交额降序 |
| 最近成交记录 | 东方财富 | 最近最多 12 条快照，不累计完整成交历史 |
| 自选搜索 | 东方财富 | 按名称或代码检索沪深京 A 股及场内 ETF、LOF |
| AI 分析（可选） | 用户自备（gptel 或 OpenAI 兼容接口） | 个股分析发送该标的的代码、名称、行业与行情快照；盘面分析只发送聚合统计（指数报价、涨跌家数、平均涨跌幅、合计成交额、自选池最强／最弱个股涨跌幅，**不含名称**）；不发送自选文件名、文件路径或其它个人数据；结果缓存于内存，不落盘 |

价格和成交额统一为元，成交量统一为手（股票 100 股、基金 100 份），流通市值按万／亿元展示。缺失字段显示 `--`；请求失败时保留同一证券或同类别榜单的上次成功数据并标记错误，不生成替代行情。

公开接口可能限流或变更。非交易时段可能返回上一交易日数据，“采集时间”表示接收数据的时间。成交记录属于分时成交快照，不是完整的 Level-2 逐笔流。

接口字段参考 [AKShare](https://github.com/akfamily/akshare) 和 [efinance](https://github.com/Micro-sheep/efinance) 的公开实现。

## 开发

确认 ETAF 及其依赖已安装，再检出 THS 源码：

```sh
git clone https://github.com/guidao/emacs-ths.git
cd emacs-ths
make check
```

以上源码检出用于开发和测试；日常安装使用前面的 `use-package :vc` 配置。

| 命令 | 作用 |
| --- | --- |
| `make check` | 严格字节编译 + 离线 ERT（自动排除 3 个已知的无 GUI 环境基线失败） |
| `make check-all` | 离线 ERT 全量，含已知基线失败（预期非零，用于观察基线） |
| `make run` | 从当前源码启动干净的 Emacs 并打开 THS |
| `make live-check` | 检查真实行情接口，需要网络；任一检查失败返回非零状态 |
| `make compile` / `make test` / `make clean` | 只做严格编译 / 只跑离线 ERT / 清理 `*.elc` |

`make check` 排除的 3 个基线失败是无 GUI 环境下的夹具断言问题，与改动无关：
`ths-fixture-charts-and-book-have-consistent-bounds`、
`ths-volume-dashboard-shows-both-panels-without-growing-page`、
`ths-volume-terminal-charts-preserve-height-and-column-width`。需要完整口径时用 `make check-all`；
`make help` 列出全部目标。

仓库不附带依赖源码。Makefile 通过 `package-initialize` 加载用户已安装的依赖，不读取用户的初始化文件，也不自动安装依赖；THS 使用当前检出的源码。可通过 `EMACS` 指定 Emacs 可执行文件，通过 `LOAD` 覆盖加载参数；依赖由 straight 安装、`package-initialize` 找不到时，用 `STRAIGHT_BUILD` 指定 straight build 目录（如 `make check STRAIGHT_BUILD=~/.emacs.d/straight/build-31.1`）。不经过 Make 时也可直接运行 `tests/run-offline.sh`（`--all` 含已知基线失败，`--selector REGEXP` 只跑名字匹配的用例）。离线测试使用独立样本和临时自选文件，不读取或修改个人自选。

图形布局测试位于 [tests/ths-gui-tests.el](tests/ths-gui-tests.el)：在图形版 Emacs 中加载该文件，再执行 `M-x ert RET ths-gui-chart-geometry RET`。

主要模块：

| 文件 | 职责 |
| --- | --- |
| [ths.el](ths.el) | 界面、状态与交互 |
| [ths-data.el](ths-data.el) | 数据源、异步请求、解析与失败回退 |
| [ths-chart.el](ths-chart.el) | SVG 与字符图表 |
| [ths-ai.el](ths-ai.el) | AI 分析：事实组装、提示词、解析、传输与编排 |
| [ths-watchlist.el](ths-watchlist.el) | 自选股持久化 |
| [ths-search.el](ths-search.el) | 异步搜索与补全 |

欢迎提交 Issue 和 Pull Request。报告问题时请附 Emacs 版本、图形／终端环境、复现步骤，以及页面显示的错误；界面问题可附截图和窗口尺寸。

## 许可证

[GPL-3.0-or-later](LICENSE)。
