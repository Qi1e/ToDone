# ToDone

ToDone 是 HarmonyOS 原生个人事项系统。用户创建事项并选择记录、计数、截止日期、备注或列表等信息；列表支持一层独立事项引用，产品边界与功能范围见 [产品规格](PROJECT_SPEC.md)。

当前平台方向：HarmonyOS NEXT 优先；其他 Android 系统仅作为后续可行性评估，不属于本轮兼容承诺。

## 开发入口
- 用 DevEco Studio 打开 `app/` 工程；Codex / VS Code 打开仓库根目录。
- [运行与验证](docs/development.md)：环境、检查脚本和实机验收。
- [当前任务与验证状态](TODO.md)：最新进度的唯一入口。
- [AI 工作约定](AGENTS.md)：任务分级、自动维护与完成标准。

## 项目资料
| 资料 | 内容 |
| --- | --- |
| [产品规格](PROJECT_SPEC.md) | 需求、边界与长期方向 |
| [技术决策](DECISIONS.md) | 重要选择、理由和替代关系 |
| [变更记录](CHANGELOG.md) | 功能变化和修复 |
| [数据模型](docs/data-model.md) | 实现结构与持久化 |
| [模块系统](docs/module-system.md) | 模块行为与需求差距 |
| [设计原则](docs/design-principles.md) | UI 设计导航 |
| [服务卡片验证](docs/widget-technical-validation.md) | 卡片逐项验收 |

## 技术与目录
ArkTS / ArkUI、Stage 模型、preferences 本地存储、服务卡片。
`app/` 存放应用工程，`docs/` 存放专题说明，`scripts/` 存放无额外 npm 依赖的开发检查入口。
