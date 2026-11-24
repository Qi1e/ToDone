import { MatterSnapshot } from '../contracts/MatterPersistence';
import { AppState, Matter } from '../model/Types';

export class MatterDataError extends Error {
  code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

export function emptyMatterState(): AppState {
  return { matters: [], clusters: [], eventRecords: [], counterEntries: [], checklistItems: [],
    singleCardMatterId: '', summaryCardMatterIds: [], cardFormIds: [] };
}

export function normalizeMatterState(input: AppState): AppState {
  if (!input || !Array.isArray(input.matters) ||
    (input.clusters !== undefined && !Array.isArray(input.clusters)) ||
    (input.tags !== undefined && !Array.isArray(input.tags)) ||
    (input.eventRecords !== undefined && !Array.isArray(input.eventRecords)) ||
    (input.counterEntries !== undefined && !Array.isArray(input.counterEntries)) ||
    (input.checklistItems !== undefined && !Array.isArray(input.checklistItems)) ||
    (input.summaryCardMatterIds !== undefined && !Array.isArray(input.summaryCardMatterIds)) ||
    (input.cardFormIds !== undefined && !Array.isArray(input.cardFormIds))) {
    throw new MatterDataError('MAT-DATA', '事项存档格式错误，原数据已保留');
  }
  input.matters.forEach((matter: Matter) => {
    if (!matter || typeof matter.id !== 'string' || !matter.id || typeof matter.title !== 'string' ||
      !Array.isArray(matter.enabledModules) || !Number.isFinite(matter.orderIndex)) {
      throw new MatterDataError('MAT-DATA', '事项内容损坏，原数据已保留');
    }
  });
  input.matters.sort((a: Matter, b: Matter) => a.orderIndex - b.orderIndex);
  input.clusters = input.clusters ?? [];
  input.eventRecords = input.eventRecords ?? [];
  input.counterEntries = input.counterEntries ?? [];
  input.checklistItems = input.checklistItems ?? [];
  input.singleCardMatterId = input.singleCardMatterId ?? '';
  input.summaryCardMatterIds = input.summaryCardMatterIds ?? input.matters
    .filter((matter: Matter) => !matter.archived).slice(0, 3).map((matter: Matter) => matter.id);
  input.cardFormIds = input.cardFormIds ?? [];
  return input;
}

export function readLegacyMatterState(raw: string): AppState {
  try {
    return normalizeMatterState(JSON.parse(raw) as AppState);
  } catch (error) {
    if (error instanceof MatterDataError) throw error;
    throw new MatterDataError('MAT-JSON', '事项存档无法读取，原数据已保留');
  }
}

export function decodeMatterSnapshot(raw: string, revision: number): MatterSnapshot {
  let snapshot: MatterSnapshot;
  try {
    snapshot = JSON.parse(raw) as MatterSnapshot;
  } catch (error) {
    throw new MatterDataError('MAT-JSON', '事项存档无法读取，原数据已保留');
  }
  if (!snapshot || snapshot.version !== 1 || !Number.isSafeInteger(revision) || revision < 0 ||
    snapshot.revision !== revision || !Array.isArray(snapshot.receipts)) {
    throw new MatterDataError('MAT-VERSION', '事项存档版本或提交记录无法读取');
  }
  snapshot.receipts.forEach((receipt) => {
    if (!receipt || typeof receipt.id !== 'string' || !receipt.id ||
      typeof receipt.fingerprint !== 'string' || typeof receipt.result !== 'string') {
      throw new MatterDataError('MAT-DATA', '事项提交记录损坏，原数据已保留');
    }
  });
  snapshot.state = normalizeMatterState(snapshot.state);
  return snapshot;
}

export function matterErrorMessage(error: Error): string {
  if (error instanceof MatterDataError) return `${error.message}（${error.code}）`;
  return '事项保存尚未确认，请重试原操作';
}
