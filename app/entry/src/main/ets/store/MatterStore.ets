import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { daysUntil, isToday } from '../common/DateFormat';
import {
  CLUSTER_COLORS,
  createId,
  createMatter,
  createModuleInstance,
  createSeedState,
  defaultConfigJson,
  moduleLabel
} from '../model/Defaults';
import {
  AppState,
  ChecklistItem,
  Cluster,
  CounterEntry,
  CreateMatterIntent,
  DeadlineConfig,
  EventRecordEntry,
  Matter,
  ModuleInstance,
  ModuleType,
  NoteConfig,
  ProgressConfig
} from '../model/Types';

const STORE_NAME = 'todone_store';
const STATE_KEY = 'app_state_v1';

export class MatterStore {
  private static instance: MatterStore = new MatterStore();
  private pref?: preferences.Preferences;
  private ready: boolean = false;
  private state: AppState = createSeedState();

  static getInstance(): MatterStore {
    return MatterStore.instance;
  }

  init(context: common.UIAbilityContext | common.FormExtensionContext): void {
    if (this.ready) {
      return;
    }

    try {
      this.pref = preferences.getPreferencesSync(context, { name: STORE_NAME });
      const raw = this.pref.getSync(STATE_KEY, '') as string;
      if (raw && raw.length > 0) {
        this.state = this.normalizeState(JSON.parse(raw) as AppState);
      } else {
        this.state = createSeedState();
        this.save();
      }
      this.ready = true;
    } catch (error) {
      this.state = createSeedState();
      this.ready = true;
    }
  }

  private normalizeState(input: AppState): AppState {
    return {
      matters: (input.matters ?? []).sort((a: Matter, b: Matter) => a.orderIndex - b.orderIndex),
      clusters: input.clusters ?? [],
      eventRecords: input.eventRecords ?? [],
      counterEntries: input.counterEntries ?? [],
      checklistItems: input.checklistItems ?? [],
      singleCardMatterId: input.singleCardMatterId ?? '',
      summaryCardMatterIds: input.summaryCardMatterIds ?? (input.matters ?? [])
        .filter((matter: Matter) => !matter.archived)
        .sort((a: Matter, b: Matter) => a.orderIndex - b.orderIndex)
        .slice(0, 3)
        .map((matter: Matter) => matter.id),
      cardFormIds: input.cardFormIds ?? []
    };
  }

  private save(): void {
    if (!this.pref) {
      return;
    }
    try {
      this.pref.putSync(STATE_KEY, JSON.stringify(this.state));
      this.pref.flush();
    } catch (error) {
    }
  }

  allMatters(): Matter[] {
    return this.state.matters.slice().sort((a: Matter, b: Matter) => a.orderIndex - b.orderIndex);
  }

  activeMatters(): Matter[] {
    return this.allMatters().filter((matter: Matter) => !matter.archived);
  }

  archivedMatters(): Matter[] {
    return this.allMatters().filter((matter: Matter) => matter.archived);
  }

  findMatter(id: string): Matter | undefined {
    return this.state.matters.find((matter: Matter) => matter.id === id);
  }

  addMatter(intent: CreateMatterIntent): Matter {
    const matter = createMatter(intent, this.state.matters.length);
    this.state.matters.push(matter);
    this.reindexMatters();
    this.save();
    return matter;
  }

  updateMatter(id: string, title: string, description: string): void {
    const matter = this.findMatter(id);
    if (!matter || title.trim().length === 0) {
      return;
    }
    matter.title = title.trim();
    matter.description = description.trim();
    matter.updatedAt = Date.now();
    this.save();
  }

  archiveMatter(id: string, archived: boolean): void {
    const matter = this.findMatter(id);
    if (!matter) {
      return;
    }
    matter.archived = archived;
    matter.updatedAt = Date.now();
    this.reindexMatters();
    this.save();
  }

  deleteMatter(id: string): void {
    this.state.matters = this.state.matters.filter((matter: Matter) => matter.id !== id);
    this.state.eventRecords = this.state.eventRecords.filter((entry: EventRecordEntry) => entry.matterId !== id);
    this.state.counterEntries = this.state.counterEntries.filter((entry: CounterEntry) => entry.matterId !== id);
    this.state.checklistItems = this.state.checklistItems.filter((item: ChecklistItem) => {
      return item.matterId !== id && item.targetMatterId !== id;
    });
    if (this.state.singleCardMatterId === id) {
      this.state.singleCardMatterId = '';
    }
    this.state.summaryCardMatterIds = this.state.summaryCardMatterIds.filter((matterId: string) => matterId !== id);
    this.removeEmptyClusters();
    this.reindexMatters();
    this.save();
  }

  moveMatterByDelta(id: string, delta: number): void {
    const active = this.activeMatters();
    const currentIndex = active.findIndex((matter: Matter) => matter.id === id);
    if (currentIndex < 0) {
      return;
    }
    this.moveMatterToActiveIndex(id, currentIndex + delta);
  }

  moveMatterToActiveIndex(id: string, targetIndex: number): void {
    const active = this.activeMatters();
    const currentIndex = active.findIndex((matter: Matter) => matter.id === id);
    if (currentIndex < 0) {
      return;
    }
    const boundedIndex = Math.max(0, Math.min(active.length - 1, targetIndex));
    const moved = active.splice(currentIndex, 1)[0];
    active.splice(boundedIndex, 0, moved);
    active.forEach((matter: Matter, index: number) => {
      matter.orderIndex = index;
      matter.updatedAt = Date.now();
    });
    this.reindexArchivedAfterActive();
    this.save();
  }

  private reindexMatters(): void {
    this.state.matters = this.allMatters();
    this.state.matters.forEach((matter: Matter, index: number) => {
      matter.orderIndex = index;
    });
  }

  private reindexArchivedAfterActive(): void {
    const activeIds = this.activeMatters().map((matter: Matter) => matter.id);
    const active = activeIds.map((id: string) => this.findMatter(id)).filter((matter: Matter | undefined) => matter !== undefined) as Matter[];
    const archived = this.archivedMatters();
    this.state.matters = active.concat(archived);
    this.reindexMatters();
  }

  createOrJoinCluster(sourceId: string, targetId: string): void {
    const source = this.findMatter(sourceId);
    const target = this.findMatter(targetId);
    if (!source || !target || source.id === target.id) {
      return;
    }

    const now = Date.now();
    const sourceClusterId = source.clusterId;
    let clusterId = target.clusterId ?? sourceClusterId;
    if (!clusterId) {
      const cluster = this.createCluster();
      clusterId = cluster.id;
    }

    this.state.matters.forEach((matter: Matter) => {
      if (sourceClusterId && matter.clusterId === sourceClusterId && sourceClusterId !== clusterId) {
        matter.clusterId = clusterId;
        matter.updatedAt = now;
      }
    });
    source.clusterId = clusterId;
    target.clusterId = clusterId;
    source.updatedAt = now;
    target.updatedAt = now;
    this.removeEmptyClusters();
    this.save();
  }

  clusterWithPrevious(id: string): void {
    const active = this.activeMatters();
    const index = active.findIndex((matter: Matter) => matter.id === id);
    if (index <= 0) {
      return;
    }
    this.createOrJoinCluster(id, active[index - 1].id);
  }

  detachCluster(id: string): void {
    const matter = this.findMatter(id);
    if (!matter) {
      return;
    }
    matter.clusterId = undefined;
    matter.updatedAt = Date.now();
    this.removeEmptyClusters();
    this.save();
  }

  clusterColor(clusterId?: string): string {
    if (!clusterId) {
      return '#D8DEE8';
    }
    const cluster = this.state.clusters.find((item: Cluster) => item.id === clusterId);
    return cluster ? cluster.color : '#D8DEE8';
  }

  private createCluster(): Cluster {
    const now = Date.now();
    const color = CLUSTER_COLORS[this.state.clusters.length % CLUSTER_COLORS.length];
    const cluster: Cluster = {
      id: createId('cluster'),
      color,
      createdAt: now,
      updatedAt: now
    };
    this.state.clusters.push(cluster);
    return cluster;
  }

  private removeEmptyClusters(): void {
    this.state.clusters = this.state.clusters.filter((cluster: Cluster) => {
      return this.state.matters.some((matter: Matter) => matter.clusterId === cluster.id);
    });
  }

  hasModule(matter: Matter, type: ModuleType): boolean {
    return matter.enabledModules.some((module: ModuleInstance) => module.moduleType === type);
  }

  toggleModule(matterId: string, type: ModuleType): void {
    const matter = this.findMatter(matterId);
    if (!matter || type === ModuleType.Countdown || type === ModuleType.Progress) {
      return;
    }
    const index = matter.enabledModules.findIndex((module: ModuleInstance) => module.moduleType === type);
    if (index >= 0) {
      matter.enabledModules.splice(index, 1);
      if (type === ModuleType.Deadline) {
        matter.enabledModules = matter.enabledModules.filter((module: ModuleInstance) => {
          return module.moduleType !== ModuleType.Countdown;
        });
      }
    } else {
      matter.enabledModules.push(createModuleInstance(matterId, type));
      if (type === ModuleType.Deadline && !this.hasModule(matter, ModuleType.Countdown)) {
        matter.enabledModules.push(createModuleInstance(matterId, ModuleType.Countdown));
      }
    }
    matter.updatedAt = Date.now();
    this.save();
  }

  private moduleFor(matterId: string, type: ModuleType): ModuleInstance | undefined {
    const matter = this.findMatter(matterId);
    if (!matter) {
      return undefined;
    }
    return matter.enabledModules.find((module: ModuleInstance) => module.moduleType === type);
  }

  private readConfig<T>(matterId: string, type: ModuleType, fallback: T): T {
    const module = this.moduleFor(matterId, type);
    if (!module) {
      return fallback;
    }
    try {
      return JSON.parse(module.configJson) as T;
    } catch (error) {
      return fallback;
    }
  }

  private writeConfig(matterId: string, type: ModuleType, config: object): void {
    let module = this.moduleFor(matterId, type);
    const matter = this.findMatter(matterId);
    if (!matter) {
      return;
    }
    if (!module) {
      module = createModuleInstance(matterId, type);
      matter.enabledModules.push(module);
    }
    module.configJson = JSON.stringify(config);
    module.updatedAt = Date.now();
    matter.updatedAt = Date.now();
    this.save();
  }

  addEventRecord(matterId: string, note?: string): void {
    this.state.eventRecords.push({
      id: createId('event'),
      matterId,
      timestamp: Date.now(),
      note
    });
    this.save();
  }

  eventRecordsFor(matterId: string, limit: number = 8): EventRecordEntry[] {
    return this.state.eventRecords
      .filter((entry: EventRecordEntry) => entry.matterId === matterId)
      .sort((a: EventRecordEntry, b: EventRecordEntry) => b.timestamp - a.timestamp)
      .slice(0, limit);
  }

  todayEventCount(matterId: string): number {
    return this.state.eventRecords.filter((entry: EventRecordEntry) => {
      return entry.matterId === matterId && isToday(entry.timestamp);
    }).length;
  }

  addCounterEntry(matterId: string, value: number): void {
    if (value === 0) {
      return;
    }
    this.state.counterEntries.push({
      id: createId('counter'),
      matterId,
      value,
      timestamp: Date.now()
    });
    this.save();
  }

  markDailyOnce(matterId: string): void {
    const done = this.state.counterEntries.some((entry: CounterEntry) => {
      return entry.matterId === matterId && isToday(entry.timestamp) && entry.value === 1;
    });
    if (!done) {
      this.addCounterEntry(matterId, 1);
    }
  }

  counterTotal(matterId: string): number {
    return this.state.counterEntries
      .filter((entry: CounterEntry) => entry.matterId === matterId)
      .reduce((total: number, entry: CounterEntry) => total + entry.value, 0);
  }

  counterToday(matterId: string): number {
    return this.state.counterEntries
      .filter((entry: CounterEntry) => entry.matterId === matterId && isToday(entry.timestamp))
      .reduce((total: number, entry: CounterEntry) => total + entry.value, 0);
  }

  // Retained for compatibility with data created before the progress module was removed.

  getProgressPercent(matterId: string): number {
    const fallback: ProgressConfig = {
      mode: 'manual_percent',
      percent: 0
    };
    const config = this.readConfig<ProgressConfig>(matterId, ModuleType.Progress, fallback);
    if (config.mode === 'target_value' && config.targetValue && config.targetValue > 0) {
      return Math.min(100, Math.round(((config.currentValue ?? 0) / config.targetValue) * 100));
    }
    return Math.max(0, Math.min(100, Math.round(config.percent ?? 0)));
  }

  setProgressPercent(matterId: string, percent: number): void {
    const config: ProgressConfig = {
      mode: 'manual_percent',
      percent: Math.max(0, Math.min(100, Math.round(percent)))
    };
    this.writeConfig(matterId, ModuleType.Progress, config);
  }

  getDeadline(matterId: string): DeadlineConfig | undefined {
    const module = this.moduleFor(matterId, ModuleType.Deadline);
    if (!module) {
      return undefined;
    }
    return this.readConfig<DeadlineConfig>(matterId, ModuleType.Deadline, {
      timestamp: Date.now(),
      hasTime: false
    });
  }

  setDeadline(matterId: string, timestamp: number, location: string): void {
    const config: DeadlineConfig = {
      timestamp,
      hasTime: false,
      location: location.trim()
    };
    this.writeConfig(matterId, ModuleType.Deadline, config);
    if (!this.moduleFor(matterId, ModuleType.Countdown)) {
      const matter = this.findMatter(matterId);
      matter?.enabledModules.push(createModuleInstance(matterId, ModuleType.Countdown));
    }
    this.save();
  }

  countdownText(matterId: string): string {
    const deadline = this.getDeadline(matterId);
    if (!deadline) {
      return '未设置截止日期';
    }
    const days = daysUntil(deadline.timestamp);
    if (days > 0) {
      return `剩余 ${days} 天`;
    }
    if (days === 0) {
      return '就是今天';
    }
    return `已过去 ${Math.abs(days)} 天`;
  }

  getNote(matterId: string): string {
    const config = this.readConfig<NoteConfig>(matterId, ModuleType.Note, { text: '' });
    return config.text ?? '';
  }

  setNote(matterId: string, text: string): void {
    const config: NoteConfig = {
      text
    };
    this.writeConfig(matterId, ModuleType.Note, config);
  }

  checklistItemsFor(matterId: string): ChecklistItem[] {
    return this.state.checklistItems
      .filter((item: ChecklistItem) => item.matterId === matterId)
      .sort((a: ChecklistItem, b: ChecklistItem) => a.orderIndex - b.orderIndex);
  }

  listSummaryText(matterId: string): string {
    const items = this.checklistItemsFor(matterId);
    const textItems = items.filter((item: ChecklistItem) => item.entryType !== 'matter_ref');
    const matterItems = items.length - textItems.length;
    const completed = textItems.filter((item: ChecklistItem) => item.completed).length;
    if (matterItems === 0) {
      return `${completed} / ${textItems.length}`;
    }
    if (textItems.length === 0) {
      return `${matterItems} 个事项`;
    }
    return `${completed} / ${textItems.length}，${matterItems} 个事项`;
  }

  addChecklistItem(matterId: string, title: string): void {
    if (title.trim().length === 0) {
      return;
    }
    const items = this.checklistItemsFor(matterId);
    const now = Date.now();
    this.state.checklistItems.push({
      id: createId('check'),
      matterId,
      title: title.trim(),
      completed: false,
      entryType: 'text',
      orderIndex: items.length,
      createdAt: now,
      updatedAt: now
    });
    this.save();
  }

  canLinkMatter(ownerMatterId: string, targetMatterId: string): boolean {
    const owner = this.findMatter(ownerMatterId);
    const target = this.findMatter(targetMatterId);
    if (!owner || !target || owner.id === target.id || owner.archived || target.archived || !this.hasModule(owner, ModuleType.Checklist)) {
      return false;
    }
    const ownerIsAlreadyLinked = this.state.checklistItems.some((item: ChecklistItem) => {
      return item.entryType === 'matter_ref' && item.targetMatterId === ownerMatterId;
    });
    if (ownerIsAlreadyLinked) {
      return false;
    }
    if (this.checklistItemsFor(ownerMatterId).some((item: ChecklistItem) => {
      return item.entryType === 'matter_ref' && item.targetMatterId === targetMatterId;
    })) {
      return false;
    }
    const alreadyLinked = this.state.checklistItems.some((item: ChecklistItem) => {
      return item.entryType === 'matter_ref' && item.targetMatterId === targetMatterId;
    });
    if (alreadyLinked) {
      return false;
    }
    const targetHasLinkedChildren = this.checklistItemsFor(targetMatterId).some((item: ChecklistItem) => {
      return item.entryType === 'matter_ref';
    });
    return !targetHasLinkedChildren;
  }

  availableMatterLinks(ownerMatterId: string): Matter[] {
    return this.activeMatters().filter((matter: Matter) => {
      return this.canLinkMatter(ownerMatterId, matter.id);
    });
  }

  addMatterListEntry(ownerMatterId: string, targetMatterId: string): void {
    if (!this.canLinkMatter(ownerMatterId, targetMatterId)) {
      return;
    }
    const items = this.checklistItemsFor(ownerMatterId);
    const target = this.findMatter(targetMatterId);
    if (!target) {
      return;
    }
    const now = Date.now();
    this.state.checklistItems.push({
      id: createId('matter_link'),
      matterId: ownerMatterId,
      title: target.title,
      completed: false,
      entryType: 'matter_ref',
      targetMatterId,
      orderIndex: items.length,
      createdAt: now,
      updatedAt: now
    });
    this.save();
  }

  linkedMatterFor(entry: ChecklistItem): Matter | undefined {
    if (entry.entryType !== 'matter_ref' || !entry.targetMatterId) {
      return undefined;
    }
    return this.findMatter(entry.targetMatterId);
  }

  toggleChecklistItem(itemId: string): void {
    const item = this.state.checklistItems.find((entry: ChecklistItem) => entry.id === itemId);
    if (!item) {
      return;
    }
    item.completed = !item.completed;
    item.updatedAt = Date.now();
    this.save();
  }

  deleteChecklistItem(itemId: string): void {
    const item = this.state.checklistItems.find((entry: ChecklistItem) => entry.id === itemId);
    this.state.checklistItems = this.state.checklistItems.filter((entry: ChecklistItem) => entry.id !== itemId);
    if (item) {
      this.reindexChecklist(item.matterId);
    }
    this.save();
  }

  private reindexChecklist(matterId: string): void {
    this.checklistItemsFor(matterId).forEach((item: ChecklistItem, index: number) => {
      item.orderIndex = index;
    });
  }

  checklistProgressText(matterId: string): string {
    const items = this.checklistItemsFor(matterId)
      .filter((item: ChecklistItem) => item.entryType !== 'matter_ref');
    if (items.length === 0) {
      return '0 / 0';
    }
    const done = items.filter((item: ChecklistItem) => item.completed).length;
    return `${done} / ${items.length}`;
  }

  moduleSummary(matter: Matter): string {
    const visibleModules = matter.enabledModules.filter((module: ModuleInstance) => {
      return module.moduleType !== ModuleType.Countdown && module.moduleType !== ModuleType.Progress;
    });
    const parts: string[] = visibleModules.slice(0, 3).map((module: ModuleInstance) => {
      return moduleLabel(module.moduleType);
    });
    if (visibleModules.length > 3) {
      parts.push(`等 ${visibleModules.length} 项信息`);
    }
    return parts.length > 0 ? parts.join(' · ') : '未启用信息';
  }

  cardPrimaryText(matter: Matter): string {
    if (this.hasModule(matter, ModuleType.EventRecord)) {
      return `今日 ${this.todayEventCount(matter.id)} 次`;
    }
    if (this.hasModule(matter, ModuleType.Counter)) {
      return `今日 ${this.counterToday(matter.id)}，累计 ${this.counterTotal(matter.id)}`;
    }
    if (this.hasModule(matter, ModuleType.Checklist)) {
      return this.listSummaryText(matter.id);
    }
    if (this.hasModule(matter, ModuleType.Countdown)) {
      return this.countdownText(matter.id);
    }
    return this.moduleSummary(matter);
  }

  cardQuickActionType(matter: Matter): string {
    if (this.hasModule(matter, ModuleType.EventRecord)) {
      return 'record';
    }
    if (this.hasModule(matter, ModuleType.Counter)) {
      return 'counter:1';
    }
    return 'open';
  }

  cardQuickActionLabel(matter: Matter): string {
    const action = this.cardQuickActionType(matter);
    if (action === 'record') {
      return '记录';
    }
    if (action === 'counter:1') {
      return '+1';
    }
    return '打开';
  }

  selectedSingleCardMatterId(): string {
    const matter = this.findMatter(this.state.singleCardMatterId);
    if (matter && !matter.archived) {
      return matter.id;
    }
    const first = this.activeMatters()[0];
    return first ? first.id : '';
  }

  selectedSingleCardMatter(): Matter | undefined {
    return this.findMatter(this.selectedSingleCardMatterId());
  }

  setSingleCardMatter(id: string): void {
    const matter = this.findMatter(id);
    if (!matter || matter.archived) {
      return;
    }
    this.state.singleCardMatterId = id;
    this.save();
  }

  selectedSummaryCardMatterIds(): string[] {
    const activeIds = this.activeMatters().map((matter: Matter) => matter.id);
    const selected = this.state.summaryCardMatterIds.filter((id: string) => activeIds.includes(id));
    return selected.slice(0, 3);
  }

  selectedSummaryCardMatters(): Matter[] {
    return this.selectedSummaryCardMatterIds()
      .map((id: string) => this.findMatter(id))
      .filter((matter: Matter | undefined) => matter !== undefined) as Matter[];
  }

  isSummaryCardMatterSelected(id: string): boolean {
    return this.selectedSummaryCardMatterIds().includes(id);
  }

  toggleSummaryCardMatter(id: string): void {
    const matter = this.findMatter(id);
    if (!matter || matter.archived) {
      return;
    }
    const nextIds = this.selectedSummaryCardMatterIds();
    const index = nextIds.indexOf(id);
    if (index >= 0) {
      nextIds.splice(index, 1);
    } else {
      if (nextIds.length >= 3) {
        nextIds.shift();
      }
      nextIds.push(id);
    }
    this.state.summaryCardMatterIds = nextIds;
    this.save();
  }

  rememberCardForm(formId: string): void {
    if (formId.length === 0 || this.state.cardFormIds.includes(formId)) {
      return;
    }
    this.state.cardFormIds.push(formId);
    this.save();
  }

  removeCardForm(formId: string): void {
    this.state.cardFormIds = this.state.cardFormIds.filter((id: string) => id !== formId);
    this.save();
  }

  cardFormIds(): string[] {
    return this.state.cardFormIds.slice();
  }

  resetDemoData(): void {
    this.state = createSeedState();
    this.save();
  }

  defaultConfigFor(type: ModuleType): string {
    return defaultConfigJson(type);
  }
}
