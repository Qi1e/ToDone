# 协作开发

沿用 [AGENTS.md](AGENTS.md) 的任务分级、自动维护和验证规则。协作开发不改变 [产品规格](PROJECT_SPEC.md) 的个人事项系统定位，不增加 App 内多用户功能。

## 领取任务与并行

- 不设置固定成员职责或代码归属。任何成员均可领取 Issue；开始前在 Issue 中明确本次执行人和修改范围。
- Issue 使用仓库模板，写明目标、范围、验收、依赖与验证。可选用 GitHub Projects 显示这些 Issue，不另建重复任务台账。
- [TODO.md](TODO.md) 保留项目级基线、阻塞与验收状态；Issue 记录细粒度任务。相关 PR 只同步受影响的项目级状态，不把整个看板复制到 TODO。
- 从最新 main 建立短期分支，如 `feat/matter-editor`、`fix/card-refresh`、`docs/team-workflow`。同一文件的大幅改动先在 Issue 协调合并顺序。
- UI 可基于 [事项服务契约](app/entry/src/main/ets/contracts/MatterService.ets) 和 Mock 开发；接口变更先提交小 PR，经使用方审查后再并行扩展实现。

## PR 与完成标准

一个任务对应一个小 PR，关联 Issue，使用 PR 模板记录实际验证。必要检查通过、讨论处理完毕、至少一名其他成员批准后采用 Squash Merge，再删除已完成分支。

代码变化仍需按 [开发说明](docs/development.md) 构建；涉及存储、交互和卡片时按现有清单验收。Node CI 不能替代 ArkTS 构建、Hypium 与设备验收。不能修改检查命令、删除有效测试或把环境缺项当作成功。

规格、契约、存储、构建或工程规则变更需让相关使用方审查。未配置强制分支规则前，这些仍是团队约定，不能声称 GitHub 已自动阻止违规合并。

## GitHub 设置（管理员操作）

本节是仓库设置，不能通过合并文件自动启用。先让 PR 的 `portable-checks` 实际运行一次，再为 main 配置 branch protection 或 active ruleset：

1. 要求 Pull Request，至少 1 名其他成员批准；新提交撤销过时批准。
2. 必需状态检查选本工作流产生的 `portable-checks`，要求分支在合并前与 main 同步，并处理所有审查讨论。
3. 禁止强推和删除 main；将维护者也纳入约束，日常协作不使用绕过。
4. 团队成员自行受邀加入仓库；不要求为当前方案提前提供名单，不按人设置 CODEOWNERS。
5. 完整构建环境验证后，再将其真实构建结果接为额外必需检查。当前不得把 Node CI 命名或解释为 HAP 构建。

GitHub 操作依据：[分支保护](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)。尚未完成的设置保留在 TODO，不自动勾选。

## 每名成员使用 AI

每个任务默认单 agent，先读 AGENTS 与 Issue；在短期分支内按范围修改、验证和同步相关文档。同一成员需要同时进行多个任务时再考虑独立 worktree，不引入额外编排框架。

任务指令应包含：Issue、可改范围、已确定契约、验收方式。例：读取 AGENTS.md 与当前 Issue；实现创建页交互，仅修改创建页和相关测试；复用事项服务接口，发现接口不足先提出变更；完成后报告实际验证与未验证项。

AI Review 可选启用；由仓库管理员在 Codex 的 GitHub 审查设置中启用后，按官方方式请求审查。AGENTS 规则、测试、人工批准与分支保护各自保留。使用 Figma 等设计工具属于可选项，不作为领取任务的前置条件。
