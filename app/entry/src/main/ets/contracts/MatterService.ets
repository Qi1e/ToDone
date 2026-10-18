import { AppState, CreateMatterIntent, Matter } from '../model/Types';

export interface CreateMatterRequest {
  intent: CreateMatterIntent;
  ownerMatterId?: string;
  checklistTitles?: string[];
}

export interface CreateMatterResult {
  success: boolean;
  // 保存失败时可能已写入内存；使用此 ID 重试保存，不重复创建。
  matterId: string;
  errorCode: string;
  message: string;
}

export interface MatterService {
  activeMatters(): Matter[];
  archivedMatters(): Matter[];
  findMatter(id: string): Matter | undefined;
  createMatter(request: CreateMatterRequest): Promise<CreateMatterResult>;
  retrySave(matterId: string): Promise<CreateMatterResult>;
}

export interface MatterRepository {
  // 返回独立快照，调用方不能直接修改仓库中的状态。
  readState(): AppState;
  // 先发布内存状态，再等待持久化。失败不承诺回滚，调用方可重试同一快照。
  commitState(state: AppState): Promise<void>;
}
