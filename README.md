# ToDone

ToDone 是一个 HarmonyOS 原生个人事项系统。它不是待办、日历、项目管理或习惯打卡工具；核心对象只有「事项」，用户先创建事项，再选择要记录的信息，并在后续自然修改和持续记录。

## V1 范围

- 事项创建、编辑、删除、归档
- 首页事项列表与排序
- 弱关联簇
- 创建时选择记录、计数、截止日期、备注、列表等信息
- 事件记录、计数、截止日期、备注、文字列表
- 列表中关联独立事项，并在事项详情中查看其状态
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

本仓库已建立 HarmonyOS ArkTS 工程结构和 V1 业务代码。当前机器已通过 DevEco Studio 自带工具完成 `ohpm install`，`@ohos/hypium@1.0.18` 已安装；HarmonyOS 编译、原生 `DatePicker` 和服务卡片行为仍需在 DevEco Studio、模拟器或真机上验证。测试与上架工作不包含在当前实现范围内。
