import {
  copyTimelineAttachments,
  TimelineAttachment,
  TimelineBlock,
  TimelineDeleteScope,
  TimelineRepeat,
  TimelineTag
} from '../contracts/TimelineService';
import { canLinkMatterInState } from './MatterLinks';
import {
  deleteMatterScheduleScope,
  effectiveMatterNote,
  effectiveMatterTagId,
  importLegacyTimelineIntoState,
  isLightScheduleMatter,
  matterMatchesDay,
  mattersForDayInState,
  stateReminderBlocks,
  stateTimelineBlocks
} from './MatterSchedule';
import { MatterDataError } from './MatterSnapshot';
import {
  dateSummary,
  effectiveDayCountMode,
  effectiveSpan,
  isToday,
  timeConfigTitle
} from '../common/DateFormat';
import { localDayStart } from './TimelineLayout';
import { planTimelineReminders, TimelineReminderPlan } from './TimelineReminderPlan';
import {
  appendDeckExamples,
  CLUSTER_COLORS,
  createId,
  createMatter,
  createModuleInstance,
  createSeedState,
  DEFAULT_MATTER_TAGS,
  defaultConfigJson,
  moduleLabel,
  stripTagEmoji
} from '../model/Defaults';
import {
  ActiveCounterMode,
  AppState,
  ChecklistItem,
  Cluster,
  CounterConfig,
  CounterEntry,
  CreateMatterIntent,
  DateMode,
  DeadlineConfig,
  EventRecordEntry,
  Matter,
  ModuleInstance,
  ModuleType,
  NoteConfig,
  ProgressConfig,
  TagConfig
} from '../model/Types';

// 所有规则只作用于调用方提供的候选状态，持久化由仓库负责。
export class MatterState {
  private state: AppState;

  constructor(state: AppState) {
    this.state = state;
  }

  allMatters(): Matter[] {
    return this.state.matters.slice().sort((a: Matter, b: Matter) => a.orderIndex - b.orderIndex);
  }

  activeMatters(): Matter[] {
    return this.allMatters().filter((matter: Matter) => !matter.archived);
  }

  residentActiveMatters(): Matter[] {
    return this.activeMatters().filter((matter: Matter) => !isLightScheduleMatter(matter));
  }

  isLightSchedule(matter: Matter): boolean {
    return isLightScheduleMatter(matter);
  }

  mattersForDay(dayTimestamp: number): Matter[] {
    return mattersForDayInState(this.state, dayTimestamp);
  }

  dayScheduleCount(dayTimestamp: number): number {
    return this.mattersForDay(dayTimestamp).length;
  }

  todayLightScheduleCount(todayTimestamp: number = Date.now()): number {
    return this.mattersForDay(todayTimestamp).filter((m: Matter) => isLightScheduleMatter(m)).length;
  }

  matterMatchesSelectedDay(matter: Matter, dayTimestamp: number): boolean {
    return matterMatchesDay(this.state, matter, dayTimestamp);
  }

  timelineBlocks(): TimelineBlock[] {
    return stateTimelineBlocks(this.state);
  }

  reminderBlocks(): TimelineBlock[] {
    return stateReminderBlocks(this.state);
  }

  planReminders(now: number, capacity: number): TimelineReminderPlan {
    return planTimelineReminders(this.reminderBlocks(), now, capacity);
  }

  importLegacyTimeline(blocks: TimelineBlock[], tags: TimelineTag[]): number {
    const imported = importLegacyTimelineIntoState(this.state, blocks, tags);
    if (imported > 0) {
      this.reindexArchivedAfterActive();
    }
    return imported;
  }

  listTags(): TimelineTag[] {
    const source = this.state.tags && this.state.tags.length > 0 ? this.state.tags : DEFAULT_MATTER_TAGS;
    const uses = new Map<string, number>();
    for (const matter of this.state.matters) {
      if (matter.archived) continue;
      const tagId = effectiveMatterTagId(this.state, matter);
      if (tagId) uses.set(tagId, (uses.get(tagId) ?? 0) + 1);
    }
    return source
      .map((tag: TimelineTag): TimelineTag => ({ id: tag.id, name: stripTagEmoji(tag.name) || tag.name.trim(), color: tag.color.toUpperCase() }))
      .sort((a: TimelineTag, b: TimelineTag) => (uses.get(b.id) ?? 0) - (uses.get(a.id) ?? 0));
  }

  findTag(tagId?: string): TimelineTag | undefined {
    if (!tagId) return undefined;
    return this.listTags().find((t: TimelineTag) => t.id === tagId);
  }

  matterTag(matter: Matter): TimelineTag | undefined {
    const tagId = effectiveMatterTagId(this.state, matter);
    return this.findTag(tagId);
  }

  saveTag(tag: TimelineTag): TimelineTag {
    const cleanName = stripTagEmoji(tag.name);
    if (!tag.id.trim() || !cleanName) {
      throw new MatterDataError('MAT-TAG', '请输入纯文字标签名称');
    }
    if (!/^#[0-9a-fA-F]{6}$/.test(tag.color.trim())) {
      throw new MatterDataError('MAT-TAG', '请选择有效的标签颜色');
    }
    if (!this.state.tags || this.state.tags.length === 0) {
      this.state.tags = DEFAULT_MATTER_TAGS.map((t: TimelineTag): TimelineTag => ({ id: t.id, name: t.name, color: t.color }));
    }
    if (this.state.tags.some((item: TimelineTag) => item.id !== tag.id && stripTagEmoji(item.name) === cleanName)) {
      throw new MatterDataError('MAT-TAG', '这个标签名已存在');
    }
    const saved: TimelineTag = {
      id: tag.id.trim(),
      name: cleanName,
      color: tag.color.trim().toUpperCase()
    };
    const index = this.state.tags.findIndex((item: TimelineTag) => item.id === saved.id);
    if (index < 0) this.state.tags.push(saved);
    else this.state.tags[index] = saved;
    return { id: saved.id, name: saved.name, color: saved.color };
  }

  allReferencedAttachments(): TimelineAttachment[] {
    const result: TimelineAttachment[] = [];
    for (const matter of this.state.matters) {
      const modules = matter.enabledModules.concat(matter.disabledModules ?? []);
      for (const mod of modules) {
        if (mod.moduleType === ModuleType.Note) {
          try {
            const cfg = JSON.parse(mod.configJson) as NoteConfig;
            if (cfg.attachments) result.push(...cfg.attachments);
          } catch (error) {}
        } else if (mod.moduleType === ModuleType.Deadline) {
          try {
            const cfg = JSON.parse(mod.configJson) as DeadlineConfig;
            for (const ov of cfg.overrides ?? []) {
              if (ov.attachments) result.push(...ov.attachments);
            }
          } catch (error) {}
        }
      }
    }
    return result;
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
  }

  archiveMatter(id: string, archived: boolean): void {
    const matter = this.findMatter(id);
    if (!matter) {
      return;
    }
    matter.archived = archived;
    matter.updatedAt = Date.now();
    this.reindexMatters();
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
  }

  deleteScheduleOccurrence(id: string, scope: TimelineDeleteScope = TimelineDeleteScope.All, occurrenceStart?: number): void {
    const removeWhole = deleteMatterScheduleScope(this.state, id, scope, occurrenceStart);
    if (removeWhole) {
      this.deleteMatter(id);
    }
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

  hasCounterLikeModule(matter: Matter): boolean {
    return this.hasModule(matter, ModuleType.Counter) || this.hasModule(matter, ModuleType.EventRecord);
  }

  toggleModule(matterId: string, type: ModuleType): void {
    const matter = this.findMatter(matterId);
    if (!matter || type === ModuleType.Countdown) {
      return;
    }
    const index = matter.enabledModules.findIndex((module: ModuleInstance) => module.moduleType === type);
    if (index >= 0) {
      const removed = matter.enabledModules.splice(index, 1);
      matter.disabledModules = (matter.disabledModules ?? []).concat(removed);
      if (type === ModuleType.Deadline) {
        matter.enabledModules = matter.enabledModules.filter((module: ModuleInstance) => {
          return module.moduleType !== ModuleType.Countdown;
        });
      }
      if (type === ModuleType.Tag) {
        matter.tagId = undefined;
      }
    } else {
      const hidden = matter.disabledModules ?? [];
      const previous = hidden.find((module: ModuleInstance) => module.moduleType === type);
      const added = previous ?? createModuleInstance(matterId, type);
      matter.enabledModules.push(added);
      matter.disabledModules = hidden.filter((module: ModuleInstance) => module.moduleType !== type);
      if (type === ModuleType.Tag) {
        try {
          const cfg = JSON.parse(added.configJson) as TagConfig;
          matter.tagId = cfg.tagId || undefined;
        } catch (error) {}
      }
    }
    matter.updatedAt = Date.now();
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
  }

  addEventRecord(matterId: string, note?: string): void {
    const matter = this.findMatter(matterId);
    if (!matter) throw new MatterDataError('MAT-MISSING', '事项已不存在，请重新加载');
    // 若已升级为统一 Counter 且不含旧 EventRecord 模块，直接记入计数流水
    if (this.hasModule(matter, ModuleType.Counter) && !this.hasModule(matter, ModuleType.EventRecord)) {
      this.addCounterEntry(matterId, 1, note);
      return;
    }
    this.state.eventRecords.push({
      id: createId('event'),
      matterId,
      timestamp: Date.now(),
      note: note?.trim() || undefined
    });
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

  addCounterEntry(matterId: string, value: number, note?: string): void {
    if (!this.findMatter(matterId)) throw new MatterDataError('MAT-MISSING', '事项已不存在，请重新加载');
    if (!Number.isFinite(value)) throw new MatterDataError('MAT-VALUE', '请输入有效数值');
    if (value === 0) {
      return;
    }
    const cleanNote = note?.trim();
    this.state.counterEntries.push({
      id: createId('counter'),
      matterId,
      value,
      timestamp: Date.now(),
      note: cleanNote && cleanNote.length > 0 ? cleanNote : undefined
    });
  }

  removeCounterEntry(entryId: string): void {
    this.state.counterEntries = this.state.counterEntries.filter((entry: CounterEntry) => entry.id !== entryId);
    this.state.eventRecords = this.state.eventRecords.filter((entry: EventRecordEntry) => entry.id !== entryId);
  }

  private isLegacyEventOnly(matterId: string): boolean {
    const matter = this.findMatter(matterId);
    if (!matter) return false;
    return this.hasModule(matter, ModuleType.EventRecord) && !this.hasModule(matter, ModuleType.Counter);
  }

  private rawEntriesForCounter(matterId: string): CounterEntry[] {
    const entries = this.state.counterEntries
      .filter((entry: CounterEntry) => entry.matterId === matterId)
      .slice();
    if (this.isLegacyEventOnly(matterId)) {
      const legacy = this.state.eventRecords
        .filter((e: EventRecordEntry) => e.matterId === matterId)
        .map((e: EventRecordEntry): CounterEntry => ({
          id: e.id,
          matterId: e.matterId,
          value: 1,
          timestamp: e.timestamp,
          note: e.note
        }));
      entries.push(...legacy);
    }
    return entries.sort((a: CounterEntry, b: CounterEntry) => b.timestamp - a.timestamp);
  }

  counterEntriesFor(matterId: string, limit: number = 12): CounterEntry[] {
    return this.rawEntriesForCounter(matterId).slice(0, limit);
  }

  isDailyDoneToday(matterId: string, now: number = Date.now()): boolean {
    return this.rawEntriesForCounter(matterId).some((entry: CounterEntry) =>
      isToday(entry.timestamp, now) && entry.value > 0);
  }

  markDailyOnce(matterId: string, note?: string): void {
    const done = this.state.counterEntries.some((entry: CounterEntry) => {
      return entry.matterId === matterId && isToday(entry.timestamp) && entry.value === 1;
    });
    if (!done) {
      this.addCounterEntry(matterId, 1, note);
    }
  }

  toggleDailyOnce(matterId: string, note?: string): boolean {
    if (!this.findMatter(matterId)) throw new MatterDataError('MAT-MISSING', '事项已不存在，请重新加载');
    if (this.isDailyDoneToday(matterId)) {
      this.state.counterEntries = this.state.counterEntries.filter((entry: CounterEntry) =>
        !(entry.matterId === matterId && isToday(entry.timestamp)));
      if (this.isLegacyEventOnly(matterId)) {
        this.state.eventRecords = this.state.eventRecords.filter((entry: EventRecordEntry) =>
          !(entry.matterId === matterId && isToday(entry.timestamp)));
      }
      return false;
    }
    this.addCounterEntry(matterId, 1, note);
    return true;
  }

  counterStreakDays(matterId: string, now: number = Date.now()): number {
    const entries = this.rawEntriesForCounter(matterId).filter((e: CounterEntry) => e.value > 0);
    if (entries.length === 0) return 0;
    const days = new Set<number>();
    for (const entry of entries) {
      days.add(localDayStart(entry.timestamp));
    }
    let cursor = localDayStart(now);
    if (!days.has(cursor)) {
      cursor = localDayStart(now, -1);
      if (!days.has(cursor)) return 0;
    }
    let streak = 0;
    while (days.has(cursor)) {
      streak++;
      cursor = localDayStart(cursor, -1);
    }
    return streak;
  }

  counterSettings(matterId: string): CounterConfig {
    if (this.isLegacyEventOnly(matterId)) {
      return { mode: 'tally', unit: '次', initialValue: 0, fixedSteps: [1] };
    }
    return this.readConfig<CounterConfig>(matterId, ModuleType.Counter, { mode: 'tally', unit: '次', fixedSteps: [1] });
  }

  activeCounterMode(matterId: string): ActiveCounterMode {
    const cfg = this.counterSettings(matterId);
    if (cfg.mode === 'tally' || cfg.mode === 'amount' || cfg.mode === 'daily_once') {
      return cfg.mode;
    }
    return 'amount';
  }

  counterUnit(matterId: string): string {
    const cfg = this.counterSettings(matterId);
    const trimmed = cfg.unit?.trim() ?? '';
    if (trimmed.length > 0) return trimmed;
    const mode = this.activeCounterMode(matterId);
    if (mode === 'tally') return '次';
    if (mode === 'daily_once') return '天';
    return '';
  }

  counterQuickSteps(matterId: string): number[] {
    const mode = this.activeCounterMode(matterId);
    if (mode !== 'amount') return [1];
    const steps = (this.counterSettings(matterId).fixedSteps ?? [])
      .filter((v: number) => Number.isFinite(v) && v > 0);
    return steps.length > 0 ? steps : [1, 10];
  }

  counterStep(matterId: string): number {
    return this.counterQuickSteps(matterId)[0] ?? 1;
  }

  counterTotal(matterId: string): number {
    const initial = this.counterSettings(matterId).initialValue ?? 0;
    return this.rawEntriesForCounter(matterId)
      .reduce((total: number, entry: CounterEntry) => total + entry.value, initial);
  }

  counterToday(matterId: string): number {
    return this.rawEntriesForCounter(matterId)
      .filter((entry: CounterEntry) => isToday(entry.timestamp))
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

  setDeadline(matterId: string, timestamp: number, location: string, mode: DateMode = 'deadline', hasTime: boolean = false): void {
    const config: DeadlineConfig = {
      timestamp,
      mode,
      hasTime: mode === 'deadline' && hasTime,
      location: location.trim() || undefined
    };
    this.writeConfig(matterId, ModuleType.Deadline, config);
  }

  countdownText(matterId: string): string {
    const deadline = this.getDeadline(matterId);
    if (!deadline) {
      return '未设置时间';
    }
    return dateSummary(deadline);
  }

  getNoteConfig(matterId: string): NoteConfig {
    const matter = this.findMatter(matterId);
    if (!matter) return { text: '' };
    return effectiveMatterNote(matter);
  }

  getNote(matterId: string): string {
    return this.getNoteConfig(matterId).text;
  }

  getAttachments(matterId: string): TimelineAttachment[] {
    return copyTimelineAttachments(this.getNoteConfig(matterId).attachments) ?? [];
  }

  setNote(matterId: string, text: string, attachments?: TimelineAttachment[]): void {
    const matter = this.findMatter(matterId);
    if (!matter) return;
    const prev = this.readConfig<NoteConfig>(matterId, ModuleType.Note, { text: '' });
    const config: NoteConfig = {
      text,
      attachments: attachments !== undefined ? copyTimelineAttachments(attachments) : copyTimelineAttachments(prev.attachments)
    };
    matter.description = undefined;
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
    if (!this.findMatter(matterId)) throw new MatterDataError('MAT-MISSING', '事项已不存在，请重新加载');
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
  }

  canLinkMatter(ownerMatterId: string, targetMatterId: string): boolean {
    return canLinkMatterInState(this.state, ownerMatterId, targetMatterId);
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
  }

  deleteChecklistItem(itemId: string): void {
    const item = this.state.checklistItems.find((entry: ChecklistItem) => entry.id === itemId);
    this.state.checklistItems = this.state.checklistItems.filter((entry: ChecklistItem) => entry.id !== itemId);
    if (item) {
      this.reindexChecklist(item.matterId);
    }
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
    const seen = new Set<string>();
    const labels: string[] = [];
    for (const module of matter.enabledModules) {
      if (module.moduleType === ModuleType.Countdown || module.moduleType === ModuleType.Progress) continue;
      let label = moduleLabel(module.moduleType);
      if (module.moduleType === ModuleType.Deadline) {
        label = timeConfigTitle(this.getDeadline(matter.id));
      } else if (module.moduleType === ModuleType.Tag) {
        const tag = this.matterTag(matter);
        label = tag ? tag.name : '标签';
      } else if (module.moduleType === ModuleType.Counter || module.moduleType === ModuleType.EventRecord) {
        const mode = this.activeCounterMode(matter.id);
        label = mode === 'tally' ? '计次' : mode === 'daily_once' ? '每日打卡' : '计数';
      }
      if (!seen.has(label)) {
        seen.add(label);
        labels.push(label);
      }
    }
    if (labels.length > 3) {
      return labels.slice(0, 3).concat(`等 ${labels.length} 项`).join(' · ');
    }
    return labels.length > 0 ? labels.join(' · ') : '未启用信息';
  }

  counterSummaryText(matterId: string): string {
    const mode = this.activeCounterMode(matterId);
    const unit = this.counterUnit(matterId);
    if (mode === 'daily_once') {
      const done = this.isDailyDoneToday(matterId);
      const streak = this.counterStreakDays(matterId);
      const total = this.counterTotal(matterId);
      return `${done ? '今日已打卡' : '今日未打卡'} · 连续 ${streak} 天（共 ${total} 天）`;
    }
    if (mode === 'tally') {
      return `今日 ${this.counterToday(matterId)} ${unit} · 累计 ${this.counterTotal(matterId)} ${unit}`;
    }
    const suffix = unit ? ` ${unit}` : '';
    return `今日 ${this.counterToday(matterId)}${suffix}，累计 ${this.counterTotal(matterId)}${suffix}`;
  }

  cardPrimaryText(matter: Matter): string {
    if (this.hasModule(matter, ModuleType.Counter) || this.hasModule(matter, ModuleType.EventRecord)) {
      return this.counterSummaryText(matter.id);
    }
    if (this.hasModule(matter, ModuleType.Checklist)) {
      return this.listSummaryText(matter.id);
    }
    if (this.hasModule(matter, ModuleType.Deadline) || this.hasModule(matter, ModuleType.Countdown)) {
      return this.countdownText(matter.id);
    }
    const note = this.getNote(matter.id).trim();
    if (note.length > 0) {
      return note.split('\n')[0];
    }
    return this.moduleSummary(matter);
  }

  cardQuickActionType(matter: Matter): string {
    if (this.hasModule(matter, ModuleType.Counter)) {
      const mode = this.activeCounterMode(matter.id);
      if (mode === 'daily_once') {
        return this.isDailyDoneToday(matter.id) ? 'open' : 'counter:1';
      }
      return 'counter:' + this.counterStep(matter.id);
    }
    if (this.hasModule(matter, ModuleType.EventRecord)) {
      return 'record';
    }
    return 'open';
  }

  cardQuickActionLabel(matter: Matter): string {
    if (this.hasModule(matter, ModuleType.Counter)) {
      const mode = this.activeCounterMode(matter.id);
      if (mode === 'daily_once') {
        return this.isDailyDoneToday(matter.id) ? '已完成' : '打卡';
      }
      if (mode === 'tally') {
        return '记一次';
      }
      return '+' + this.counterStep(matter.id);
    }
    if (this.hasModule(matter, ModuleType.EventRecord)) {
      return '记一次';
    }
    return '打开';
  }

  selectedSingleCardMatterId(): string {
    const matter = this.findMatter(this.state.singleCardMatterId);
    if (matter && !matter.archived) {
      return matter.id;
    }
    const first = this.residentActiveMatters()[0] ?? this.activeMatters()[0];
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
  }

  rememberCardForm(formId: string): void {
    if (formId.length === 0 || this.state.cardFormIds.includes(formId)) {
      return;
    }
    this.state.cardFormIds.push(formId);
  }

  removeCardForm(formId: string): void {
    this.state.cardFormIds = this.state.cardFormIds.filter((id: string) => id !== formId);
  }

  cardFormIds(): string[] {
    return this.state.cardFormIds.slice();
  }

  addDeckExamples(): number {
    return appendDeckExamples(this.state);
  }

  resetDemoData(): void {
    const seed = createSeedState();
    this.state.matters = seed.matters;
    this.state.clusters = seed.clusters;
    this.state.tags = seed.tags;
    this.state.eventRecords = seed.eventRecords;
    this.state.counterEntries = seed.counterEntries;
    this.state.checklistItems = seed.checklistItems;
    this.state.singleCardMatterId = seed.singleCardMatterId;
    this.state.summaryCardMatterIds = seed.summaryCardMatterIds;
  }

  defaultConfigFor(type: ModuleType): string {
    return defaultConfigJson(type);
  }
}
