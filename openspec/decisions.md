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
