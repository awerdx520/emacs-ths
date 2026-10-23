# 技术债

| 日期 | 位置 | 描述 | 影响 | 建议 |
|---|---|---|---|---|
| 2026-10-23 | `README.md`「开发」节、`tests/ths-live-check.el`、`tests/ths-gui-tests.el` 注释 | **已解决（2026-10-23）**：文档引用的 `make check` / `make run` / `make live-check` 现已由仓库根的 `Makefile` 提供（另含 `compile` / `test` / `check-all` / `clean` / `help`） | 开发者无法按文档验证；agent 需手写 `emacs -Q --batch` 命令，易与文档漂移 | 已补 `Makefile`（check / check-all / compile / test / live-check / run / clean / help） |
| 2026-10-22 | `tests/ths-tests.el` 的 `ths-fixture-charts-and-book-have-consistent-bounds`；`tests/ths-volume-tests.el` 的 `ths-volume-dashboard-shows-both-panels-without-growing-page`、`ths-volume-terminal-charts-preserve-height-and-column-width` | **已解决（2026-10-23，`LOCALE_ENV=C.UTF-8`）**：该 3 例是宽字符显示宽度断言，固定 locale 后转绿。原描述：基线测试红（3 例）：干净检出的仓库上即失败。11 文件全量离线套件实测 `Ran 144, 141 expected, 3 unexpected`，与是否加载 `tests/ths-ai-tests.el` 无关（不加载时 `Ran 123, 120 expected, 3 unexpected`，同一 3 例）；`ths-fixture-charts-and-book-have-consistent-bounds` 单独跑 `tests/ths-tests.el` 亦为 `Ran 14, 13 expected, 1 unexpected` | 全量 ERT 无法以「0 unexpected」为门禁，只能以「无新增 unexpected」为口径（T7 验收即按此口径） | 已由 `Makefile` 的 `LOCALE_ENV = LC_ALL=C.UTF-8` 前缀修复（zh_CN.UTF-8 下 3 红、C.UTF-8 / en_US.UTF-8 下全绿，属环境敏感而非源码缺陷）；`KNOWN_FAILURES` 已清空，`check` 与 `check-all` 现等价（均以 `0 unexpected` 为门禁） |
| 2026-10-23 | `tests/` | **已解决（2026-10-23）**：离线测试启动引导已固化为 `tests/run-offline.sh` 与 `Makefile` 的 `BOOTSTRAP` 变量（`package-initialize` → 找不到 `etaf` 时补 straight build 目录 → 仓库根前置），两处逻辑一致 | 与「缺 Makefile」叠加后，每次跑离线 ERT 都要手写长 `--eval` BOOT 串，易漏项导致加载到旧版 `ths` | 已新增 `tests/run-offline.sh`（`--all` / `--selector REGEXP`）+ `Makefile` 的 `BOOTSTRAP` |
| 2026-10-22 | `README.md`「开发」节 | 文档与仓库不一致：README 仍描述 `make check` / `make run` / `make live-check`，仓库无 `Makefile`（与第 1 条同源，本条补充「测试引导脚本缺失」维度） | 新环境无法复现文档中的验证流程 | 与第 1、3 条合并处理：补 `Makefile` + `tests/run-offline.sh`，或统一改为显式命令 |
| 2026-10-22 | `ths-ai--present` 写入 `*THS 分析*` 的 `ths-ai--dashboard-buffer` | 报告 buffer 保存的看板 buffer 指向已被 kill 的看板时不会被清理（有 `buffer-live-p` 保护，仅悬空引用） | 无功能问题，仅轻微引用残留 | `ths--stop` 时同步清理报告 buffer 的 buffer-local 值（需改 `ths.el`，本期回避） |
| 2026-10-22 | `ths-ai--neutralise-schemes` | scheme 匹配不跳过 http(s) URL 内部 | `https://a/b/file:c` 会被改写为 `https://a/b/file :c`，链接仍可解析但文本变形（纯可读性，无安全影响） | 匹配前先定位 URL 区间并跳过 |
| 2026-10-22 | 报告 buffer（`ths-ai--present` 内的 `org-confirm-elisp-link-function` / `org-confirm-shell-link-function`） | 使用 `org-confirm-elisp-link-function` / `org-confirm-shell-link-function` 的旧别名 | 新名 `org-link-{elisp,shell}-confirm-function` 已生效，旧名被标记 obsolete，未来 Org 版本删除后会静默失效（届时仅剩第一层净化防护） | 改用新变量名并保留旧名兼容分支 |
| 2026-10-23 | `gptel-curl--stream-filter`（gptel 上游） | gptel 以 curl stdout 首行作为 `info :status`；`-D-` 与 HTTP 代理 CONNECT 叠加时，代理应答行 `HTTP/1.1 200 Connection established` 被当作响应首行，导致 THS-AI 请求被误判失败 | 走代理的机器上 DeepSeek 请求必失败，只能靠 per-backend `--noproxy` 绕开 | 上游修复后（改成按响应体/真实状态行解析）即可移除 `thomas-emacs/lisp/init-llm.el` 里的 `:curl-args '("--noproxy" "api.deepseek.com")` |
| 2026-10-23 | `elisp_check_parens`（elisp-dev-mcp 工具）对 `tests/*.el` | 工具用 `fundamental-mode` 解析文件，中文注释里成对的反引号（`` `…' `` 风格之外的成对 `` ` ``）被当作代码字符，导致假阳性括号不匹配；未修改的备份文件同样报错 | `tests/ths-ai-tests.el` 无法用该工具做 L1 门禁，易误判为回归（本仓库以 `make compile` 为准） | 以 `make compile` / 离线 ERT 为 `tests/*.el` 的门禁；工具侧待改为按 `emacs-lisp-mode` 语法表解析 |
| 2026-10-23 | elisp-dev-mcp 的 task 文件（`/run/user/1000/elisp-mcp-task`） | task 声明是全局单例：多个子代理并行使用 elisp-dev-mcp 时，后声明者会覆盖前者的 `task`，验证请求可能落到主实例 | 并行编排下验证结论不可信，写操作有污染用户 Emacs 的风险 | 编排约束：同一时刻只允许一个子代理使用 elisp-dev-mcp；如需并行，工具侧应把 task 改为按会话/进程维度隔离 |
| 2026-10-23 | `Makefile` 的 `compile` 目标（合并前 master 版） | 门禁漏判：`-f batch-byte-compile` 是命令，返回值不影响 emacs 退出码；`byte-compile-error-on-warn=t` 遇 warning 只让 `byte-compile-file` 返回 nil 且不生成 `.elc`，emacs 仍以 0 退出 → `make compile` 假绿 | 严格编译门禁形同虚设，warning 长期潜伏 | 已改用 `scripts/compile-strict.el`（按返回值判失败 + 显式 `kill-emacs 1`） |

## 2026-10-22 — 东财 push2 域名族在本机不可达，A 股成交明细失效、A 股榜单依赖新浪回退

- **现象**：`push2`、`push2his`、`82.push2`、`88.push2`、`push2delay` 在本机（WSL2 mirrored 网络）TLS 握手后 EOF；57 次尝试仅 2 次偶发 200。
- **影响**：① A 股成交明细（唯一东财源）功能失效；② A 股排行榜依赖 `ths-data-ranking-providers` 的新浪回退才能出数据；③ 港美股东财报价 / 日 K 分支无法实网验证，只能靠离线 fixture 覆盖。
- **复现**：`curl -sv --noproxy '*' --max-time 5 'https://push2.eastmoney.com/api/qt/stock/get?secid=1.600519&fields=f43'`（预期 TLS 握手后 EOF）。
- **发现日期**：2026-10-22（两轮港美股接口探测期间）。
- **处置**：港美支持计划不复现该父问题（A 股成交明细行为保持原状）；恢复可达性后补测港美东财分支，并把 `make live-check` 里的 `skip` 改回真实检查。
