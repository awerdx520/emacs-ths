# emacs-ths 港美股支持收尾与 AI 线合并

## 当前状态

- 阶段：Phase 2（Plan）· 待用户确认
- 已确认：方案 ✅（用户 2026-10-23 确认：先港美收尾、再 AI 信息因子；四个默认值均同意）
- 关联计划：`2026-10-23-ths-ai-info-factors.md`（本计划完成后串行执行）
- 前置计划：`feat/hk-us-support` 上的 `openspec/active/2026-10-22-emacs-ths-hk-us-support.md`（任务 0–5 完成，任务 6/7/8 未完成）
- 安全点（Phase 3 首步创建）：tag `pre-hkus-finish` 指向合并前分支 tip；`stash@{0}` 为任务 6 的进行中改动
- 下一步：plan-reviewer 独立审查 → 用户确认计划 → Phase 3

## 目标

1. 把 `master`（AI 分析线，领先 4 个提交）合并进 `feat/hk-us-support`（港美线，领先 8 个提交），形成单一基线，使后续 AI 增强能一次覆盖 A 股 / 港股 / 美股。
2. 把 `stash@{0}` 里任务 6 的进行中代码安全落地。
3. 完成港美计划的剩余三项：任务 6（UI 展示）、任务 7（测试夹具与既有断言）、任务 8（文档与变更记录）。
4. 终验后合回 `master` 并归档两份计划。

## 非目标

- 不做 AI 信息因子（新闻 / 公告 / 财报 / 行业 / 宏观）——属下一份计划。
- 不修复 A 股成交明细因东财域名不可达导致的既有失效（已登记 tech-debt）。
- 不引入付费行情源、不做汇率换算、不做盘前盘后分时（沿用前置计划的显式非目标）。
- 不改 `ths-ai.el` 的功能行为：合并只求两侧能力共存，不在此计划内扩展 AI。

## 设计与前置事实

### 分支拓扑（2026-10-23 实测）

| 项 | 事实 |
|---|---|
| 当前分支 | `master`，与 `origin/master` 同步，工作区干净 |
| 分叉 | `master` 领先 4、`feat/hk-us-support` 领先 8，merge-base `7fad453`（tag `pre-hkus-baseline`） |
| master 独有 | `65c4646` AI 分析、`88358ff` Makefile + `tests/run-offline.sh`、`4b08532` 文档/ADR/计划、`764bd50` 报告配色与 evil 键 |
| 分支独有 | 港美任务 0–5 共 8 个提交（画像表、报价、分时/日K、搜索、榜单、locale 修正、Makefile） |
| 分支缺 | `ths-ai.el`、`tests/ths-ai-tests.el`、`tests/run-offline.sh`、`CHANGELOG.md`、`docs/adr/0001-*`、两份 AI 计划 |
| master 缺 | `tests/ths-hkus-tests.el`、`scripts/{boot,compile-strict,test-batch}.el`、港美计划文件 |
| 合并冲突（merge-tree 试算） | 4 处：`Makefile`(add/add)、`openspec/decisions.md`(add/add)、`openspec/tech-debt.md`(add/add)、`ths.el`(content) |
| stash | `stash@{0}` = `On feat/hk-us-support: dca672c`，254 insertions / 63 deletions / 5 文件（`ths.el` 135/38、`tests/ths-hkus-tests.el` 66/0、`ths-data.el` 27/10、`ths-chart.el` 21/13、`tests/ths-data-tests.el` 5/2）；`git show stash@{0}` 是 combined diff（`diff --cc`）**不可直接 apply**，标准格式在 `git stash show -p` |

### 合并冲突处置（逐文件口径，不得整段丢弃任一侧）

| 文件 | 处置 |
|---|---|
| `Makefile` | 取并集：保留 master 的目标集（`check` / `check-all` / `compile` / `test` / `live-check` / `run` / `clean` / `help`）与 `BOOTSTRAP` 变量；**保留分支的 `LOCALE_ENV = LC_ALL=C.UTF-8`**（分支为保证宽字符断言稳定而加，master 无此修正）。**`compile` 目标必须改用分支的 `scripts/compile-strict.el`**：实测 master 现写法 `-f batch-byte-compile $(SOURCES) \|\| st=$$?` 存在门禁漏判——`batch-byte-compile` 是命令，其返回值不影响 emacs 退出码，`byte-compile-error-on-warn=t` 遇 warning 时只让 `byte-compile-file` 返回 nil 且不生成 `.elc`，emacs 仍以 0 退出，于是 `st=0`、`make compile` 假绿。改法：`compile` 目标改为执行 `scripts/compile-strict.el`（按 `byte-compile-file` 返回值判失败、显式 `kill-emacs 1`），并把该债登记到 `tech-debt.md` |
| 构建入口（统一为 master 结构） | **删除分支的 `scripts/boot.el` 与 `scripts/test-batch.el`**（语义分别被 master 的 `BOOTSTRAP` 与 `tests/run-offline.sh` 覆盖）；**保留 `scripts/compile-strict.el`** 并接入 `compile` 目标（原因见上一行）。在 `tests/run-offline.sh` 的 `tests` 数组与 `Makefile` 的 `TESTS` 变量各加一行 `tests/ths-hkus-tests.el`（`ths-ai-tests.el` 已在列表内）。删脚本前先 `grep -rn "scripts/" Makefile tests/ README.md` 确认无残留引用；改完用「人为制造一条编译 warning 的临时副本」验证 `make compile` 返回非零 |
| `openspec/decisions.md` | 两侧条目全部保留，按日期升序合并，不删任何一条 |
| `openspec/tech-debt.md` | 两侧条目合并去重；同一债两侧都记时保留信息更全的一条，并保留 master 的「已解决（2026-10-23）」标注 |
| `ths.el` | master 侧：AI 摘要行 + `chart-rows` 常数 7→8 + `A` 键绑定 + `ths--stop` 取消 AI 请求；分支侧：港美详情面板、排行榜 5 态与按钮、窄窗列裁剪。两侧改的是不同函数为主，真正重叠点在 `ths--exchange-detail`（AI 摘要行与港美标题/盘口同处一个函数体），合并时保留 AI 摘要行**并且**应用港美的市场标签/币种/1 档盘口改动 |

### 构建入口统一后的期望语义

- `make check` = 严格字节编译 + 离线 ERT **全量（0 unexpected）**
- `make compile` = 仅严格编译；`make test` = 仅离线 ERT
- **`LOCALE_ENV=C.UTF-8` 使既有的 3 例「基线红」转绿**（该 3 例是宽字符显示宽度随 locale 变化的断言，不是代码缺陷）：合并后 `make check` 与 `make check-all` 应同为 0 unexpected。因此：
  - `Makefile` 的 `KNOWN_FAILURES`（若有排除项）需清空或删除；
  - `openspec/tech-debt.md` 中该条目改为「已解决（2026-10-23，`LOCALE_ENV=C.UTF-8`）」；
  - A7/L2 的验收口径是 **0 unexpected**，不再是「基线 3 红不变」。
- 三个目标都以 `LC_ALL=C.UTF-8` 前缀运行，结果与调用者 locale 无关

## 任务

- [ ] A1 安全点与计划入库
  - 文件：无源码改动
  - 步骤：① `git -C /home/thomas/Workspace/emacs-ths tag pre-hkus-finish feat/hk-us-support`；② `git checkout feat/hk-us-support`（两份计划为 untracked，会随工作区保留）；③ 提交两份计划文件（commit message：`docs(openspec): 增加港美收尾与 AI 信息因子计划`）
  - 验收：`git tag -l 'pre-hkus-*'` 含 2 个 tag；分支上两份计划文件已提交；`git status --porcelain` 干净
  - 依赖：无

- [ ] A2 合并 master → 分支并解决 4 处冲突
  - 文件：`Makefile`、`openspec/decisions.md`、`openspec/tech-debt.md`、`ths.el`、`tests/run-offline.sh`（修改）、`scripts/boot.el` 与 `scripts/test-batch.el`（删除）、`scripts/compile-strict.el`（保留并接入 `compile` 目标）
  - 步骤：① `git merge master`（预期 4 处冲突）；② 按「设计与前置事实」的逐文件口径解决；③ 只删 `scripts/boot.el` 与 `scripts/test-batch.el`，保留 `scripts/compile-strict.el` 并接入 `compile` 目标；在 `tests/run-offline.sh` 与 `Makefile` 的 `TESTS` 各加 `tests/ths-hkus-tests.el`；③b `compile-strict.el` 的源文件清单**必须由硬编码 7 个改为读命令行参数**（Makefile 传 `$(SOURCES)`，8 个文件含 `ths-ai.el`），或直接补成 8 个——否则合并后 `ths-ai.el` 不被严格编译、门禁覆盖缩水；④ 清空 `KNOWN_FAILURES`（`Makefile:35`）与 `tests/run-offline.sh` 的 `known_failures`——注意两处的 ERT 选择器都是 `(not (member <列表>))`，列表置空会变成非法 elisp `(not (member ))`，必须同步把选择器改为 `t`（或保留变量并把选择器写成 `(when KNOWN_FAILURES ...)` 分支）；**同时更新 `Makefile` 的 help 两行（「排除 3 个已知基线红」「含已知基线红，预期非零」）与头部 `KNOWN_FAILURES` 注释段，并写明 `check` 与 `check-all` 现已等价（保留 `check-all` 作显式全量别名）**；把 `tech-debt.md` 的 3 红条目改为已解决、新增「master `make compile` 门禁漏判」条目；⑤ 提交（`merge: 合并 master 的 AI 分析线到港美分支`），commit body 记录四处冲突的取舍理由
  - 验收：`git status --porcelain` 干净；`make check` 退出码 0 且输出 **0 unexpected**；`make compile` 覆盖 8 个源文件（含 `ths-ai.el`，由 `compile-strict.el` 输出或参数校验证明）；`make compile` 在人为 warning 的临时副本上返回非零；`make check` 输出的 ERT 用例数与改动前两侧基线之和**无重复计数**（记录实测确切数字，不预先假设为「152 + N」）；`git log --oneline -1 --merges` 可查到该 merge 提交
  - 依赖：A1

- [ ] A3 落地 `stash@{0}`（任务 6 进行中改动）
  - 文件：`ths.el`、`ths-data.el`、`ths-chart.el`、`tests/ths-hkus-tests.el`、`tests/ths-data-tests.el`
  - 步骤：① `git stash apply stash@{0}`（不要 `pop`，保留 stash 直到 A4 验收通过）；② 逐 hunk 审查与合并后代码的兼容性（特别是 `ths.el` 中 AI 摘要行附近的冲突）；③ 跑 `make check`
  - 验收：`make check` 无新增 unexpected；任务 6 的新函数（`ths-data-market-label`、`ths-data-volume-unit`、`ths--trades-p`、`ths--book-title`、`ths--book-volume`、`ths-chart--volume-unit`）全部存在且被引用；若 apply 冲突严重无法安全解决，则 `git checkout -- .` 回滚并在 A4 按计划重建（此时记录原因到本计划「实现记录」）；注意 `tests/ths-data-tests.el` 的 5/2 改动来自 stash（指数 3→8 的断言），与 A5「240 分钟断言逐字未改」不冲突——后者只指 `(= 240 (ths-data-minute-slot "1500"))` 这一条断言
  - 依赖：A2

- [ ] A4 任务 6：UI 展示
  - 文件：`ths.el`、`ths-data.el`、`ths-chart.el`、`tests/ths-hkus-tests.el`
  - 步骤：① `ths--exchange-detail` 标题追加画像 `:label` 与 `:currency`；② `ths--exchange-book` 按 `:book-levels` 渲染（港美只出买一/卖一、标题「盘口 / 股」，不补伪造档位）；③ `ths--ensure-chart` 请求列表：场外基金 `(quote)`、hk/us 去掉 `trades`、A 股不变；④ `ths--trades` 与 `ths--market-sidebar` 对 hk/us 跳过成交明细面板；⑤ 单位文案按画像取「手」或「股」（`ths--trade-cells`、`ths--volume`、`ths-chart.el` 的「成交量（手）」「量/手」）；⑥ 指数条扩为 8 条（`ths-data-index-symbols` + `ths-data--metadata` 补名称 + 按宽度截断）；⑦ 自选列表行（`ths--watchlist`）名称列补市场标签，并确认列表筛选（`ths-data-filter` 的 `:market-label` 查询键）可搜「港股」「美股」
  - 验收：新增 ERT `ths-hkus-book-single-level`、`ths-hkus-index-bar-8-entries`、`ths-hkus-no-trades-request`（hk/us 无 `trades`、A 股仍有）、`ths-hkus-trades-panel-absent`；`tests/ths-trades-tests.el` 的先盘口后成交位置断言仍绿；`make check` 无新增 unexpected；新增 ERT `ths-hkus-watchlist-shows-market-label` 与 `ths-hkus-filter-matches-market-label`（筛选查询「港股」「美股」能命中）
  - 依赖：A3

- [ ] A5 任务 7：测试夹具与既有断言
  - 文件：`tests/ths-hkus-tests.el`、`tests/ths-fixtures.el`、`tests/ths-live-check.el`
  - 步骤：① 把两轮探测的真实响应体整理为 defconst（腾讯 hk00700/usAAPL 报价、港股分时 4 列、美股 usMinute 3 列、港美日 K、新浪港美榜单首页），逐条标注探测日期；② `ths-fixtures.el` 的 `ths-test--stocks` 增港美样本、`ths-test--book` 按画像档数生成；③ `ths-live-check.el` 补 `hkstock`/`usstock` universe、东财相关项标 `skip（东财本机不可达）` 且不计失败、`pending` 与实际检查数同步
  - 验收：`make check` 全绿（不触网）；`git diff --stat` 显示无用例被删除；新增用例数 ≥ 4；A 股回归用例（`ths-data-tests.el` 240 分钟、`ths-volume-tests.el` 量/手、`ths-tests.el` 卖5/买5）逐字未改且通过
  - 依赖：A4

- [ ] A6 任务 8：文档与变更记录
  - 文件：`README.md`、`CHANGELOG.md`、`openspec/decisions.md`、`openspec/tech-debt.md`
  - 步骤：① README 功能列表/按键表（`u` 五态）/配置表（6 种符号前缀）/数据来源表补港美；已知限制写「港美 1 档盘口、无成交明细、港美无行业数据、东财本机不可达」；② `CHANGELOG.md` 的 `Unreleased` 段补港美 Added/Changed/Limitations；③ `decisions.md` 追加 ≥3 条（市场画像表为单一事实来源、港美 1 档与无成交明细的显式降级、后缀缺失直接走新浪兜底）；④ 核对 `tech-debt.md` 的东财 `push2` 条目
  - 验收：README 三目标说明与 `make -n check` / `make -n run` / `make -n live-check` 实际命令行逐字一致；`grep -c "push2" openspec/tech-debt.md` ≥ 1；`decisions.md` 新增条目日期为 2026-10-23
  - 依赖：A5

- [ ] A7 终验与合回 master + 归档
  - 文件：计划归档
  - 步骤：① 跑 L1（`make compile` + 源文件 `check-parens`）、L2（`make check`）、L3（`make live-check`，需网络）、L4（verify 隔离实例 headless 冒烟：断言 `hk00700` / `usAAPL` 的 `:price` 为数字、`:market-label` 为 港股/美股）；② `git checkout master && git merge --no-ff feat/hk-us-support`；③ 把本计划移入 `openspec/completed/`；④ 删除 `stash@{0}`（确认内容已在分支历史中）
  - 验收：四级验证全过（L2 口径为 **0 unexpected**）；master 上 `make check` 通过；计划已在 `completed/`；`git stash list` 为空
  - 依赖：A6

## 文档清单

| 文档 | 动作 |
|---|---|
| `README.md` | 港美功能、按键表 `u` 五态、6 种符号前缀、数据来源表、已知限制 |
| `CHANGELOG.md` | `Unreleased` 补港美 Added / Changed / Limitations |
| `openspec/decisions.md` | 追加画像表、1 档降级、后缀兜底三条决策；保留两侧既有条目 |
| `openspec/tech-debt.md` | 核对东财 push2 条目；合并两侧条目去重 |
| `openspec/completed/` | 本计划归档 |
| `tests/ths-live-check.el` | Commentary 说明新增港美检查与东财 skip 条件 |

## 验证标准

| 级别 | 方法 | 通过判据 |
|---|---|---|
| L1 | `make compile`（严格字节编译）+ 源文件 `check-parens` | 0 error 0 warning；仓库无 `.elc` 残留 |
| L2 | `make check`（离线 ERT 全量） | **0 unexpected**（`LOCALE_ENV=C.UTF-8` 后既有 3 例应转绿；若仍红说明合并破坏了宽字符断言，须定位修复而非重新豁免） |
| L3 | `make live-check`（需网络） | 港美报价/分时/日K/榜单检查通过；东财项 `skip` 不计失败；退出码 0 |
| L4 | verify 隔离实例 headless：`elisp_mcp_set_task(verify)` → 加载 → `(ths)` → 断言 → `set_task(auto)` → `instance(stop)` → `instance_status` 确认 | 港美两条断言成立；收尾 `task=auto` 且实例已停 |

## 注意事项

1. **合并后必须先跑全量 ERT 再动任何代码**：冲突解决可能引入静默回归，`make check` 是最快的探针。
2. **`stash@{0}` 在 A4 验收通过前不得 drop**：它是任务 6 的唯一样本。
3. **两套构建入口不能并存**：`scripts/test-batch.el` 与 `tests/run-offline.sh` 同时存在会让「跑的是哪套」不可判定，必须统一。
4. **`ths.el` 是唯一内容冲突文件**：AI 摘要行与港美详情改动同处 `ths--exchange-detail`，合并时以「两侧功能都必须保留」为准，不允许为省事回退任一侧。
5. **locale**：`LC_ALL=C.UTF-8` 是分支为稳定宽字符断言加的必要修正，合并时不得丢失。
6. **验收口径**：采用 `LOCALE_ENV=C.UTF-8` 后既有的 3 例「基线红」应转绿，因此验收口径是 0 unexpected；**不得**为了「保持 3 红」去改回 locale，也不得删除那 3 个断言。
7. **工作区整洁核对**：仓库根的 `test-nativecomp-cache-*/` 三个目录若未被 `.gitignore` 覆盖，A1 的「工作区干净」表述不成立——执行时先 `git status --ignored --porcelain | grep nativecomp` 确认，必要时补 `.gitignore` 或删除（属清理，需在 commit 说明中注明）。
8. **不得为省事回退任一侧**：`ths.el` 合并后必须同时具备 AI 摘要行与港美详情/盘口/指数条改动，验收以「两侧功能都在」为准。

## 假设清单

| # | 假设 | 来源 |
|---|---|---|
| 1 | 4 处冲突可人工取并集且不丢任一侧能力 | 事实✓ merge-tree 试算；假设? 未实际合并 |
| 2 | `stash@{0}` 的任务 6 代码可安全 apply | 事实✓ stash 存在且内容对应任务 6；假设? 未经运行验证 |
| 3 | `make check` 在合并后可一次通过（需加一行 `ths-hkus-tests.el` 并清 `KNOWN_FAILURES`） | 假设? 两侧 runner 结构不同；另注 `LOCALE_ENV=C.UTF-8` 后既有 3 例应转绿（分支实测依据：C.UTF-8 下 146 tests / 0 unexpected） |
| 4 | 合回 master 后 AI 与港美功能互不影响（`ths.el` 合并是唯一耦合点） | 假设? 需 L2 + L4 验证 |

## 计划审查记录

| 轮次 | 结论 | 修订 |
|---|---|---|
| 1（plan-reviewer，2026-10-23） | 需修订 | ① A4 补自选列表市场标签与筛选可搜「港股」「美股」（原遗漏任务 6 末条）；② 更正「基线 3 红不变」口径——`LOCALE_ENV=C.UTF-8` 使该 3 例转绿，L2 改为 0 unexpected，并同步清 `KNOWN_FAILURES` 与 tech-debt 标注；③ 统一 `scripts/*.el` 处置为「删除，语义由 master Makefile 覆盖」，消除「并入 vs 保留」自相矛盾；④ 更正 ERT 并集数字的预判（改为实测记录）。Minor：澄清 stash 的 `ths-data-tests.el` 改动与 240 分钟断言的关系；补工作区 nativecomp 目录核对；补「不得回退任一侧」注意事项 |
| 2（harspower 事实核实，2026-10-23） | 纠正第 1 轮的 M5 误判 | 核实 `Makefile` 的 `compile` 目标用 `-f batch-byte-compile`：该命令返回值不影响 emacs 退出码，`byte-compile-error-on-warn=t` 遇 warning 仍以 0 退出 → **门禁漏判**，故 `scripts/compile-strict.el` 必须保留并接入 `compile` 目标（第 1 轮「可删除」的判断作废）；另核实 `KNOWN_FAILURES` 与 `run-offline.sh` 的 `known_failures` 双份存在且选择器为 `(not (member …))`，清空需同步改选择器为 `t` |
| 3（plan-reviewer 复审，2026-10-23） | 需修订 → 已修 | ① 缓存命中路径占位未 `remhash` 会导致永久去重死锁 → B6 改为「回调内先 `remhash` 清占位再分支」，并补两条 ERT（命中后再按 `A`、超时/失败后可重新发起）；② 围栏转义会破坏既有断言 `tests/ths-ai-tests.el:289`（`DATA>>>` → `DATA >> >`）→ B7 显式纳入该断言与 R7 注释的同步修正；③ `compile-strict.el` 源文件清单 7→8（含 `ths-ai.el`）与传参方式写入 A2 ③b；④ `Makefile` help 两行与 `KNOWN_FAILURES` 注释段、`check`/`check-all` 等价语义写入 A2 ④；⑤ 退码 63 映射抽成纯函数 + `ths-info` 自建 curl 封装（不复用 `ths-data--http` 的写死 referer）写入 B3 |
