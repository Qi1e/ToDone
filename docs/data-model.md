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

## 协作开发边界

- [事项服务契约](../app/entry/src/main/ets/contracts/MatterService.ets) 复用 Types.ets，不另建平行模型；定义创建参数、失败结果、查询和保存重试。
- [创建业务](../app/entry/src/main/ets/domain/DefaultMatterService.ets) 在独立快照中校验并一次提交事项、初始文字项与关联，避免校验失败留下部分数据。
- [共享引用规则](../app/entry/src/main/ets/domain/MatterLinks.ets) 同时供旧 MatterStore 与新创建服务使用，保持一层独立引用语义。
- MatterStore 实现仓库接口，并继续服务尚未迁移的旧页面与系统卡片。[preferences 适配器](../app/entry/src/main/ets/store/PreferencesStateStorage.ets) 保留 `todone_store` / `app_state_v1` 与现有 JSON 数据，不做迁移。
- 现有 AppState 还包含 `singleCardMatterId`、`summaryCardMatterIds`、`cardFormIds`，字段以 Types.ets 为准，新服务整份保留这些字段。
- `commitState` 先发布内存状态，再等待 flush；失败不承诺回滚。创建结果返回仍存在的事项 ID，重试提交当前快照，避免重复创建；未经 flush 确认不报告保存成功。
- [内存 Mock](../app/entry/src/main/ets/mocks/MockMatterService.ets) 与真实实现复用相同业务规则，只替换仓库，不接触 SDK、preferences 或卡片。
