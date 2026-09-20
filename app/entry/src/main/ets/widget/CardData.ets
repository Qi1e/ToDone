import { Matter } from '../model/Types';
import { MatterStore } from '../store/MatterStore';

export interface CardBindingData {
  title: string;
  primary: string;
  secondary: string;
  quickActionLabel: string;
  quickActionType: string;
  matterId: string;
  clusterColor: string;
  summaryTitle: string;
  summaryPrimary: string;
  row1Title: string;
  row1Primary: string;
  row1Color: string;
  row2Title: string;
  row2Primary: string;
  row2Color: string;
  row3Title: string;
  row3Primary: string;
  row3Color: string;
}

export function createCardBindingData(store: MatterStore): CardBindingData {
  const summaryMatters = store.selectedSummaryCardMatters();
  const primaryMatter = store.selectedSingleCardMatter();
  const title = primaryMatter ? primaryMatter.title : '事项';
  const matterId = primaryMatter ? primaryMatter.id : '';
  const primary = primaryMatter ? store.cardPrimaryText(primaryMatter) : '暂无事项';
  const secondary = primaryMatter ? store.moduleSummary(primaryMatter) : '打开 App 创建事项';
  const color = primaryMatter ? store.clusterColor(primaryMatter.clusterId) : '#2F7BFF';
  const quickActionLabel = primaryMatter ? store.cardQuickActionLabel(primaryMatter) : '打开';
  const quickActionType = primaryMatter ? store.cardQuickActionType(primaryMatter) : 'open';

  return {
    title,
    primary,
    secondary,
    quickActionLabel,
    quickActionType,
    matterId,
    clusterColor: color,
    summaryTitle: '事项汇总',
    summaryPrimary: summaryMatters.length > 0 ? `${summaryMatters.length} 个显示事项` : '暂无事项',
    row1Title: rowTitle(store, summaryMatters, 0),
    row1Primary: rowPrimary(store, summaryMatters, 0),
    row1Color: rowColor(store, summaryMatters, 0),
    row2Title: rowTitle(store, summaryMatters, 1),
    row2Primary: rowPrimary(store, summaryMatters, 1),
    row2Color: rowColor(store, summaryMatters, 1),
    row3Title: rowTitle(store, summaryMatters, 2),
    row3Primary: rowPrimary(store, summaryMatters, 2),
    row3Color: rowColor(store, summaryMatters, 2)
  };
}

function rowTitle(store: MatterStore, matters: Matter[], index: number): string {
  return matters.length > index ? matters[index].title : '未设置';
}

function rowPrimary(store: MatterStore, matters: Matter[], index: number): string {
  return matters.length > index ? store.cardPrimaryText(matters[index]) : '打开 App 管理';
}

function rowColor(store: MatterStore, matters: Matter[], index: number): string {
  return matters.length > index ? store.clusterColor(matters[index].clusterId) : '#D8DEE8';
}
