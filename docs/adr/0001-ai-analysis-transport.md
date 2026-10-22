# ADR 0001：AI 分析的传输与依赖策略

- 状态：已接受（2026-10-22）
- 决策者：项目维护者 + Plan Agent
- 相关计划：`openspec/active/2026-10-22-ths-ai-analysis.md`

## 背景

THS 目前是纯行情展示项目：数据层 `ths-data.el` 用 curl 异步拉取公开行情接口，UI 层基于 ETAF 响应式渲染，除 `etaf` 外无外部包依赖，README 明确"无需 API Key"。需求要求在保持这一形态的前提下新增「AI 投机建议 + 大盘盘面分析」。

约束：
1. 输入只能来自本地已有行情快照（报价 / 分时 / 日 K / 五档 / 成交记录 / 指数），不新增数据源。
2. 输出必须是结构化 JSON（评级 + 置信度 + 理由 + 风险 + 观察位），便于面板摘要与报告渲染。
3. 请求必须异步，不阻塞 ETAF 渲染与用户输入。
4. 不得泄露 API 凭据。

## 决策

1. **双通道，gptel 优先**：`ths-ai-provider` 为 `auto` 时，若 `(require 'gptel nil t)` 成功且 `gptel-request` 可调用，则复用 gptel；否则走内置 OpenAI 兼容 HTTP。gptel 仅作软依赖，不进入 `Package-Requires`。
2. **HTTP 通道用内置 `url-retrieve`**：异步 POST，`Authorization` 头由 `url-request-extra-headers` 传递，密钥只从环境变量或 auth-source 读取。
3. **单次请求只处理一个分析对象**：个股与大盘盘面各发一次请求，分别缓存与降级。
4. **不依赖 gptel 的 `:schema`**：JSON 契约写在 system prompt 内，解析层做容错与校验。

## 备选方案

| 方案 | 放弃原因 |
|---|---|
| 仅依赖 gptel | 强迫所有用户安装第三方包，违背项目零依赖定位；未配置 gptel 时功能直接不可用 |
| 仅内置 HTTP | 丢弃用户已配置的 gptel 与凭据管理，重复造轮子；用户已明确要求复用 gptel |
| 纯本地规则算法（不接 LLM） | 无法产出自然语言分析与解释，用户明确要求 AI 分析 |
| HTTP 走 curl（沿用 `ths-data--http`） | `Authorization` 头会出现在进程 argv，`ps` 可见，违反密钥保护；POST + JSON body 还需临时文件 |
| 传 gptel `:schema` 强制结构化输出 | 文档标注实验性且非所有 provider 支持，脆弱 |

## 后果

正面：功能可用面最大（有 gptel 用 gptel，无 gptel 用 HTTP）；核心纯函数可离线单测（事实组装、提示词、解析、渲染均不触网）；密钥不出现在进程参数中。

负面：两条传输路径需各自维护超时与错误处理；JSON 合法性依赖模型遵循度，需解析层兜底并把失败降级为"面板显示错误 + 报告保留上次结果"；`ths-data--http` 与 `ths-ai--http-request` 风格不一致，需在代码注释中说明理由。
