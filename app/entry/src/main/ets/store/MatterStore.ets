import { common } from '@kit.AbilityKit';
import { MatterRepository } from '../contracts/MatterService';
import { MatterOperation } from '../contracts/MatterPersistence';
import { MatterState } from '../domain/MatterState';
import { MatterDataError, emptyMatterState } from '../domain/MatterSnapshot';
import { TransactionalMatterRepository } from '../domain/TransactionalMatterRepository';
import { createId } from '../model/Defaults';
import { AppState, ChecklistItem, CounterConfig, CreateMatterIntent, DateMode, DeadlineConfig,
  EventRecordEntry, Matter, ModuleType } from '../model/Types';
import { RdbMatterPersistence } from './RdbMatterPersistence';

export class MatterStore implements MatterRepository {
  private static instance: MatterStore = new MatterStore();
  private repository?: TransactionalMatterRepository;
  private listeners: Set<() => void> = new Set();
  private failedOperations: Map<string, MatterOperation> = new Map();

  static getInstance(): MatterStore {
    return MatterStore.instance;
  }

  async init(context: common.UIAbilityContext | common.FormExtensionContext): Promise<void> {
    if (!this.repository) this.repository = new TransactionalMatterRepository(new RdbMatterPersistence(context));
    await this.reload();
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

  addCounterEntry(matterId: string, value: number, operationId?: string): Promise<void> {
    return this.change('addCounterEntry', JSON.stringify([matterId, value]),
      (state: MatterState) => state.addCounterEntry(matterId, value), operationId);
  }

  markDailyOnce(matterId: string, operationId?: string): Promise<void> {
    return this.change('markDailyOnce', JSON.stringify([matterId]),
      (state: MatterState) => state.markDailyOnce(matterId), operationId);
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

  setNote(matterId: string, text: string, operationId?: string): Promise<void> {
    return this.change('setNote', JSON.stringify([matterId, text]),
      (state: MatterState) => state.setNote(matterId, text), operationId);
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
