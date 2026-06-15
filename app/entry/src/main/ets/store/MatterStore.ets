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

  init(context: common.UIAbilityContext): void {
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
      checklistItems: input.checklistItems ?? []
    };
  }

  private save(): void {
    if (!this.pref) {
      return;
    }
    this.pref.putSync(STATE_KEY, JSON.stringify(this.state));
    this.pref.flush();
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
    this.state.checklistItems = this.state.checklistItems.filter((item: ChecklistItem) => item.matterId !== id);
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

    let clusterId = target.clusterId;
    if (!clusterId) {
      const cluster = this.createCluster();
      clusterId = cluster.id;
      target.clusterId = clusterId;
    }
    source.clusterId = clusterId;
    source.updatedAt = Date.now();
    target.updatedAt = Date.now();
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
    if (!matter) {
      return;
    }
    const index = matter.enabledModules.findIndex((module: ModuleInstance) => module.moduleType === type);
    if (index >= 0) {
      matter.enabledModules.splice(index, 1);
    } else {
      matter.enabledModules.push(createModuleInstance(matterId, type));
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
      orderIndex: items.length,
      createdAt: now,
      updatedAt: now
    });
    this.save();
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
    const items = this.checklistItemsFor(matterId);
    if (items.length === 0) {
      return '0 / 0';
    }
    const done = items.filter((item: ChecklistItem) => item.completed).length;
    return `${done} / ${items.length}`;
  }

  moduleSummary(matter: Matter): string {
    const parts: string[] = matter.enabledModules.slice(0, 3).map((module: ModuleInstance) => {
      return moduleLabel(module.moduleType);
    });
    if (matter.enabledModules.length > 3) {
      parts.push(`等 ${matter.enabledModules.length} 个模块`);
    }
    return parts.length > 0 ? parts.join(' · ') : '未启用模块';
  }

  cardPrimaryText(matter: Matter): string {
    if (this.hasModule(matter, ModuleType.EventRecord)) {
      return `今日 ${this.todayEventCount(matter.id)} 次`;
    }
    if (this.hasModule(matter, ModuleType.Counter)) {
      return `今日 ${this.counterToday(matter.id)}，累计 ${this.counterTotal(matter.id)}`;
    }
    if (this.hasModule(matter, ModuleType.Progress)) {
      return `${this.getProgressPercent(matter.id)}%`;
    }
    if (this.hasModule(matter, ModuleType.Checklist)) {
      return this.checklistProgressText(matter.id);
    }
    if (this.hasModule(matter, ModuleType.Countdown)) {
      return this.countdownText(matter.id);
    }
    return this.moduleSummary(matter);
  }

  resetDemoData(): void {
    this.state = createSeedState();
    this.save();
  }

  defaultConfigFor(type: ModuleType): string {
    return defaultConfigJson(type);
  }
}

