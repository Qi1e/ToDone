import { TimelineTag } from './TimelineService';
import { EditorDraft } from '../domain/MatterEditor';
import { AppState, CreateMatterIntent, Matter } from '../model/Types';
import { MatterOperation } from './MatterPersistence';

export interface CreateMatterRequest {
  intent: CreateMatterIntent;
  ownerMatterId?: string;
  checklistTitles?: string[];
}

export interface CreateMatterResult {
  success: boolean;
  // 保存未确认时保留同一事项与请求身份，重试原操作。
  matterId: string;
  errorCode: string;
  message: string;
}

export interface MatterService {
  linkCandidates(draft: EditorDraft, ownerId: string): Matter[];
  loadEditor(id: string, occurrenceStart?: number): EditorDraft | undefined;
  saveEditor(draft: EditorDraft, ownerId: string): Promise<CreateMatterResult>;
  listTags(): TimelineTag[];
  saveTag(tag: TimelineTag): Promise<TimelineTag>;
  activeMatters(): Matter[];
  residentActiveMatters(): Matter[];
  mattersForDay(dayTimestamp: number): Matter[];
  archivedMatters(): Matter[];
  findMatter(id: string): Matter | undefined;
  createMatter(request: CreateMatterRequest): Promise<CreateMatterResult>;
  retrySave(matterId: string): Promise<CreateMatterResult>;
}

export interface MatterRepository {
  // 返回独立快照，调用方不能直接修改仓库中的状态。
  readState(): AppState;
  reload(): Promise<void>;
  // 回调可在版本冲突后重跑，只修改传入状态。提交确认后才发布结果。
  transact<T>(operation: MatterOperation, change: (state: AppState) => T): Promise<T>;
}
