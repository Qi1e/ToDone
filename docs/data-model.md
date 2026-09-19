# 数据模型

实现结构以 [Types.ets](../app/entry/src/main/ets/model/Types.ets) 为准，存储行为见 [MatterStore.ets](../app/entry/src/main/ets/store/MatterStore.ets)。本文解释结构；需求中的建议字段不代表全部已实现。代码结构或存储机制改变时同步本文件。

V1 只保留一个核心对象：事项。

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

V1 模块：

- 事件记录
- 计数
- 进度
- 截止日期
- 倒计时
- 备注
- 列表

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

