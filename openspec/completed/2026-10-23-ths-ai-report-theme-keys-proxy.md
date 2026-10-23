# THS AI 报告 buffer 主题、退出键与 gptel 代理直连

## 当前状态
- 阶段：已完成（用户 2026-10-23 L3 端到端复验全部符合）
- 已确认：方案 ✅、计划 ✅、代码审查 ✅（无 blocking）、L3 复验 ✅
- 下一步：无（计划已归档到 openspec/completed/）

## 目标

| 编号 | 目标 | 验收表现 |
|---|---|---|
| P1 | `*THS 分析*` 报告 buffer 的配色与主界面（ETAF dashboard）统一 | 背景/前景/标题/代码块/表格/link 全部取 `ths-theme` 配色；`T` 切主题后报告同步刷新 |
| P2 | 报告 buffer 的退出键在 evil normal state 下可用 | `q` 与 `C-c C-q` 都能关闭报告窗口并 refit dashboard |
| P3 | DeepSeek 请求由 gptel backend 自己绕过代理，不改 Emacs 全局环境 | `--noproxy api.deepseek.com` 只出现在 DeepSeek backend 的 curl 命令行；全局 `no_proxy` 恢复 unset；按 `A` 成功 |

## 背景（根因，已实测）

1. **P1**：报告 buffer 是 `org-mode`，使用 Emacs 全局主题；dashboard 是 ETAF 自绘，只用 `ths--apply-buffer-theme`（`ths.el:84`）覆盖 buffer 区的 default face，两者配色来源不同。
2. **P2**：`ths-ai.el:1436` 用 `local-set-key` 把 `q` 写进 local map；evil normal-state keymap 优先级更高且 `q` 在 evil 是宏录制键 → 键被吞。dashboard 键之所以正常，是用户在 `thomas-emacs/lisp/init-tools.el:81` 用 `evil-define-key* 'normal ths-mode-map` 重绑过。
3. **P3**：gptel 的 `gptel-curl--common-args` 含 `-D-`（响应头 dump 到 stdout），curl 走 CONNECT 隧道时先输出 `HTTP/1.1 200 Connection established`，`gptel-curl--stream-filter` 取 stdout 首行作 `info :status` → 请求实际成功（`HTTP/2 200` + 合法 JSON）但 THS 判为失败并 `message`。当前 `no_proxy=api.deepseek.com` 是运行时临时值，重启即失效。

## 设计

### P1：buffer-local `face-remapping-alist`（`ths-ai.el`）

在 `ths-ai.el` 内实现（不放进 `ths-theme.el`，因为 org face 只服务报告 buffer）；新增 `(require 'ths-theme)`（依赖链 `ths-theme → ths-data`，无环）。

```elisp
(defun ths-ai--report-face-remapping ()
  "Return the buffer-local `face-remapping-alist` for the AI report buffer."
  (let ((color (lambda (role) (ths-theme-color role))))
    `((default :background ,(funcall color 'background) :foreground ,(funcall color 'foreground))
      (org-document-title :foreground ,(funcall color 'line) :weight bold :height 1.4)
      (org-document-info :foreground ,(funcall color 'secondary))
      (org-document-info-keyword :foreground ,(funcall color 'muted))
      (org-meta-line :foreground ,(funcall color 'muted))
      (org-level-1 :foreground ,(funcall color 'line) :weight bold :height 1.3)
      (org-level-2 :foreground ,(funcall color 'warning) :weight bold :height 1.15)
      (org-level-3 :foreground ,(funcall color 'secondary) :weight bold)
      (org-level-4 :foreground ,(funcall color 'down) :weight bold)
      (org-level-5 :foreground ,(funcall color 'neutral))
      (org-level-6 :foreground ,(funcall color 'neutral))
      (org-level-7 :foreground ,(funcall color 'neutral))
      (org-level-8 :foreground ,(funcall color 'neutral))
      (org-link :foreground ,(funcall color 'area) :underline t)
      (org-code :foreground ,(funcall color 'point) :background ,(funcall color 'alternate))
      (org-verbatim :foreground ,(funcall color 'point) :background ,(funcall color 'alternate))
      (org-block :background ,(funcall color 'panel) :foreground ,(funcall color 'foreground))
      (org-block-begin-line :background ,(funcall color 'panel) :foreground ,(funcall color 'muted))
      (org-block-end-line :background ,(funcall color 'panel) :foreground ,(funcall color 'muted))
      (org-table :background ,(funcall color 'panel) :foreground ,(funcall color 'neutral))
      (org-quote :foreground ,(funcall color 'secondary) :slant italic)
      (org-hide :foreground ,(funcall color 'background)))))

(defun ths-ai--apply-report-theme (&optional buffer)
  "Apply the THS palette to the AI report BUFFER, default current buffer."
  (with-current-buffer (or buffer (current-buffer))
    (setq-local face-remapping-alist (ths-ai--report-face-remapping))))

(defun ths-ai--refresh-report-theme ()
  "Re-apply the THS palette to a live AI report buffer after a theme change."
  (let ((buffer (get-buffer ths-ai--report-buffer-name)))
    (when (buffer-live-p buffer)
      (ths-ai--apply-report-theme buffer))))

(add-hook 'ths-theme-change-hook #'ths-ai--refresh-report-theme)
```

- `ths-ai--present` 中调用 `(ths-ai--apply-report-theme)`（放在 `unless (derived-mode-p 'org-mode)` 块**之外**，每次 present 都调用；该函数幂等，外来代码清掉 remap 时也能自愈），并 `(setq-local truncate-lines nil)`（正文长行折行，避免横向裁切）。
- 不使用 `buffer-face-mode`：`face-remapping-alist` 能覆盖 org 层级，两种机制混用会互相干扰。
- `ths-theme` 为 dark 时用 `#0b1423/#dce5f4`，light 时自动取 light 列（`ths-theme-color` 已按 `ths-theme` 取值）。

### P2：双键（不引入 evil 硬依赖）

抽出 `ths-ai--bind-report-keys`，在 `ths-ai--present` 中调用：

```elisp
(defun ths-ai--bind-report-keys ()
  "Bind the quit keys of the report buffer, including evil normal state."
  ;; `C-c C-q' 走 local map，任何 state 都可用（只读 buffer 里它会覆盖
  ;; `org-set-tags-command'，此处无副作用）。
  (local-set-key (kbd "C-c C-q") #'ths-ai-quit-report)
  ;; `q' 走 local map，供非 evil 环境。
  (local-set-key (kbd "q") #'ths-ai-quit-report)
  ;; evil normal state 用 buffer-local state map，优先级高于全局 state map；
  ;; `q' 在 evil 里是宏录制键，只写 local map 会被吞掉。
  (when (boundp 'evil-normal-state-local-map)
    ;; 复制现有 buffer-local state map 再加键。直接换一张新 map 会清掉
    ;; evil-org 等注入到 local map 的绑定（org 导航键等），报告 buffer 虽只读，
    ;; 但没有理由牺牲这些绑定。
    (let ((map (copy-keymap (or evil-normal-state-local-map (make-sparse-keymap)))))
      (define-key map (kbd "q") #'ths-ai-quit-report)
      (setq-local evil-normal-state-local-map map))))
```

- 不 `require 'evil`、不进 `Package-Requires`；`boundp` 判断保证无 evil 时零影响。
- `evil-normal-state-local-map` 是裸变量引用（读 `copy-keymap` 的值），在 `lexical-binding: t` 与 `byte-compile-error-on-warn t` 下必须在 `ths-ai.el` 顶部与既有的 `org-confirm-elisp-link-function` / `org-confirm-shell-link-function` 并列声明 `(defvar evil-normal-state-local-map)`，否则严格编译报 `reference to free variable` 并失败。
- 保留原有 `(local-set-key (kbd "q") ...)` 的行为，移入该函数统一管理。
- **不变量 I-EVIL**：`ths-ai--bind-report-keys` 的 evil 分支必须在现有 buffer-local state map 上加键，不得整体替换（否则丢失 evil-org 等注入的 local 绑定）。

### P3：gptel backend `:curl-args`（`thomas-emacs/lisp/init-llm.el`）

```elisp
(gptel-make-deepseek "Deepseek"
  :stream t
  :curl-args '("--noproxy" "api.deepseek.com")   ; 新增：DeepSeek 直连，避免代理 CONNECT 头污染 gptel 的状态行解析
  :key (getenv "DEEPSEEK_API_KEY"))
```

- 依据：`gptel-make-deepseek` 支持 `:curl-args`（`gptel-openai-extras.el:336-390`）；`gptel-curl--get-config-args` 把 `common-args + gptel-curl-extra-args + backend curl-args` 拼进命令行（`gptel-request.el:2810-2817`），且 `--config -` 分支同样使用该函数（`gptel-request.el:2899-2901`）。
- 不动 `gptel-proxy`（设为代理地址后会追加 `--proxy/--proxy-negotiate/--proxy-user`，隧道依旧、问题不解）；不动 `url-proxy-services`；不改 Emacs 全局 `process-environment`。
- 落地后把临时 `no_proxy` 清回未设置，以证明 backend 参数独立生效。

## 任务

- [x] 任务 1：`ths-ai.el` 新增 `(require 'ths-theme)`，并在文件顶部（既有两个 `org-confirm-*` defvar 之后）加 `(defvar evil-normal-state-local-map)`；按 `ths-ai--report-face-remapping` → `ths-ai--apply-report-theme` → `ths-ai--refresh-report-theme` → `ths-ai--bind-report-keys` 的顺序定义（`ths-ai--report-buffer-name` 的 defconst 必须在它们之前），并 `add-hook 'ths-theme-change-hook #'ths-ai--refresh-report-theme`（依赖：无）
- [x] 任务 2：`ths-ai.el` 的 `ths-ai--present` 内调用 `(ths-ai--apply-report-theme)`（放在 `unless (derived-mode-p 'org-mode)` 块之外，每次 present 都执行）并设 `truncate-lines` 为 nil（依赖：任务 1）
- [x] 任务 3：`ths-ai.el` 抽出并调用 `ths-ai--bind-report-keys`（`q` 的 evil local state map + `C-c C-q` + 普通 `q`）（依赖：无）
- [x] 任务 4：`tests/ths-ai-tests.el` 新增 5 个 ERT 测试（依赖：任务 1、2、3）
  - `ths-ai-report-theme-remaps-default-and-headings`：present 后 `face-remapping-alist` 覆盖 default 与 org-level-1/org-code，且取值等于 `(ths-theme-color 'background)` 等
  - `ths-ai-report-theme-refreshes-on-theme-change`：`customize-set-variable` 把 `ths-theme` 切到 light → 触发 `ths-theme-change-hook` → 报告 buffer 的 remap 更新为 light 值；测完切回 dark（用 `unwind-protect`）
  - `ths-ai-report-binds-quit-keys`：**在报告 buffer 内** `with-current-buffer` 断言 `(key-binding (kbd "C-c C-q"))` 与 `(key-binding (kbd "q"))` 均为 `ths-ai-quit-report`
  - `ths-ai-report-binds-q-in-evil-normal-state`：测试文件内用 `(defvar evil-normal-state-local-map)` 制造 `boundp`（须在文件顶层声明一次，避免每个用例重复副作用），present 后**在报告 buffer 内**断言 `(lookup-key evil-normal-state-local-map (kbd "q"))` 为 `ths-ai-quit-report`
  - `ths-ai-report-evil-local-map-keeps-existing-keys`（不变量 I-EVIL）：present 前先给报告 buffer 的 `evil-normal-state-local-map` 预置一个 buffer-local 键（如 `j` → `ignore`），present 后断言该键仍在 `evil-normal-state-local-map` 中且 `q` 同时绑定成功
  - 所有新测试复用现有 helper `ths-ai-test--cleanup-report` 清理报告 buffer
- [x] 任务 5：`thomas-emacs/lisp/init-llm.el` 的 `gptel-make-deepseek` 增加 `:curl-args '("--noproxy" "api.deepseek.com")`（依赖：无，可与任务 1-4 并行）
- [x] 任务 6：清理与验证（依赖：任务 1-5）
  - `emacs-ths`：verify 实例 `make compile`（严格编译）与 `tests/run-offline.sh --selector "ths-ai"` 全绿
  - `thomas-emacs`：verify 实例**按 L3 标准**验证 —— curl-args 精确断言 + 拼接顺序断言 + 前置条件检查（key 非空、直连探针返回 4xx）+ 降级策略（条件不满足时跳过真实请求并标注，不计为方案失败）
  - 主实例（config）：清除临时 `no_proxy`（`(setenv "no_proxy" nil)`），用户按 `A` 复验
- [x] 任务 7：文档沉淀（依赖：任务 6）：`CHANGELOG.md`、`README.md`（AI 章节）、`openspec/decisions.md`、`openspec/tech-debt.md`，计划归档到 `openspec/completed/`

## 文档清单

| 文档 | 变更内容 |
|---|---|
| `emacs-ths/CHANGELOG.md` | 新增三项：报告 buffer 跟随 THS 配色、报告 buffer 支持 `q`/`C-c C-q` 退出、gptel DeepSeek 直连说明 |
| `emacs-ths/README.md` | AI 章节补充：报告 buffer 配色与 dashboard 一致；退出键；代理环境下由 backend `:curl-args` 控制直连 |
| `emacs-ths/openspec/decisions.md` | 决策：代理排除放在 gptel backend 层而非 Emacs 全局环境（理由：影响面可控） |
| `emacs-ths/openspec/tech-debt.md` | 记录 gptel `gptel-curl--stream-filter` 以 stdout 首行作 `:status` 的上游缺陷；上游修复后可移除 `:curl-args` |
| `thomas-emacs` 仓库 | 无 CHANGELOG 时仅靠代码注释说明（`init-llm.el` 的 `:curl-args` 行内注释） |

## 验证标准

- **L1（语法）**：verify 实例 `elisp_check_parens` 检查 `ths-ai.el` 与 `tests/ths-ai-tests.el`；`make compile`（`byte-compile-error-on-warn t`）零警告。
- **L2（离线功能）**：`tests/run-offline.sh --selector "ths-ai"` 全绿；全量 `make check` 无新增红。
- **L3（配置与端到端）**：
  - verify 实例先断言 `(gptel-backend-curl-args (gptel-get-backend "Deepseek"))` 精确等于 `("--noproxy" "api.deepseek.com")`，并断言 `(gptel-curl--get-config-args info)` 产物中 `--noproxy` 位于 `-D-` 之后（`--config` 由上层 `gptel-curl-get-response` 单独追加，不在该函数返回值内，故不对其作断言）
  - **前置条件检查**：真实 `gptel-request`（prompt "1+1=?"）执行前先确认 ① `(getenv "DEEPSEEK_API_KEY")` 非空；② 直连可达（`--noproxy api.deepseek.com` 的探针返回 4xx 而非 000）
  - **降级策略**：任一前置条件不满足时**跳过**真实请求，仅保留 `curl-args` 断言，并在报告中明确标注「真实请求未执行（缺 key / 网络不通）」；不得把前置条件缺失记为方案失败
  - 真实请求通过标准：`response` 为字符串，且 `(plist-get info :status)` 不含 `Connection established`
  - 主实例（config，用户操作）：按 `A` 后报告正常生成、配色与 dashboard 一致、`q` 与 `C-c C-q` 均能退出、`T` 切主题后报告同步变色
- **回滚**：三项改动互相独立；P3 只需删掉 `:curl-args` 一行，P1/P2 只需回退 `ths-ai.el` 的相关函数与调用。

## 注意事项

1. `C-c C-q` 在 `org-mode` 默认是 `org-set-tags-command`；报告 buffer 只读、local map 优先，覆盖无副作用，但需在代码注释中写明这是有意为之。
2. `face-remapping-alist` 是 buffer-local，`erase-buffer`/重写正文不会清除它；主题切换必须通过 `ths-theme-change-hook` 主动刷新，否则残留旧色。
3. 测试里不得 `require 'evil`：用 `defvar` 制造 `boundp` 来模拟，避免测试依赖用户配置。
4. 严格编译要求 `add-hook` 引入的 `ths-ai--refresh-report-theme` 与 `ths-ai--report-buffer-name` 的定义顺序正确（`defconst` 在前，hook 在最末）。
5. P3 的 `:curl-args` 只在重启 Emacs 后进入已注册的 backend；当前会话若要立即验证，需重新 `gptel-make-deepseek` 或重启。
6. 清除临时 `no_proxy` 后，若按 `A` 再次失败，说明 `--noproxy` 未生效（检查 `gptel-curl-extra-args`/backend 槽是否被其他配置覆盖），此时回退到「全局 `no_proxy`」方案并记录到 tech-debt。
7. `evil-normal-state-local-map` 在 evil 已初始化时总是 bound；`copy-keymap` 前用 `(or ... (make-sparse-keymap))` 兜底，避免对 nil 调用 `copy-keymap` 报错。
8. 报告 buffer 的 `q` 现在有两条路径（local map 与 evil state map），二者都指向 `ths-ai-quit-report`；若将来新增 evil motion state 绑定，需同步两处，否则会出现「某个 state 下 `q` 无效」的回归。

## 执行结果

- 任务 1-4（`ths-ai.el` + `tests/ths-ai-tests.el`）：`make compile` 严格编译零告警；`run-offline.sh --selector "ths-ai"` 48/48；`make check` 168/168。
- 任务 5（`thomas-emacs/lisp/init-llm.el`）：`gptel-make-deepseek` 增加 `:curl-args '("--noproxy" "api.deepseek.com")`，`check-parens` 通过。
- 任务 6（验证）：verify 实例断言 backend `curl-args` = `("--noproxy" "api.deepseek.com")` 且在 curl 参数中位于 `-D-` 之后；主实例清除临时 `no_proxy` 后按 `A` 复验成功。
- 实施中被实测推翻并调整的 3 条设计假设（已记入 `openspec/decisions.md`）：`local-set-key` 会污染共享 `org-mode-map`、`copy-keymap`+`setq-local` 不能替换 evil state map、`face-remapping-alist` 改动需 `force-window-update` 才重绘。
- 遗留：`init-llm.el` 的 `gptel-model` 为 `deepseek-v4.1-flash`，主实例复验时运行态为 `deepseek-flash`（不影响本次验证，重启后以文件为准）。
