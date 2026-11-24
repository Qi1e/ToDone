import { common } from '@kit.AbilityKit';
import {
  TimelineAttachment,
  TimelineBlock,
  TimelineDeleteScope,
  TimelineTag
} from '../contracts/TimelineService';
import { MatterRepository } from '../contracts/MatterService';
import { MatterOperation } from '../contracts/MatterPersistence';
import { DefaultTimelineService } from '../domain/DefaultTimelineService';
import { MatterState } from '../domain/MatterState';
import { MatterDataError, emptyMatterState } from '../domain/MatterSnapshot';
import { TransactionalMatterRepository } from '../domain/TransactionalMatterRepository';
import { createId } from '../model/Defaults';
import {
  ActiveCounterMode,
  AppState,
  ChecklistItem,
  CounterConfig,
  CounterEntry,
  CreateMatterIntent,
  DateMode,
  DeadlineConfig,
  EventRecordEntry,
  Matter,
  ModuleType
} from '../model/Types';
import { PreferencesStateStorage } from './PreferencesStateStorage';
import { RdbMatterPersistence } from './RdbMatterPersistence';

export class MatterStore implements MatterRepository {
  private static instance: MatterStore = new MatterStore();
  private repository?: TransactionalMatterRepository;
  private listeners: Set<() => void> = new Set();
  private failedOperations: Map<string, MatterOperation> = new Map();
  private legacyTimelineWarning: string = '';

  static getInstance(): MatterStore {
    return MatterStore.instance;
  }

  async init(context: common.UIAbilityContext | common.FormExtensionContext): Promise<void> {
    if (!this.repository) this.repository = new TransactionalMatterRepository(new RdbMatterPersistence(context));
    await this.reload();
    await this.importLegacyTimelineIfNeeded(context);
  }

  legacyImportWarning(): string {
    return this.legacyTimelineWarning;
  }

  private async importLegacyTimelineIfNeeded(
    context: common.UIAbilityContext | common.FormExtensionContext
  ): Promise<void> {
    if (!this.repository || this.readState().timelineImported) return;
    try {
      const storage = new PreferencesStateStorage(
        context as common.UIAbilityContext,
        'todone_timeline',
        'timeline_blocks_v1'
      );
      const raw = storage.read();
      if (!raw) {
        await this.transact(
          { id: 'legacy-timeline-empty', fingerprint: 'legacy-timeline:empty' },
          (state: AppState): void => { state.timelineImported = true; }
        );
        this.legacyTimelineWarning = '';
        return;
      }
      const parser = new DefaultTimelineService(storage);
      const blocks = parser.list();
      const tags = parser.listTags();
      await this.transact(
        { id: 'legacy-timeline-import-v1', fingerprint: 'legacy-timeline:import-v1' },
        (state: AppState): number => {
          if (state.timelineImported) return 0;
          return new MatterState(state).importLegacyTimeline(blocks, tags);
        }
      );
      this.legacyTimelineWarning = '';
    } catch (error) {
      // 旧时间线文件若损坏则保留原文件、不置位 timelineImported，以便修复后重试。
      this.legacyTimelineWarning = '旧时间线存档未能导入，原文件已保留';
      console.warn('ToDone legacy timeline import skipped');
    }
  }

  async reload(): Promise<void> {
    if (!this.repository) throw new MatterDataError('MAT-INIT', '事项存储尚未初始化');
    await this.repository.reload();
    this.publish();
  }

  readState(): AppState {
    return this.repository ? this.repository.readState() : emptyMatterState();
  }

  completedFormOperation(formId: string): string {
    return this.repository?.latestOperationId('form:' + formId + ':') ?? '';
  }

  async transact<T>(operation: MatterOperation, change: (state: AppState) => T): Promise<T> {
    if (!this.repository) throw new MatterDataError('MAT-INIT', '事项存储尚未初始化');
    const result = await this.repository.transact(operation, change);
    this.publish();
    return result;
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  private publish(): void {
    this.listeners.forEach((listener: () => void) => {
      try { listener(); } catch (error) { console.error('ToDone 事项视图更新失败'); }
    });
  }

  private view(): MatterState {
    return new MatterState(this.readState());
  }

  private async change<T>(kind: string, payload: string, change: (state: MatterState) => T,
    operationId?: string): Promise<T> {
    const fingerprint = kind + ':' + payload;
    const pending = this.failedOperations.get(fingerprint);
    const operation: MatterOperation = { id: operationId ?? pending?.id ?? createId('operation'), fingerprint };
    try {
      const result = await this.transact(operation, (state: AppState): T => change(new MatterState(state)));
      if (this.failedOperations.get(fingerprint)?.id === operation.id) this.failedOperations.delete(fingerprint);
      return result;
    } catch (error) {
      this.failedOperations.set(fingerprint, operation);
      throw error as Error;
    }
  }

  allMatters(): Matter[] {
    return this.view().allMatters();
  }

  activeMatters(): Matter[] {
    return this.view().activeMatters();
  }

  residentActiveMatters(): Matter[] {
    return this.view().residentActiveMatters();
  }

  isLightSchedule(matter: Matter): boolean {
    return this.view().isLightSchedule(matter);
  }

  mattersForDay(dayTimestamp: number): Matter[] {
    return this.view().mattersForDay(dayTimestamp);
  }

  dayScheduleCount(dayTimestamp: number): number {
    return this.view().dayScheduleCount(dayTimestamp);
  }

  todayLightScheduleCount(todayTimestamp?: number): number {
    return this.view().todayLightScheduleCount(todayTimestamp);
  }

  timelineBlocks(): TimelineBlock[] {
    return this.view().timelineBlocks();
  }

  reminderBlocks(): TimelineBlock[] {
    return this.view().reminderBlocks();
  }

  allReferencedAttachments(): TimelineAttachment[] {
    return this.view().allReferencedAttachments();
  }

  listTags(): TimelineTag[] {
    return this.view().listTags();
  }

  findTag(tagId?: string): TimelineTag | undefined {
    return this.view().findTag(tagId);
  }

  matterTag(matter: Matter): TimelineTag | undefined {
    return this.view().matterTag(matter);
  }

  saveTag(tag: TimelineTag, operationId?: string): Promise<TimelineTag> {
    return this.change('saveTag', JSON.stringify([tag]),
      (state: MatterState) => state.saveTag(tag), operationId);
  }

  archivedMatters(): Matter[] {
    return this.view().archivedMatters();
  }

  findMatter(id: string): Matter | undefined {
    return this.view().findMatter(id);
  }

  addMatter(intent: CreateMatterIntent, operationId?: string): Promise<Matter> {
    return this.change('addMatter', JSON.stringify([intent]),
      (state: MatterState) => state.addMatter(intent), operationId);
  }

  updateMatter(id: string, title: string, description: string, operationId?: string): Promise<void> {
    return this.change('updateMatter', JSON.stringify([id, title, description]),
      (state: MatterState) => state.updateMatter(id, title, description), operationId);
  }

  archiveMatter(id: string, archived: boolean, operationId?: string): Promise<void> {
    return this.change('archiveMatter', JSON.stringify([id, archived]),
      (state: MatterState) => state.archiveMatter(id, archived), operationId);
  }

  deleteMatter(id: string, operationId?: string): Promise<void> {
    return this.change('deleteMatter', JSON.stringify([id]),
      (state: MatterState) => state.deleteMatter(id), operationId);
  }

  deleteScheduleOccurrence(id: string, scope: TimelineDeleteScope = TimelineDeleteScope.All,
    occurrenceStart?: number, operationId?: string): Promise<void> {
    return this.change('deleteScheduleOccurrence', JSON.stringify([id, scope, occurrenceStart]),
      (state: MatterState) => state.deleteScheduleOccurrence(id, scope, occurrenceStart), operationId);
  }

  moveMatterByDelta(id: string, delta: number, operationId?: string): Promise<void> {
    return this.change('moveMatterByDelta', JSON.stringify([id, delta]),
      (state: MatterState) => state.moveMatterByDelta(id, delta), operationId);
  }

  moveMatterToActiveIndex(id: string, targetIndex: number, operationId?: string): Promise<void> {
    return this.change('moveMatterToActiveIndex', JSON.stringify([id, targetIndex]),
      (state: MatterState) => state.moveMatterToActiveIndex(id, targetIndex), operationId);
  }

  createOrJoinCluster(sourceId: string, targetId: string, operationId?: string): Promise<void> {
    return this.change('createOrJoinCluster', JSON.stringify([sourceId, targetId]),
      (state: MatterState) => state.createOrJoinCluster(sourceId, targetId), operationId);
  }

  clusterWithPrevious(id: string, operationId?: string): Promise<void> {
    return this.change('clusterWithPrevious', JSON.stringify([id]),
      (state: MatterState) => state.clusterWithPrevious(id), operationId);
  }

  detachCluster(id: string, operationId?: string): Promise<void> {
    return this.change('detachCluster', JSON.stringify([id]),
      (state: MatterState) => state.detachCluster(id), operationId);
  }

  clusterColor(clusterId?: string): string {
    return this.view().clusterColor(clusterId);
  }

  hasModule(matter: Matter, type: ModuleType): boolean {
    return this.view().hasModule(matter, type);
  }

  hasCounterLikeModule(matter: Matter): boolean {
    return this.view().hasCounterLikeModule(matter);
  }

  toggleModule(matterId: string, type: ModuleType, operationId?: string): Promise<void> {
    return this.change('toggleModule', JSON.stringify([matterId, type]),
      (state: MatterState) => state.toggleModule(matterId, type), operationId);
  }

  addEventRecord(matterId: string, note?: string, operationId?: string): Promise<void> {
    return this.change('addEventRecord', JSON.stringify([matterId, note]),
      (state: MatterState) => state.addEventRecord(matterId, note), operationId);
  }

  eventRecordsFor(matterId: string, limit: number = 8): EventRecordEntry[] {
    return this.view().eventRecordsFor(matterId, limit);
  }

  todayEventCount(matterId: string): number {
    return this.view().todayEventCount(matterId);
  }

  addCounterEntry(matterId: string, value: number, operationId?: string, note?: string): Promise<void> {
    return this.change('addCounterEntry', JSON.stringify([matterId, value, note]),
      (state: MatterState) => state.addCounterEntry(matterId, value, note), operationId);
  }

  removeCounterEntry(entryId: string, operationId?: string): Promise<void> {
    return this.change('removeCounterEntry', JSON.stringify([entryId]),
      (state: MatterState) => state.removeCounterEntry(entryId), operationId);
  }

  counterEntriesFor(matterId: string, limit: number = 12): CounterEntry[] {
    return this.view().counterEntriesFor(matterId, limit);
  }

  isDailyDoneToday(matterId: string): boolean {
    return this.view().isDailyDoneToday(matterId);
  }

  toggleDailyOnce(matterId: string, note?: string, operationId?: string): Promise<boolean> {
    return this.change('toggleDailyOnce', JSON.stringify([matterId, note]),
      (state: MatterState) => state.toggleDailyOnce(matterId, note), operationId);
  }

  markDailyOnce(matterId: string, operationId?: string): Promise<void> {
    return this.change('markDailyOnce', JSON.stringify([matterId]),
      (state: MatterState) => state.markDailyOnce(matterId), operationId);
  }

  counterStreakDays(matterId: string): number {
    return this.view().counterStreakDays(matterId);
  }

  activeCounterMode(matterId: string): ActiveCounterMode {
    return this.view().activeCounterMode(matterId);
  }

  counterUnit(matterId: string): string {
    return this.view().counterUnit(matterId);
  }

  counterQuickSteps(matterId: string): number[] {
    return this.view().counterQuickSteps(matterId);
  }

  counterSettings(matterId: string): CounterConfig {
    return this.view().counterSettings(matterId);
  }

  counterStep(matterId: string): number {
    return this.view().counterStep(matterId);
  }

  counterTotal(matterId: string): number {
    return this.view().counterTotal(matterId);
  }

  counterToday(matterId: string): number {
    return this.view().counterToday(matterId);
  }

  counterSummaryText(matterId: string): string {
    return this.view().counterSummaryText(matterId);
  }

  getProgressPercent(matterId: string): number {
    return this.view().getProgressPercent(matterId);
  }

  setProgressPercent(matterId: string, percent: number, operationId?: string): Promise<void> {
    return this.change('setProgressPercent', JSON.stringify([matterId, percent]),
      (state: MatterState) => state.setProgressPercent(matterId, percent), operationId);
  }

  getDeadline(matterId: string): DeadlineConfig | undefined {
    return this.view().getDeadline(matterId);
  }

  setDeadline(matterId: string, timestamp: number, location: string, mode: DateMode = 'deadline', hasTime: boolean = false, operationId?: string): Promise<void> {
    return this.change('setDeadline', JSON.stringify([matterId, timestamp, location, mode, hasTime]),
      (state: MatterState) => state.setDeadline(matterId, timestamp, location, mode, hasTime), operationId);
  }

  countdownText(matterId: string): string {
    return this.view().countdownText(matterId);
  }

  getNote(matterId: string): string {
    return this.view().getNote(matterId);
  }

  getAttachments(matterId: string): TimelineAttachment[] {
    return this.view().getAttachments(matterId);
  }

  setNote(matterId: string, text: string, operationId?: string, attachments?: TimelineAttachment[]): Promise<void> {
    return this.change('setNote', JSON.stringify([matterId, text, attachments]),
      (state: MatterState) => state.setNote(matterId, text, attachments), operationId);
  }

  checklistItemsFor(matterId: string): ChecklistItem[] {
    return this.view().checklistItemsFor(matterId);
  }

  listSummaryText(matterId: string): string {
    return this.view().listSummaryText(matterId);
  }

  addChecklistItem(matterId: string, title: string, operationId?: string): Promise<void> {
    return this.change('addChecklistItem', JSON.stringify([matterId, title]),
      (state: MatterState) => state.addChecklistItem(matterId, title), operationId);
  }

  canLinkMatter(ownerMatterId: string, targetMatterId: string): boolean {
    return this.view().canLinkMatter(ownerMatterId, targetMatterId);
  }

  availableMatterLinks(ownerMatterId: string): Matter[] {
    return this.view().availableMatterLinks(ownerMatterId);
  }

  addMatterListEntry(ownerMatterId: string, targetMatterId: string, operationId?: string): Promise<void> {
    return this.change('addMatterListEntry', JSON.stringify([ownerMatterId, targetMatterId]),
      (state: MatterState) => state.addMatterListEntry(ownerMatterId, targetMatterId), operationId);
  }

  linkedMatterFor(entry: ChecklistItem): Matter | undefined {
    return this.view().linkedMatterFor(entry);
  }

  toggleChecklistItem(itemId: string, operationId?: string): Promise<void> {
    return this.change('toggleChecklistItem', JSON.stringify([itemId]),
      (state: MatterState) => state.toggleChecklistItem(itemId), operationId);
  }

  deleteChecklistItem(itemId: string, operationId?: string): Promise<void> {
    return this.change('deleteChecklistItem', JSON.stringify([itemId]),
      (state: MatterState) => state.deleteChecklistItem(itemId), operationId);
  }

  checklistProgressText(matterId: string): string {
    return this.view().checklistProgressText(matterId);
  }

  moduleSummary(matter: Matter): string {
    return this.view().moduleSummary(matter);
  }

  cardPrimaryText(matter: Matter): string {
    return this.view().cardPrimaryText(matter);
  }

  cardQuickActionType(matter: Matter): string {
    return this.view().cardQuickActionType(matter);
  }

  cardQuickActionLabel(matter: Matter): string {
    return this.view().cardQuickActionLabel(matter);
  }

  selectedSingleCardMatterId(): string {
    return this.view().selectedSingleCardMatterId();
  }

  selectedSingleCardMatter(): Matter | undefined {
    return this.view().selectedSingleCardMatter();
  }

  setSingleCardMatter(id: string, operationId?: string): Promise<void> {
    return this.change('setSingleCardMatter', JSON.stringify([id]),
      (state: MatterState) => state.setSingleCardMatter(id), operationId);
  }

  selectedSummaryCardMatterIds(): string[] {
    return this.view().selectedSummaryCardMatterIds();
  }

  selectedSummaryCardMatters(): Matter[] {
    return this.view().selectedSummaryCardMatters();
  }

  isSummaryCardMatterSelected(id: string): boolean {
    return this.view().isSummaryCardMatterSelected(id);
  }

  toggleSummaryCardMatter(id: string, operationId?: string): Promise<void> {
    return this.change('toggleSummaryCardMatter', JSON.stringify([id]),
      (state: MatterState) => state.toggleSummaryCardMatter(id), operationId);
  }

  rememberCardForm(formId: string, operationId?: string): Promise<void> {
    return this.change('rememberCardForm', JSON.stringify([formId]),
      (state: MatterState) => state.rememberCardForm(formId), operationId);
  }

  removeCardForm(formId: string, operationId?: string): Promise<void> {
    return this.change('removeCardForm', JSON.stringify([formId]),
      (state: MatterState) => state.removeCardForm(formId), operationId);
  }

  cardFormIds(): string[] {
    return this.view().cardFormIds();
  }

  addDeckExamples(operationId?: string): Promise<number> {
    return this.change('addDeckExamples', JSON.stringify([]),
      (state: MatterState) => state.addDeckExamples(), operationId);
  }

  resetDemoData(operationId?: string): Promise<void> {
    return this.change('resetDemoData', JSON.stringify([]),
      (state: MatterState) => state.resetDemoData(), operationId);
  }

  defaultConfigFor(type: ModuleType): string {
    return this.view().defaultConfigFor(type);
  }
}
