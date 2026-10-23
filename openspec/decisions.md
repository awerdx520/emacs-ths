# 架构决策日志

记录 THS 项目的重大架构决策，格式为「日期 + 决策 + 理由」。

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
