# 变更日志

本项目所有值得注意的变更都会记录在此文件。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 新增

- AI 分析（可选）：按 `A` 为当前标的生成投机建议（评级／置信度／理由／风险／关键观察位），并附大盘盘面分析；详情面板显示一行摘要，完整报告在右侧侧边窗口（`*THS 分析*`，org 模式，`q` 关闭）。
- 双通道后端：优先复用 `gptel`（软依赖，不写入 `Package-Requires`），否则使用内置 OpenAI 兼容 HTTP 通道（`url-retrieve` 异步 POST，密钥只从环境变量或 `auth-source` 读取）。
- 结果缓存与去重：同一标的 600 秒内且行情签名未变时复用缓存，`C-u A` 强制刷新；请求进行中不重复发起。
- 新增 `ths-ai` 自定义组与 8 个选项：`ths-ai-provider`、`ths-ai-http-url`、`ths-ai-http-model`、`ths-ai-http-key-env`、`ths-ai-http-key-auth-source`、`ths-ai-timeout`、`ths-ai-cache-seconds`、`ths-ai-language`。
- AI 报告 buffer 的配色跟随 THS 主题（背景／前景／标题／代码块／表格／link 均取 `ths-theme` 调色板），与看板一致，按 `T` 切换主题时同步刷新。
- AI 报告 buffer 支持 `q` 与 `C-c C-q` 退出（evil normal state 下同样生效），键绑定只作用于报告 buffer，不污染其它 org buffer。

### 变更

- 详情面板在图表与报价来源行之间新增一行 AI 摘要与「AI 分析 A」按钮，图表区行数预算相应调整（`chart-rows` 常数 7 → 8），布局外观不变。
- `ths--stop` 在关闭看板时取消挂起的 AI 请求并清空结果缓存（不关闭已打开的分析报告窗口）。
- gptel 的 DeepSeek backend 改用 `--noproxy api.deepseek.com` 直连：gptel 以 curl stdout 首行作为响应状态，HTTP 代理 CONNECT 的 `HTTP/1.1 200 Connection established` 会被当成响应行，导致请求被误判失败。代理排除只作用于该 backend 的 curl 子进程，Emacs 全局 `process-environment` 不变。

### 安全

- 盘面分析只外发聚合统计，不再包含自选池个股名称；自选池少于 3 只时不发合计成交额与最强／最弱幅度。
- 内置 HTTP 通道强制 `https://` 并启用证书校验失败即报错；请求禁用 cookie；响应体解析前按字节上限 1 MiB（下载阶段不设硬上限）；3xx 重定向一律拒绝。
- 供应商字段（含 `:code`／`:time`／`:intraday-date`／指数名称）提交前折叠控制字符并截断；模型输出写入 org 报告前中和全文 `[[` 链接、转义行首 `#+`/`#|`，并抑制 org 启动视觉副作用（`#+` 关键字由转义拦截）。
- 密钥含控制字符视为非法，不发送请求。
