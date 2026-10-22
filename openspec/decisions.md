# 决策日志

## 2026-10-22 — 港美股计划工件从 thomas-emacs 迁入 emacs-ths 仓库

- **决策**：在 emacs-ths 仓库根新建完整 `openspec/`（`active/`、`completed/`、`decisions.md`、`tech-debt.md`）；原 `~/thomas-emacs/openspec/active/2026-10-22-emacs-ths-hk-us-support.md` 降级为指针文件（保留迁移说明，不再承载计划正文）。
- **理由**：① 计划的全部改造对象（7 个源文件、13 个测试文件、README、CHANGELOG）都在本仓库，跨仓库跟踪会导致行号锚点与文档清单持续漂移；② 覆盖到的文档也在本仓库，Phase 4 文档沉淀无法跨仓库执行；③ thomas-emacs 仅保留 ths 作为 straight 包的安装与键位配置，不承载实现细节。参见 `~/thomas-emacs/openspec/decisions.md` 的 2026-10-22「A股看盘包由 achive 完全替换为 ths」条目。
- **配套调整**：原计划任务8 中的 `thomas-emacs/openspec/tech-debt.md` 条目改为本仓库 `openspec/tech-debt.md`；验证入口（Makefile + 严格编译驱动 + ERT runner）由任务8 前置为任务0（基线门禁无法在无入口时执行）。
