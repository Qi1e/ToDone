# 开发与验证

制作或核对页面原型时，参考[界面开发手册](ui-handbook/README.md)中的效果图和交互说明。

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
- 默认执行编译验证；实机或模拟器操作只在用户明确要求时进行。以下设备验收步骤在获得该要求后执行，未运行项保留状态。
- 页面变化：编译后在相关设备上打开页面，检查文字、布局与交互。
- 存储变化：创建/修改测试事项，结束进程再打开检查数据；使用测试数据，涉及迁移先确认恢复方式。
- 排序/弱关联变化：操作前后核对列表顺序，再重启检查。
- 卡片变化：按 [卡片清单](widget-technical-validation.md) 更新对应结果。
- 本地 Hypium 和设备侧 `ohosTest` 共用同一个[套件入口](../app/entry/src/ohosTest/ets/test/List.test.ets)，覆盖事项操作、翻页遮挡和末尾回弹。触控手感仍需在设备上核对。

## 运行本地 Hypium

用 DevEco 打开 `app/`，安装锁文件中已有的依赖（`ohpm install`）。创建 Hvigor 运行配置，将工作目录设为 `app/`，使用下列参数运行本地套件。

```text
--mode module -p module=entry@default -p product=default -p pageType=page -p isLocalTest=true -p unitTestMode=true -p buildRoot=.test -p unit.test.replace.page=../../../.test/testability/pages/Index test --no-daemon
```

逐项结果和通过数见 `app/entry/.test/default/intermediates/test/coverage_data/test_result.txt`。设备上的 Instrument Test 需另行运行。

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

它调用原文档检查、检查 scripts/ 中 Node 脚本语法，并执行事项服务、[事项事务与双进程 SQLite 回归](../tests/matter-transactions.test.mjs)以及[时间线业务回归](../tests/timeline.test.mjs)。后者使用真实业务代码与临时文件验证重新读回、失败重试、跨日与重叠。设备上的 preferences、原生组件、系统键盘和触控另做验收。不运行 npm install，不修改 SDK 或原 `verify.mjs` 的通过条件。

测试读取白名单中的真实无 SDK 依赖 `.ets` 源码，用 Node 内置的实验性 `stripTypeScriptTypes` 转换到临时目录执行；仅移除已知接口/类型导入，不编译 ArkUI，也不验证 ArkTS 严格模式。Node 小版本升级可能影响该实验性转换入口，变更 Node 时须重新运行检查。

[GitHub Actions](../.github/workflows/ci.yml) 在 PR 和 main 推送上运行同一命令，稳定检查名为 `portable-checks`。状态检查配置见 [协作说明](../CONTRIBUTING.md)。CI 结果不能充当 `assembleHap`、Hypium、preferences 重启持久化或系统卡片验收证据。

2026-11-13，独立时间块首个原生切片在 macOS 使用 Node 24.14.0 执行 `node scripts/check-ci.mjs`：16 份文档路径检查、8 项既有业务测试和 7 项时间线测试通过。`node scripts/verify.mjs --build` 因缺本机配置退出 2，未启动编译。Hypium 与设备验收待在目标 DevEco 环境执行。

## 契约与 Mock 开发

创建页和首页查询通过 [MatterService](../app/entry/src/main/ets/contracts/MatterService.ets) 工作；由 [组装入口](../app/entry/src/main/ets/application/MatterServices.ets) 默认选择真实实现。

本地开发可在首个页面创建前显式调用 `MatterServices.setForPreview(new MockMatterService())`。Mock 保存在独立内存仓库，创建校验与真实服务一致；预览不初始化 RDB/preferences、不请求系统卡片刷新。首页尚未迁移的旧交互在预览模式禁用，只供列表查看；完整 UI 编辑只支持已迁移的创建页。提交时不保留调用预览切换的代码。

创建页在保存期间禁用重复提交和输入；保存失败若返回待确认 ID，则锁定输入并显示可点击的“重试保存”；该 ID 不表示事项已经保存。重试不重新创建事项。真实保存完成后才请求卡片刷新并返回，刷新是否成功仍按原设备清单验证。

## 2026-10-18 协作改造验证

- 基线：`3d9bff7`；范围为协作规则、PR / Issue 模板、CI 和创建 / 查询服务切片，原有效测试和检查命令保留。
- 当前环境 Node 24.14.1，执行 `node scripts/check-ci.mjs`：文档路径检查、脚本语法、8 项可移植业务回归通过。
- 当前环境缺少 ohpm、Hvigor、hdc 和 tools.local.json，未执行 HAP 构建、Hypium、preferences 重启或设备 UI / 卡片验收。
- 增加 `app/entry/src/ohosTest/ets/test/List.test.ets` 注册原 MatterStore 套件，原测试文件不改动。目标 DevEco 的测试运行配置和设备执行仍需核实，不猜测本机测试命令。
- 远程 Actions 状态由 PR 检查显示，不能把本地通过写成远程已通过；main 分支保护需单独配置，未完成项在 TODO 跟踪。

## 2026-11-17 至 18 原生验收

- 基线 `main@84d107c`。Pura 90 模拟器，HDC `127.0.0.1:5555`，`OpenHarmony-6.1.1.125`，API 24。本机已有签名配置下执行 `node scripts/verify.mjs --build` 通过，生成签名 HAP。此轮为增量构建。
- Node 24.19.0 的 `node scripts/check-ci.mjs` 通过 76 项测试，Demo 两个测试文件通过 10 项。布局、数据故障和桌面卡片结果见 [验收报告](product-validation.md)。
- 原仓库执行 `--mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` 失败，错误码 `00304060`，缺少 `entry/src/ohosTest/module.json5`。聚合文件存在并不构成可运行配置。
- 在本机临时副本保留原 `test/` 套件，补入已安装 DevEco 的 Stage 测试模板清单、TestAbility、OpenHarmonyTestRunner 与资源后，`assembleHap` 成功。安装测试 HAP 后执行 `hdc -t 127.0.0.1:5555 shell aa test -b com.example.todone -m entry_test -s unittest OpenHarmonyTestRunner -w 20`，结果为 5 tests、0 failure、0 error、5 pass。
- 上述 Hypium 验证原有 MatterStore 逻辑，没有覆盖 ArkUI 响应式、系统 preferences 失败或 App/卡片多实例交替写入。正式测试入口仍待补齐，本轮临时文件不进入仓库。
- 本轮移除临时 `entry_test` 模块时，系统也移除了桌面入口与卡片。已重装正式包、按原布局重建三张卡，业务数据与草稿恢复，卡片 ID 更新为系统新分配值。后续避免把未经验证的测试模块清理操作用于含用户桌面配置的环境。

## 2026-11-20 事项一致性修复验证

- 基线为本地 `main@f3a8ba6`，新分支 `codex/matter-consistency`。沿用本机签名与 SDK，没有升级或新增依赖。最终 `node scripts/verify.mjs --build` 通过 ArkTS 编译和签名 HAP 构建。
- Node 24.19.0 执行 `node scripts/check-ci.mjs`：110 项通过，其中 11 项为新增事务回归；两个独立 Node 进程和 SQLite 连接完成 32 次并发计数，同一操作重放不重复。没有把这组检查写成原生 RDB 或 Hypium 通过。
- 原 5 项 Hypium 断言保留，测试对象调整为提取后的 `MatterState` 业务规则；本轮未运行 Hypium，因为正式测试模块入口仍缺失，不再在含用户卡片的环境安装/卸载临时测试模块。
- 设备沿用 Pura 90 模拟器，HDC `127.0.0.1:5555`，OpenHarmony 6.1.1.125 / API 24。安装本轮签名 HAP，以真实 UI、系统卡片、布局树及数据库快照核对以下结果。

| 场景 | 观察结果 |
| --- | --- |
| 原 preferences 导入 | 8 个原事项及所有业务字段逐字段一致，3 个卡片 ID 保留；旧事项文件与草稿原始字节未变化。 |
| App/卡片交替写入 | 卡片 +1、App 新建另一事项、另一张卡 +1，最终两笔计数和新事项均保留；冷启动读回为 2。 |
| 详情即时反馈 | 计数从 2 到 3；记录出现时间戳；勾选从 0/1 到 1/1；删除文字项及解除关联立即更新，关联目标仍存在。 |
| 原生拒绝写入 | 在测试数据库临时添加 `RAISE(ABORT)` 触发器。App 保持累计 3，显示保存尚未确认；移除触发器后原请求重试为 4，只有一笔新增。 |
| 卡片失败与恢复 | 同样拒绝写入时原记录数 1 保留，卡片出现错误和“确认保存”；解除故障后重试为 2，两张卡同步更新。 |
| 创建失败后重启 | 未发布失败事项；恢复草稿显示重试。实测发现父 List 禁用导致重试按钮无响应，修正禁用范围后同一草稿成功保存，只有一个事项。 |
| 损坏快照 | 临时替换测试 payload 为非法 JSON；MAT-JSON 与重新读取入口可见，数据库内容不被示例覆盖；恢复原行后同一进程重新读取成功。 |
| 容量边界 | 将隔离快照扩至约 1.61 MB，卡片保存报 MAT-SIZE，revision 不变；解除超限条件后可确认原请求。 |

故障注入只模拟明确拒绝写入与损坏内容。真实磁盘耗尽、系统断电、进程恰在提交边界被结束、长期容量和物理设备仍未验收。事项和草稿备份保留在本机临时目录 `todone-consistency-20261120`，不进入仓库。结束后原 8 个事项、历史、卡片选择与 3 个绑定 ID 逐字段恢复，原 preferences 和草稿逐字节一致，故障触发器和测试表已移除。本轮没有移除或重建桌面卡片。

故障界面证据：[拒绝写入](validation-assets/consistency-native-save-rejected.png)、[损坏存档](validation-assets/consistency-corrupt-error-confirmed.png)。用户随后明确以后仅在要求时做设备测试；最后的卡片待确认文案条件调整只做编译验证。

## 本地网页交互 Demo

运行 `node demo/web/server.mjs` 后访问 http://127.0.0.1:4173 。无外部依赖、仅监听本机，修改界面源码自动刷新。启动与数据边界见 [Demo 说明](../demo/web/README.md)。

该原型使用独立浏览器数据模型；不修改鸿蒙业务契约。可用 `node --test demo/web/model.test.mjs` 验证日期、计数及幂等更新，不能替代 ArkTS 构建、Hypium 或实机验收。

网页 Demo 的视觉值直接来自原生 `Theme.ets`，由 `theme-sync.mjs` 动态输出；运行 `node --test demo/web/model.test.mjs demo/web/theme.test.mjs` 检查业务与主题引用。页面按 1 CSS px 对应 1 vp 的布局单位展示，浏览器原生日期控件、字体与系统栏不作为鸿蒙最终视觉验收。
