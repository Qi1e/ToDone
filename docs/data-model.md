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

V1 使用单个 JSON 状态保存到 `preferences`：

```ts
interface AppState {
  matters: Matter[]
  clusters: Cluster[]
  eventRecords: EventRecordEntry[]
  counterEntries: CounterEntry[]
  checklistItems: ChecklistItem[]
}
```

这样可以先验证产品闭环，避免过早引入复杂数据层。

## 独立时间块

[TimelineBlock](../app/entry/src/main/ets/contracts/TimelineService.ets) 保存稳定 ID、标题、开始与结束时间戳（毫秒）、备注及可选的 tagId 和 repeat。每段重复规则存一条系列记录，startAt / endAt 保存用于计算重复的起始时段。标签含稳定 ID、名称（可含 emoji）和 #RRGGBB 颜色。从时间线创建的独立块单独读写，无须创建同名 Matter。原有事项快照仍使用原文件与键。

[TimelineServices](../app/entry/src/main/ets/application/TimelineServices.ets) 复用 preferences 适配器，在 `todone_timeline` 文件的 `timeline_blocks_v1` 键保存时间块和标签。旧版数组及 v2 至 v5 快照均可读取。无重复字段的日程按单次显示，旧重复系列保留原来已经排出的历史。下次成功写入时升为 v6，系列可存生效日、截止日（不含当天）和排除日期集合。上述值均按当地年月日编号，改钟点仍保留删除范围。单次编辑保存在系列内，以修改前那次的开始时间识别。修改这次及以后的规则时，旧段截至选中日，新段与旧段在同一次写入中提交，之后按各段编辑和删除。若新频率无法容纳原本单独编辑过的一次，保留它的实际时段与内容，转为可独立编辑的日程。时间块和标签共用写入队列；频率由当前已保存日程计算。日期圈、小窗和网格共用[重复日期计算](../app/entry/src/main/ets/domain/TimelineRecurrence.ets)，只展开与查询窗口相交的时段。同一系列的各次以系列 ID 和当次开始时间区分，整组编辑或删除按持久化 ID 执行，删除单次和截断还会核对实例开始时间。把过去的单次转为重复时，原来那次独立留存；新系列复用原 ID，从设置日起按规则排期。[业务服务](../app/entry/src/main/ets/domain/DefaultTimelineService.ets) 按同一 ID 新增或更新，串行执行写入，等待 flush 完成后发布新的列表。读取损坏快照时向页面返回读取失败。开始与结束构成左闭右开区间，切分到日期列和重叠排布在[布局计算](../app/entry/src/main/ets/domain/TimelineLayout.ets)中完成。

旧版存档未记录创建时区。遇到跨夏令时的单次修改，读入时可按系列日期和匹配的钟点偏移重新关联原来的那次日程，实际修改的起止时刻和资料照原样保留。单纯打开日程不会写入存档。

时间块和单次例外可保存相对开始时间的提前分钟数（0 表示开始时）及附件列表。老日程默认关闭提醒，附件为空。每个附件记录 ID、名称、类型和来源。文件、图片与音频由系统选择器导入到应用私有目录，快照仅保存文件名。新输入的网址作为备注原文保存，显示时识别链接。旧版已保存的网址附件沿用原地址，仍可打开和移除。清理文件前核对系列、单次例外、草稿和正在导入的引用。系统提醒按实际实例及其提前量排序，改期、删除或再次进入应用时与系统已登记的提醒核对。

## 协作开发边界

- [事项服务契约](../app/entry/src/main/ets/contracts/MatterService.ets) 复用 Types.ets，不另建平行模型；定义创建参数、失败结果、查询和保存重试。
- [创建业务](../app/entry/src/main/ets/domain/DefaultMatterService.ets) 在独立快照中校验并一次提交事项、初始文字项与关联，避免校验失败留下部分数据。
- [共享引用规则](../app/entry/src/main/ets/domain/MatterLinks.ets) 同时供旧 MatterStore 与新创建服务使用，保持一层独立引用语义。
- MatterStore 实现仓库接口，并继续服务尚未迁移的旧页面与系统卡片。[preferences 适配器](../app/entry/src/main/ets/store/PreferencesStateStorage.ets) 保留 `todone_store` / `app_state_v1` 与现有 JSON 数据，不做迁移。
- 现有 AppState 还包含 `singleCardMatterId`、`summaryCardMatterIds`、`cardFormIds`，字段以 Types.ets 为准，新服务整份保留这些字段。
- `commitState` 先发布内存状态，再等待 flush；失败不承诺回滚。创建结果返回仍存在的事项 ID，重试提交当前快照，避免重复创建；未经 flush 确认不报告保存成功。
- [内存 Mock](../app/entry/src/main/ets/mocks/MockMatterService.ets) 与真实实现复用相同业务规则，只替换仓库，不接触 SDK、preferences 或卡片。

## 创建与编辑

草稿按新建、来源列表 ID 或编辑事项 ID 存入独立 preferences。确认后由 MatterService 校验并一次提交事项与引用。保存标识随事项持久化，恢复未确认的提交后可以重试。编辑快照包含表单配置和列表内容，用于识别过期草稿；计数流水、记录和勾选状态保留当前值。

disabledModules 保存关闭的模块配置。日期用途缺省为截止时间；计数初始值缺省为零，累计值为初始值加流水之和。编辑原有配置沿用模块与列表项 ID。
