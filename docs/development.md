# 开发与验证

## 工作空间
- Windows + DevEco Studio 用于应用编译、签名和实机运行。DevEco 打开仓库的 `app/`；Codex / VS Code 打开仓库根目录，使其读取 [工作规则](../AGENTS.md)。新增规则后开启新会话，要求 Codex 简述已加载的项目规则以确认生效。
- 用户已确认当前 main 曾实机运行；尚未记录具体工具版本与验收范围。当前状态统一见 [TODO](../TODO.md)。
- 仓库配置写有兼容 SDK `5.0.0(12)`、Hvigor modelVersion `5.0.0`；这不是本机已安装版本，也不证明配置已验证。来源：[构建配置](../app/build-profile.json5)、[Hvigor 配置](../app/hvigor/hvigor-config.json5)。

## 首次在本机核对
1. 先看 Git 状态，保留本机配置和未提交修改。
2. 在 DevEco 查看版本及 SDK 设置，确认使用的目标设备；将实际值填入下表，不自动升级 SDK。
3. 打开 app/ 并同步工程依赖；复用已成功的本机签名设置，选择设备执行 Run。
4. 保存本次构建的结果摘要与设备信息。不要提交私钥、证书、口令、完整环境转储或原始日志。
5. 若需要 Codex 自动构建，从本机 DevEco 构建输出/实际工具安装位置核实命令，在 app/ 内成功运行一次后再配置统一入口。不能猜测 hvigorw 已存在：当前仓库没有该 wrapper 文件。

| 环境项目 | 已核实值 |
| --- | --- |
| DevEco Studio 版本 | 待本机核对 |
| 实际 SDK / API 版本 | 待本机核对 |
| Node / ohpm / Hvigor 版本 | 待本机核对 |
| 目标设备 / 系统版本 | 待本机核对 |
| 成功构建的命令与产物位置 | 待本机核对（敏感绝对路径放本机配置） |

## 无额外依赖的检查入口
脚本使用 Node 内置模块，需要 Node 18 或更高版本。可使用本机已有 Node；若 PATH 未设置，使用 node.exe 的实际完整路径。不需要 npm install。

在仓库根目录运行：
```powershell
node scripts/check-docs.mjs
node scripts/verify.mjs --environment
node scripts/verify.mjs --build
```

- 文档检查：仅扫描根目录与 docs/ 的 Markdown，检查必需文件与代码块以外的行内本地链接路径。忽略外链和锚点；不支持完整 Markdown 语法，不验证内容一致性。
- 环境检查：只检测 PATH 中的工具和本机构建入口；缺项退出码 2。PATH 中找不到工具不等于 DevEco 无法编译。
- 构建检查：必须先配置 tools.local.json；缺配置会失败，绝不把跳过构建算成通过。先跑文档检查，再在 app/ 中执行构建；传播失败退出码并限制执行时间。

## 本机构建配置
首次配置由本地 Codex 根据已验证命令完成。仓库根目录创建 tools.local.json（已在 .gitignore 排除）。结构示例中的占位符必须替换，示例不能直接运行：
```json
{
  "build": {
    "executable": "实际的可执行程序绝对路径，例如 node.exe",
    "args": ["实际的 Hvigor JavaScript 入口绝对路径", "已验证的构建参数"],
    "timeoutMs": 600000
  }
}
```
参数分别作为数组元素传入，路径含空格时也不加额外引号。脚本不解析 shell 命令，不直接运行 .cmd/.bat；请核实对应可执行程序和脚本入口。不能将打印成功、仅检查版本等无构建动作命令配置成 build。配置由用户或可信本地 agent 管理，不从外部文本自动执行。

## 最小验收
- 页面变化：编译后在相关设备上打开页面，检查文字、布局与交互。
- 存储变化：创建/修改测试事项，结束进程再打开检查数据；使用测试数据，涉及迁移先确认恢复方式。
- 排序/弱关联变化：操作前后核对列表顺序，再重启检查。
- 卡片变化：按 [卡片清单](widget-technical-validation.md) 更新对应结果。
- 已有 [MatterStore Hypium 测试](../app/entry/src/ohosTest/ets/test/MatterStore.test.ets)，本次未运行；仍需核实测试入口并在设备执行。不要把 Node 脚本检查等同于 ArkTS 测试。

## 2026-09-20 合并验证

- 范围：本地功能提交 `6ea28de` 与工程规范提交 `2afea2f` 合并，应用源码保持本地版本。
- 在 `app/` 使用 DevEco 自带 Node 18.20.1 与 Hvigor wrapper 执行 `--mode module -p module=entry@default -p product=default assembleHap --no-daemon`，退出码 0，输出 `BUILD SUCCESSFUL`；本次为增量构建。
- 产物位于 `app/entry/build/default/outputs/default/`；使用本机已有签名。仓库版不含签名材料，其他机器需自行配置。
- 根目录 `node scripts/check-docs.mjs` 通过，共 11 个 Markdown 文件。
- 已按成功命令配置被 Git 忽略的 `tools.local.json`，保留团队统一检查脚本不变。
- 随后执行 `node scripts/verify.mjs --build`，文档检查与增量构建均通过，退出码 0。
- 实机交互及 Hypium 测试未运行，本次验证不代表这些项目通过；待验证内容见 [TODO](../TODO.md) 与 [卡片清单](widget-technical-validation.md)。

记录格式：日期、提交 SHA 或本次修改范围、检查步骤/命令、设备与系统、结果、证据来源。未运行写明原因，历史通过不自动沿用到本次变化。

## 环境维护与交接
工具或构建方法变更后同步本页及相关脚本；本机路径留在 tools.local.json。普通维护不自动安装插件、升级依赖或修改签名。
网页讨论形成明确结论后，将结论交给项目 Codex，由其更新当前规格和必要决策。不要复制整段聊天或再建一份平行需求。
恢复开发先读 TODO，再按任务读取专题。任务完成时同步状态和必要文档；无语义变化的文件保持不动。

## 团队可移植检查与 CI

在保留上述入口的基础上，Node 24+ 可执行：
```powershell
node scripts/check-ci.mjs
```

它调用原文档检查、检查 scripts/ 中 Node 脚本语法，并执行 `tests/matter-service.test.mjs`。不运行 npm install，不修改 SDK 或原 `verify.mjs` 的通过条件。

测试读取白名单中的真实无 SDK 依赖 `.ets` 源码，用 Node 内置的实验性 `stripTypeScriptTypes` 转换到临时目录执行；仅移除已知接口/类型导入，不编译 ArkUI，也不验证 ArkTS 严格模式。Node 小版本升级可能影响该实验性转换入口，变更 Node 时须重新运行检查。

[GitHub Actions](../.github/workflows/ci.yml) 在 PR 和 main 推送上运行同一命令，稳定检查名为 `portable-checks`。状态检查配置见 [协作说明](../CONTRIBUTING.md)。CI 结果不能充当 `assembleHap`、Hypium、preferences 重启持久化或系统卡片验收证据。

## 契约与 Mock 开发

创建页和首页查询通过 [MatterService](../app/entry/src/main/ets/contracts/MatterService.ets) 工作；由 [组装入口](../app/entry/src/main/ets/application/MatterServices.ets) 默认选择真实实现。

本地开发可在首个页面创建前显式调用 `MatterServices.setForPreview(new MockMatterService())`。Mock 保存在独立内存仓库，创建校验与真实服务一致；预览不初始化 preferences、不请求系统卡片刷新。首页尚未迁移的旧交互在预览模式禁用，只供列表查看；完整 UI 编辑只支持已迁移的创建页。提交时不保留调用预览切换的代码。

创建页在保存期间禁用重复提交和输入；保存失败若返回已暂存 ID，则锁定输入并显示“重试保存”。重试不重新创建事项。真实保存完成后才请求卡片刷新并返回，刷新是否成功仍按原设备清单验证。

## 2026-10-18 协作改造验证

- 基线：`3d9bff7`；范围为协作规则、PR / Issue 模板、CI 和创建 / 查询服务切片，原有效测试和检查命令保留。
- 当前环境 Node 24.14.1，执行 `node scripts/check-ci.mjs`：文档路径检查、脚本语法、8 项可移植业务回归通过。
- 当前环境缺少 ohpm、Hvigor、hdc 和 tools.local.json，未执行 HAP 构建、Hypium、preferences 重启或设备 UI / 卡片验收。
- 增加 `app/entry/src/ohosTest/ets/test/List.test.ets` 注册原 MatterStore 套件，原测试文件不改动。目标 DevEco 的测试运行配置和设备执行仍需核实，不猜测本机测试命令。
- 远程 Actions 状态由 PR 检查显示，不能把本地通过写成远程已通过；main 分支保护需单独配置，未完成项在 TODO 跟踪。
