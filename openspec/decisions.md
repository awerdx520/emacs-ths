# 架构决策日志

记录 THS 项目的重大架构决策，格式为「日期 + 决策 + 理由」。

## 2026-10-22 — 港美股计划工件从 thomas-emacs 迁入 emacs-ths 仓库

- **决策**：在 emacs-ths 仓库根新建完整 `openspec/`（`active/`、`completed/`、`decisions.md`、`tech-debt.md`）；原 `~/thomas-emacs/openspec/active/2026-10-22-emacs-ths-hk-us-support.md` 降级为指针文件（保留迁移说明，不再承载计划正文）。
- **理由**：① 计划的全部改造对象（7 个源文件、13 个测试文件、README、CHANGELOG）都在本仓库，跨仓库跟踪会导致行号锚点与文档清单持续漂移；② 覆盖到的文档也在本仓库，Phase 4 文档沉淀无法跨仓库执行；③ thomas-emacs 仅保留 ths 作为 straight 包的安装与键位配置，不承载实现细节。参见 `~/thomas-emacs/openspec/decisions.md` 的 2026-10-22「A股看盘包由 achive 完全替换为 ths」条目。
- **配套调整**：原计划任务8 中的 `thomas-emacs/openspec/tech-debt.md` 条目改为本仓库 `openspec/tech-debt.md`；验证入口（Makefile + 严格编译驱动 + ERT runner）由任务8 前置为任务0（基线门禁无法在无入口时执行）。

## 2026-10-22 AI 分析采用双通道接入（gptel 软依赖优先 / 内置 HTTP 回退）

- 决策：新增 `ths-ai.el`，按 `ths-ai-provider` 分派：`auto` 时若 `(require 'gptel nil t)` 成功且 `gptel-request` 可用则走 gptel，否则走内置 OpenAI 兼容 HTTP；gptel 不写入 `Package-Requires`。
- 理由：用户已在本机配置 gptel 与凭据，复用可免去密钥与模型管理；同时保持项目"无外部包强依赖"的定位，未装 gptel 的用户仍可用 HTTP 通道。
- 备选与放弃原因：仅 gptel（强制第三方依赖，违背项目零依赖定位）；仅内置 HTTP（丢弃用户已配置的 gptel、需重复管理密钥）；纯本地规则分析（用户要求自然语言分析，规则无法满足）。

## 2026-10-22 HTTP 通道使用 url-retrieve 而非项目既有的 curl 模式

- 决策：`ths-ai--http-request` 使用内置 `url-retrieve` 异步 POST，不沿用 `ths-data--http` 的 curl 方案。
- 理由：curl 需通过 `--header "Authorization: ..."` 传密钥，会暴露在进程 argv（`ps` 可见），违反密钥保护要求；且本通道需要 POST + JSON body，curl 需临时文件或 stdin 双通道，复杂度更高。
- 代价：与 `ths-data--http` 的 curl 风格有意偏离；HTTP 通道的错误处理与超时逻辑需独立实现。

## 2026-10-22 不向 gptel 传 :schema，改用提示词内建 JSON 契约

- 决策：`gptel-request` 调用只使用 `:callback` / `:system` / `:buffer` / `:context` 等稳定参数，不传 `:schema`。
- 理由：gptel 文档明确标注 SCHEMA 为实验性、且并非所有 provider 支持结构化输出；改用提示词内建 JSON 契约 + 容错解析（剥围栏、截取花括号区间、字段校验），跨 provider 与跨版本更稳定。
- 代价：输出合法性依赖模型遵循度，需解析层兜底与失败降级。

## 2026-10-22 AI 报告对危险 org 链接采用「改写 + 拒绝确认」两层防护

- 决策：模型输出写入 `*THS 分析*` 前，先把 `elisp`/`shell`/`file`/`data`/`ftp` 等危险 scheme 的 `:` 改写为 ` :`（`https`/`http` 保留），并在报告 buffer 内把 `org-confirm-*` 系列设为拒绝执行。
- 理由：实测 org 除 bracket link 外还识别 plain link（`[ [shell:rm -rf ~]]` 仍解析为 `shell` 型 plain link），仅中和 `[[` 不足以消除"可点击执行"的面；而括号中和在奇数个连续 `[` 时不收敛（`[[[elisp:…` → `[ [[elisp:…`），必须循环到不动点。
- 备选与放弃原因：只做 `[[` 中和（plain link 仍可跟随）；把报告 buffer 设为非 org 模式（降低可读性，且用户需要 org 折叠与导出）；不改写正文只靠 confirm 拒绝（用户可手动重跑 major mode 使防护回落为"询问"，纵深过薄）。

## 2026-10-23 代理排除放在 gptel backend 层，而非修改 Emacs 全局环境

- 决策：DeepSeek 的 `gptel-make-deepseek` 注册时加 `:curl-args '("--noproxy" "api.deepseek.com")`，不改 `process-environment` 里的全局 `no_proxy`。
- 理由：gptel 以 curl stdout 首行作为 `info :status`，带 `-D-` 时代理 CONNECT 的应答 `HTTP/1.1 200 Connection established` 会被当成响应行，请求因此被误判失败。把 `--noproxy` 放进该 backend 的 curl 参数，影响面只限这条 curl 子进程；全局 `no_proxy` 会波及 ECA 等其它走 curl 的子进程，改变它们本已正常的代理行为。
- 备选与放弃原因：全局设 `no_proxy`（影响所有子进程，且需在每次会话重建）；改 gptel 上游（跨仓库、升级即失效）；让 THS 自带 HTTP 通道绕开 gptel（丢失用户已配置的 backend 与凭据复用）。

## 2026-10-23 报告 buffer 用「buffer 局部键表 + `use-local-map`」而非 `local-set-key`

- 决策：`ths-ai--bind-report-keys` 以当前 `current-local-map` 为父键表新建稀疏键表，把 `q` / `C-c C-q` 写进新键表后 `use-local-map`。
- 理由：实测 org buffer 的 `current-local-map` 就是全 buffer 共享的 `org-mode-map`，`local-set-key` 会把绑定写进共享对象，污染用户所有 org buffer（`C-c C-q` 会顶掉 `org-set-tags-command`）。另建 buffer 局部键表后，覆盖只在本 buffer 生效，且父键表保留 org 的其余绑定。
- 备选与放弃原因：`local-set-key`（污染共享 `org-mode-map`）；用 `minor-mode-map-alist` 挂一个临时 minor mode（为一两个键引入模式状态，还要处理开关与清理）；把报告 buffer 改成非 org 模式（牺牲折叠与导出）。

## 2026-10-23 evil binding 就地 `define-key` 现有 buffer-local state map

- 决策：`evil-normal-state-local-map` 已是键表时直接 `define-key` 就地加键；仅当该 map 尚未建立时用 `evil-local-set-key` 交由 evil 创建并登记；两者都不可用时退回 `setq-local` 造新 map（仅在测试环境可达）。
- 理由：evil 按 map 对象身份把 state map 登记进 `emulation-mode-map-alists`，`copy-keymap` + `setq-local` 换掉对象后登记项仍指向旧对象，`q` 依然命中全局 `evil-normal-state-map` 的 `evil-record-macro`（Evil 1.15 实测：改对象后 `key-binding` 仍返回 `evil-record-macro`，就地 `define-key` 立刻返回本命令）。就地加键同时天然保住 evil-org 注入的 org 导航键，不会整体替换既有绑定。
- 备选与放弃原因：`copy-keymap` + `setq-local`（登记失配，绑定不生效）；统一走 `evil-local-set-key`（buffer-local state map 已存在时它按对象身份登记，语义等价但多一层间接，且 map 已存在时无需重建）。

## 2026-10-23 市场画像表 `ths-data-markets` 作为港美能力的单一事实来源

- 决策：在 `ths-data.el` 定义 `ths-data-markets`，把市场事实全部收进属性列表：符号前缀、显示名（`沪A`／`深A`／`京A`／`沪基`／`深基`／`港股`／`美股`，指数另用 `港股指数`／`美股指数`）、小数位、成交量单位（`手`／`股`）、币种、盘口档数、分时分钟数与会话区间、成交额换算系数 `amount-scale`、腾讯 secid 前缀、时间戳形态、是否有成交明细、是否画均价线，以及各 kind 的 provider 顺序。消费方一律经 `ths-data-market` 取事实：`ths-data--url` 选端点、`ths-data--providers` 定回退链、`ths-data-volume-unit` 与 `ths-chart--volume-unit` 定单位与图注、`ths--ranking-columns` 决定港美不出现流通市值与 60 日涨跌幅列、`ths-data-market-label` 出市场名。
- 理由：港美同时打破了「240 分钟」「5 档盘口」「手」「元」四个 A 股假设，消费点分布在 `ths-data.el`／`ths-chart.el`／`ths.el` 三处。若各处就近判断前缀，新增一个市场要改 N 处，测试夹具极易只覆盖一半（单位改了、图注没改）。单表还让「港美只有 1 档」「无成交明细」这类降级成为**数据**而非散落的 `if`。
- 备选与放弃原因：各模块内 `string-prefix-p "hk"` 就地判断（改一处不生效、口径漂移，且无法被单个 ERT 用例统一断言）；按 kind 建 alist 但不含展示字段（市场名、单位、小数位仍散落，`ths-data-market-label` 类逻辑无处安放）；把画像做成 defcustom（用户可改市场事实会让符号校验、端点拼接与解析字段数互相失配——这些事实由接口协议决定，不是偏好）。

## 2026-10-23 港美股显式降级：按实际 1 档盘口渲染、不发 trades 请求、不补伪造档位

- 决策：港美画像 `:book-levels 1`、`:trades nil`。盘口由 `ths-data--book-rows` 按 `:book-levels` 生成行（1 档即买一／卖一）；`ths-data-fetch` 在 `kind=trades` 且画像无 `:trades` 时直接回调「该市场不提供成交明细」，**不构造 URL、不发请求**；`ths--trades-p` 让详情页与右侧栏都不渲染成交面板；港股挂单量字段接口不给值，显示为 0。
- 理由：港美接口的事实就是买一／卖一与无逐笔成交。渲染 5 档要么伪造空档，要么把「接口没有」显示成「暂无数据」，两种都会让用户以为行情不完整只是暂时的。按实际档数渲染、请求与事实一致，也避免每次刷新多发一次必然失败的东财 trades 请求。
- 备选与放弃原因：补 `--` 行填满 5 档（伪造档位，与 A 股视觉无差别，误导用户以为有深度数据）；保留面板显示「暂无」（空面板仍要占详情页行数预算，且暗示该功能存在）；港美直接隐藏整个右侧栏（详情页仍需要买一／卖一与量价信息，隐藏侧栏反而丢信息）；只在**前端**把 5 档截断为 1 档显示（请求与解析仍按 5 档走，字段缺失处依旧要造值，问题只是被藏起来）。

## 2026-10-23 美股日 K 后缀缺失时直接走新浪兜底，不做「先 quote 后 daily」两阶段编排

- 决策：美股日 K 的腾讯端点需要交易所后缀（`AAPL` → `AAPL.OQ`），该后缀来自上一条腾讯报价的 `:exchange-suffix`。`ths-data--providers` 对 `us` + `daily` 判断后缀是否存在：有则 `(tencent sina)`，无则 `(sina)`——直接跳过腾讯、用新浪日 K 补齐；`ths-data--url` 在无后缀时 `error`，不拼无后缀 URL。
- 理由：实测无后缀的 `usfqkline` 请求返回两行残缺数据，比失败更糟（会被当成功写进缓存）。改成「先确保 quote 再发 daily」会把单 kind 的 provider 回退链变成依赖另一 kind 结果的异步状态机：quote 在途／失败／过期、缓存代次与 `ths-data-fetch` 的 `generation` 计数都要联动，而收益只是「可能用上腾讯」。
- 备选与放弃原因：两阶段编排（先 quote 后 daily，等后缀就绪再请求；引入跨 kind 依赖与竞态，现有 `generation` 机制只覆盖单 kind 的重入）；发无后缀请求再按残行数判失败重试（先把坏数据带进解析路径，判据还依赖「恰好两行」这一脆弱特征）；把交易所后缀硬编码进代码表（东财搜索响应只给内部 market 号 105/106/107，腾讯后缀是唯一实网可靠来源，硬编码在新代码上必失败）；只允许在已有 quote 缓存时请求日 K（用户按 `2` 时可能尚无报价，功能直接不可用）。

## 2026-10-23 `make compile` 改用 `scripts/compile-strict.el`，不再直接 `-f batch-byte-compile`

- 决策：`Makefile` 的 `compile` 目标改为 `-l scripts/compile-strict.el -- $(SOURCES)`。脚本逐个 `byte-compile-file`，按返回值判失败、复核 `.elc` 是否真的生成，任一 warning／error 即 `kill-emacs 1`；`.elc` 经 `byte-compile-dest-file-function` 重定向到临时目录，`unwind-protect` 保证成功、失败、异常三条路径都清理。源文件清单由 Makefile 传参（`SOURCES`，8 个文件），脚本缺省清单与之一致，避免两份清单漂移。
- 理由：`-f batch-byte-compile` 是**命令**，返回值被丢弃；`byte-compile-error-on-warn` 为 t 时遇 warning 只让 `byte-compile-file` 返回 `nil` 且不写 `.elc`，而 `emacs --batch` 的退出码恒为 0（实测 GNU Emacs 31.1）。两道机制叠加使 `make compile` 长期假绿，门禁只能由脚本按返回值判失败并显式非零退出。
- 备选与放弃原因：`-f batch-byte-compile` 之后用 `--eval` 猜退出码（拿不到逐文件返回值，batch 下失败已被吞，无处可判）；把编译循环内联成一行 `--eval`（不可维护，报错没有文件名清单）；保留漏判、改在 CI 里 grep `*Compile-Log*` 兜底（日志格式随 Emacs 版本变化，本地 `make compile` 仍假绿）。
