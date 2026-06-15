# ToDone

ToDone 是一个 HarmonyOS 原生个人事项系统。它不是待办、日历、项目管理或习惯打卡工具；核心对象只有「事项」，用户通过为事项启用不同模块来记录和查看自己真正关心的内容。

## V1 范围

- 事项创建、编辑、删除、归档
- 首页事项列表与排序
- 弱关联簇
- 模块勾选
- 事件记录、计数、进度、截止日期、倒计时、备注、列表
- 基础单事项卡片与基础汇总卡片
- 本地数据持久化

## 技术路线

- HarmonyOS Stage 模型
- ArkTS / ArkUI
- `preferences` 轻量本地持久化
- Service Widget / 服务卡片基础结构

## 目录结构

```text
/
├─ PROJECT_SPEC.md
├─ README.md
├─ CHANGELOG.md
├─ DECISIONS.md
├─ TODO.md
├─ docs/
└─ app/
   ├─ AppScope/
   ├─ entry/
   ├─ build-profile.json5
   ├─ hvigorfile.ts
   └─ oh-package.json5
```

## 当前验证状态

本仓库已建立 HarmonyOS ArkTS 工程结构和 V1 业务代码。当前机器没有检测到 `ohpm` / `hvigor`，因此尚未完成本地 DevEco 编译验证。导入 DevEco Studio 后应先执行依赖同步与 M0 技术验证。

