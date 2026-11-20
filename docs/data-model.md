# 数据模型

实现结构以 [Types.ets](../app/entry/src/main/ets/model/Types.ets) 为准，存储行为见 [MatterStore.ets](../app/entry/src/main/ets/store/MatterStore.ets)。本文解释结构；需求中的建议字段不代表全部已实现。代码结构或存储机制改变时同步本文件。

V1 只保留一个核心对象：事项。短期备忘、日期事项和长期记录都使用同一个模型。

## Matter / 事项

```ts
interface Matter {
  id: string
  title: string
  description?: string
  createdAt: number
  updatedAt: number
  archived: boolean
  orderIndex: number
  clusterId?: string
  enabledModules: ModuleInstance[]
}
```

## ModuleInstance / 模块实例

模块是事项启用的能力，不是事项类型。

```ts
interface ModuleInstance {
  id: string
  matterId: string
  moduleType: ModuleType
  configJson: string
  createdAt: number
  updatedAt: number
}
```

V1 用户可选信息：

- 记录
- 计数
- 截止日期
- 备注
- 列表

`Countdown` 可以继续存在于旧数据和内部派生结构中，但不出现在创建选择器或详情页的信息选择器中；它始终由 `Deadline` 计算。

## ChecklistItem / 列表项

```ts
interface ChecklistItem {
  id: string
  matterId: string
  title: string
  completed: boolean
  entryType?: 'text' | 'matter_ref'
  targetMatterId?: string
  orderIndex: number
  createdAt: number
  updatedAt: number
}
```

`entryType: 'text'` 是普通文字项；`entryType: 'matter_ref'` 是对另一个独立事项的引用。引用事项仍可单独编辑、归档、删除，并可出现在首页或桌面卡片中。

V1 只允许一层引用，不建立递归父子树。

## Cluster / 弱关联簇

```ts
interface Cluster {
  id: string
  color: string
  createdAt: number
  updatedAt: number
}
```

簇不命名、不分层、不作为分类系统。一个事项 V1 最多属于一个簇。

## 本地持久化

事项沿用 AppState 结构，当前保存到原生 RDB 的带版本快照；旧 `todone_store` / `app_state_v1` 仅作首次导入来源：

```ts
interface AppState {
  matters: Matter[]
  clusters: Cluster[]
  eventRecords: EventRecordEntry[]
  counterEntries: CounterEntry[]
  checklistItems: ChecklistItem[]
}
```

业务数据、卡片选择和注册 ID 均属于同一个提交范围。生产适配器与并发规则见下文。草稿与时间线继续独立存储。

「补充示例」按四张示例事项的固定 ID 查找缺项，把新增事项和所属列表项一起写入当前快照。已有事项的排序、模块、归档状态和桌面卡片选择均沿用原值。[示例定义](../app/entry/src/main/ets/model/Defaults.ets)

## 独立时间块

[TimelineBlock](../app/entry/src/main/ets/contracts/TimelineService.ets) 保存稳定 ID、标题、开始与结束时间戳（毫秒）、备注及可选的 tagId 和 repeat。每段重复规则存一条系列记录，startAt / endAt 保存用于计算重复的起始时段。标签含稳定 ID、名称（可含 emoji）和 #RRGGBB 颜色。从时间线创建的独立块单独读写，无须创建同名 Matter。事项快照的存储位置见本页的一致性实现；两者没有跨存储原子提交。

[TimelineServices](../app/entry/src/main/ets/application/TimelineServices.ets) 复用 preferences 适配器，在 `todone_timeline` 文件的 `timeline_blocks_v1` 键保存时间块和标签。旧版数组及 v2 至 v5 快照均可读取。无重复字段的日程按单次显示，旧重复系列保留原来已经排出的历史。下次成功写入时升为 v6，系列可存生效日、截止日（不含当天）和排除日期集合。上述值均按当地年月日编号，改钟点仍保留删除范围。单次编辑保存在系列内，以修改前那次的开始时间识别。修改这次及以后的规则时，旧段截至选中日，新段与旧段在同一次写入中提交，之后按各段编辑和删除。若新频率无法容纳原本单独编辑过的一次，保留它的实际时段与内容，转为可独立编辑的日程。时间块和标签共用写入队列；频率由当前已保存日程计算。日期圈、小窗和网格共用[重复日期计算](../app/entry/src/main/ets/domain/TimelineRecurrence.ets)，只展开与查询窗口相交的时段。同一系列的各次以系列 ID 和当次开始时间区分，整组编辑或删除按持久化 ID 执行，删除单次和截断还会核对实例开始时间。把过去的单次转为重复时，原来那次独立留存；新系列复用原 ID，从设置日起按规则排期。[业务服务](../app/entry/src/main/ets/domain/DefaultTimelineService.ets) 按同一 ID 新增或更新，串行执行写入，等待 flush 完成后发布新的列表。读取损坏快照时向页面返回读取失败。开始与结束构成左闭右开区间，切分到日期列和重叠排布在[布局计算](../app/entry/src/main/ets/domain/TimelineLayout.ets)中完成。

旧版存档未记录创建时区。遇到跨夏令时的单次修改，读入时可按系列日期和匹配的钟点偏移重新关联原来的那次日程，实际修改的起止时刻和资料照原样保留。单纯打开日程不会写入存档。

时间块和单次例外可保存相对开始时间的提前分钟数（0 表示开始时）及附件列表。老日程默认关闭提醒，附件为空。每个附件记录 ID、名称、类型和来源。文件、图片与音频由系统选择器导入到应用私有目录，快照仅保存文件名。新输入的网址作为备注原文保存，显示时识别链接。旧版已保存的网址附件沿用原地址，仍可打开和移除。清理文件前核对系列、单次例外、草稿和正在导入的引用。系统提醒按实际实例及其提前量排序，改期、删除或再次进入应用时与系统已登记的提醒核对。

## 协作开发边界

- [事项服务契约](../app/entry/src/main/ets/contracts/MatterService.ets) 复用 Types.ets，不另建平行模型；定义创建参数、失败结果、查询和保存重试。
- [创建业务](../app/entry/src/main/ets/domain/DefaultMatterService.ets) 在独立快照中校验并一次提交事项、初始文字项与关联，避免校验失败留下部分数据。
- [共享引用规则](../app/entry/src/main/ets/domain/MatterLinks.ets) 同时供旧 MatterStore 与新创建服务使用，保持一层独立引用语义。
- MatterStore 作为旧页面与系统卡片的异步门面，所有修改委托统一事务仓库。[RDB 适配器](../app/entry/src/main/ets/store/RdbMatterPersistence.ets) 负责事项存储；preferences 适配器继续服务时间线。
- 现有 AppState 还包含 `singleCardMatterId`、`summaryCardMatterIds`、`cardFormIds`，字段以 Types.ets 为准，新服务整份保留这些字段。
- 写入契约已从 `commitState(oldSnapshot)` 改为 `transact(operation, change)`。失败结果中的事项 ID 是待确认请求的稳定 ID，不表示事项已发布或保存。重试原操作，持久化确认后才发布视图。
- [内存 Mock](../app/entry/src/main/ets/mocks/MockMatterService.ets) 与真实实现复用相同业务规则，只替换仓库，不接触 SDK、preferences 或卡片。

## 创建与编辑

草稿按新建、来源列表 ID 或编辑事项 ID 存入独立 preferences。确认后由 MatterService 校验并一次提交事项与引用。保存标识随事项持久化，恢复未确认的提交后可以重试。编辑快照包含表单配置和列表内容，用于识别过期草稿；计数流水、记录和勾选状态保留当前值。

disabledModules 保存关闭的模块配置。日期用途缺省为截止时间；计数初始值缺省为零，累计值为初始值加流水之和。编辑原有配置沿用模块与列表项 ID。

## 数据一致性实现

2026-11-20 在本地 `f3a8ba6` 基础上实施。App 与 FormExtension 共用业务提交规则，生产后端采用系统 RDB；不增加依赖，也不改变事项、模块和一层引用的产品模型。

### 分层与提交顺序

| 文件 | 职责 |
| --- | --- |
| [MatterState](../app/entry/src/main/ets/domain/MatterState.ets) | 从旧 MatterStore 提取的同步业务规则，只修改候选状态。 |
| [DefaultMatterService](../app/entry/src/main/ets/domain/DefaultMatterService.ets) | 创建、编辑校验，保留请求和编辑基线。 |
| [TransactionalMatterRepository](../app/entry/src/main/ets/domain/TransactionalMatterRepository.ets) | 读取最新版本、重放操作、去重、冲突重试和提交确认。没有 SDK 依赖。 |
| [MatterPersistence](../app/entry/src/main/ets/contracts/MatterPersistence.ets) | `read()` 与原子 `compareAndSwap(expectedRevision, next)` 契约。 |
| [RdbMatterPersistence](../app/entry/src/main/ets/store/RdbMatterPersistence.ets) | 原生数据库、旧数据导入、版本条件更新。 |
| [MatterStore](../app/entry/src/main/ets/store/MatterStore.ets) | 兼容页面和卡片的异步入口，成功后的视图通知。 |

每个操作携带 `id` 和请求指纹 `fingerprint`。服务传入同步回调，在最新状态的副本上执行。回调可能因版本竞争重复执行，不能在其中刷新 UI、发送卡片消息或改变外部状态。

1. 读取已提交的状态、revision 和回执。页面缓存仅用于展示。
2. 若有相同 ID、相同指纹的回执，直接返回原结果；同 ID 不同内容报 `MAT-OPERATION`。
3. 在候选状态上应用业务规则，生成下一版本并加入回执。校验失败不写入、不发布候选状态。
4. 通过原子版本条件提交。如果其他入口已更新版本，重新读取并重放，最多 32 次；耗尽后报 `MAT-BUSY`，沿用原 ID 重试。
5. 提交确认后发布缓存、通知页面、请求卡片刷新。刷新失败不回滚业务数据。
6. 写入抛错时再读持久化回执：查到则确认原结果；未查到或读取仍失败则向入口报告未确认，不发布候选状态。

例如卡片 A 的 +1、App 新建、卡片 B 的 +1，分别作用于最新状态，最终计数为 2，新增事项仍保留。A 的旧请求再次到达时，回执阻止重复计数。各实例自己的 Promise 队列只负责调用顺序，跨实例安全由底层原子条件更新提供。

### 当前 RDB 适配器

数据库 `todone_matter.db` 中 `matter_state` 表只有 `id=1` 这一行，列为 `revision` 与 `payload`。payload 是 `{ version: 1, revision, state, receipts }`；每份回执保存 ID、指纹和序列化结果。提交等价于：

```sql
UPDATE matter_state SET revision = ?, payload = ?
WHERE id = 1 AND revision = ?;
```

原生实现使用 `RdbPredicates` 和 `update()`，以受影响行数判定是否提交。版本判断、状态和回执在同一 SQL 写入中生效。独立进程不可能同时以同一个旧版本覆盖这一行。SQLite 的不同连接通过数据库锁协调写入，详见 [SQLite 隔离说明](https://www.sqlite.org/isolation.html)；目标 SDK 的原生调用另以构建与模拟器验证。

选择这个过渡实现是为了直接获得跨进程提交边界。XML preferences 缺少此保证，不再承担事项业务写入；因此无需额外设计一个有后台生命周期约束的临时写入服务。

单行快照会随历史和回执增长。系统 RDB 文档指出过大的单行可能写入成功却无法读取，因此适配器在 UTF-8 编码超过 **1,500,000 字节**时先报 `MAT-SIZE`，不执行写入或导入。[官方 RDB 约束](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/database/data-persistence-by-rdb-store.md) 这只是安全边界，分表、回执归档和大数据量性能仍待完善，不能把该快照布局当作长期容量方案。

### 入口、重试与视图

- 创建/编辑沿用草稿 token。失败后保留原内容与 token，输入锁定、重试按钮可用；跨重启恢复草稿继续确认原请求。
- 计数、记录、勾选、列表、关联、排序、归档、删除、示例操作与卡片注册/选择全部经过 `transact`。页面等待 Promise 后才清空输入、显示完成提示或请求刷新。
- 详情和卡片设置订阅提交通知，App 进入前台重读，卡片每次事件/更新也重读。详情模块按提交后的状态重建，避免存储变化而读数不变。
- 新版单事项卡片在发送端生成操作 ID，结果未确认期间按钮用于重试同一次操作。绑定数据携带该实例最后确认的操作 ID，收到确认后下一次点击才生成新 ID。
- 页面内旧操作在同进程保留失败 ID；它们尚未实现跨进程退出的待确认请求日志。创建草稿可跨重启恢复；卡片渲染进程丢失未确认请求身份、旧版无 ID 消息重投递仍需继续验收与完善。
- 不自动清理回执。只有确定旧请求不会再重投递，才能安全归档或清理；不能按任意数量截断后宣称继续幂等。

### 旧数据与恢复

1. 首次读取没有状态行时，清除旧 preferences 的进程缓存，再读取 `todone_store` 的 `app_state_v1`。缺少旧可选数组时按旧语义补默认值，其余字段、禁用模块、历史和卡片 ID 保留。
2. 只有旧键确实不存在才创建初始演示数据。JSON 或结构错误直接返回错误；不拿示例覆盖原存档。RDB 快照损坏时也保留原内容并提供重新读取入口。
3. 用 `INSERT OR IGNORE` 建立初始行。App 和卡片同时导入时只保留先成功的一份，再读取真正提交的内容。旧 preferences 文件保持只读，后续只写 RDB。
4. 升级前保留旧文件与草稿备份。若需回退旧版，先停止 App/卡片写入，从 RDB 导出最新 `state` 为旧键格式，核对后再回退。**只恢复首次旧备份会丢掉切换后的新增数据。** 本轮没有实现用户可见的导出/回退按钮。

### 后续分表复用方式

未来按事项、模块、计数、记录、引用和回执分表，只替换 `MatterPersistence` 的映射与原子提交实现。`read()` 必须在同一读取事务中组装一致快照；`compareAndSwap()` 在写事务内核对 revision，写业务记录、操作回执与新版本，统一提交或回滚。回执 ID 建唯一约束。不能独立读取各张表后拼接不同版本，也不能把状态与回执分开提交。

`MatterState`、`applyEditor`、请求指纹、幂等恢复与冲突重试算法继续复用；适配器仍需做 schema 迁移、字段映射和存储专项验证。时间线目前有独立存储边界，若以后跨入口写入或与事项原子联动，需要另行接入相应事务范围。

### 验证与剩余边界

[事务回归](../tests/matter-transactions.test.mjs) 使用生产领域代码，覆盖交替写入、独立仓库并发、写前失败、提交响应丢失、恢复读取失败、重复请求、请求内容冲突、候选状态隔离、过期编辑、删除后的旧操作与旧数据兼容。两个真正的 Node 进程各用独立 SQLite 连接，从同一旧版本开始完成 32 次计数，并验证重启重放不重复。

原生模拟器验证范围与结果见 [开发说明](development.md#2026-11-20-事项一致性修复验证) 和 [卡片清单](widget-technical-validation.md)。真实磁盘耗尽、写入瞬间断电、长期容量、物理设备及正式 Hypium 配置仍未验收。故障注入的拒绝写入与损坏快照不等同于这些场景。
