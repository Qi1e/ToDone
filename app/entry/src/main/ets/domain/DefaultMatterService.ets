import { applyEditor, editorDraft, EditorDraft, EditorItem } from './MatterEditor';
import { daysUntil } from '../common/DateFormat';
import { CreateMatterRequest, CreateMatterResult, MatterRepository, MatterService } from '../contracts/MatterService';
import { createId, createMatter, createModuleInstance } from '../model/Defaults';
import { AppState, ChecklistItem, Matter, ModuleInstance, ModuleType } from '../model/Types';
import { canLinkMatterInState } from './MatterLinks';
import { MatterOperation } from '../contracts/MatterPersistence';
import { MatterDataError, matterErrorMessage } from './MatterSnapshot';

interface PendingMatterSave {
  operation: MatterOperation;
  apply: (state: AppState) => string;
}

export class DefaultMatterService implements MatterService {
  private repository: MatterRepository;
  private pending: Map<string, PendingMatterSave> = new Map();

  constructor(repository: MatterRepository) {
    this.repository = repository;
  }

  linkCandidates(draft: EditorDraft, ownerId: string): Matter[] {
    if (ownerId) return [];
    const state = this.repository.readState();
    let source = state.matters.find((m: Matter) => m.id === draft.id);
    if (!source) {
      source = createMatter({ title: draft.title }, state.matters.length);
      source.id = draft.id;
      state.matters.push(source);
    }
    if (!source.enabledModules.some((m: ModuleInstance) => m.moduleType === ModuleType.Checklist)) {
      source.enabledModules.push(createModuleInstance(draft.id, ModuleType.Checklist));
    }
    state.checklistItems = state.checklistItems.filter((i: ChecklistItem) => i.matterId !== draft.id);
    return state.matters.filter((m: Matter) => canLinkMatterInState(state, draft.id, m.id) &&
      !m.enabledModules.some((module: ModuleInstance) => module.moduleType === ModuleType.Checklist) &&
      !draft.items.some((i: EditorItem) => i.targetId === m.id));
  }

  loadEditor(id: string): EditorDraft | undefined {
    return editorDraft(this.repository.readState(), id);
  }

  async saveEditor(draft: EditorDraft, ownerId: string): Promise<CreateMatterResult> {
    if (!draft.token) draft.token = createId('save');
    const frozen = JSON.parse(JSON.stringify(draft)) as EditorDraft;
    const operation: MatterOperation = { id: frozen.token, fingerprint: 'editor:' + JSON.stringify([frozen, ownerId]) };
    return this.persist(frozen.id, { operation, apply: (state: AppState): string => {
      // 兼容旧版已保存 token 的草稿，后续重复请求由持久化回执识别。
      if (state.matters.some((matter: Matter) => matter.id === frozen.id && matter.lastEditorToken === frozen.token)) {
        return frozen.id;
      }
      const error = applyEditor(state, frozen, ownerId);
      if (error) throw new MatterDataError('invalid_editor', error);
      return frozen.id;
    } });
  }

  activeMatters(): Matter[] {
    return this.sortedMatters().filter((matter: Matter) => !matter.archived);
  }

  archivedMatters(): Matter[] {
    return this.sortedMatters().filter((matter: Matter) => matter.archived);
  }

  findMatter(id: string): Matter | undefined {
    return this.repository.readState().matters.find((matter: Matter) => matter.id === id);
  }

  private sortedMatters(): Matter[] {
    return this.repository.readState().matters.sort((a: Matter, b: Matter) => a.orderIndex - b.orderIndex);
  }

  async createMatter(request: CreateMatterRequest): Promise<CreateMatterResult> {
    const intent = request.intent;
    if (intent.title.trim().length === 0) {
      return this.failure('invalid_title', '请先填写事项名称');
    }
    const types = intent.enabledModuleTypes ?? [];
    if ((types.includes(ModuleType.Deadline) || intent.deadlineTimestamp !== undefined) &&
      (intent.deadlineTimestamp === undefined || !Number.isFinite(intent.deadlineTimestamp))) {
      return this.failure('invalid_deadline', '请选择有效的截止日期');
    }
    if (intent.deadlineMode === 'elapsed' && intent.deadlineTimestamp !== undefined &&
      daysUntil(intent.deadlineTimestamp) > 0) {
      return this.failure('invalid_deadline', '正数日的起始日期不能晚于今天');
    }
    const titles = (request.checklistTitles ?? []).map((title: string) => title.trim())
      .filter((title: string) => title.length > 0);
    if (titles.length > 0 && !types.includes(ModuleType.Checklist)) {
      return this.failure('invalid_checklist', '添加列表项前请启用列表信息');
    }

    const frozen = JSON.parse(JSON.stringify(request)) as CreateMatterRequest;
    const matter = createMatter(frozen.intent, 0);
    const operation: MatterOperation = { id: createId('create'), fingerprint: 'create:' + JSON.stringify(frozen) };
    return this.persist(matter.id, { operation, apply: (state: AppState): string => {
      const created = JSON.parse(JSON.stringify(matter)) as Matter;
      created.orderIndex = state.matters.length;
      state.matters.push(created);
      const ownerId = frozen.ownerMatterId ?? '';
      if (ownerId.length > 0) {
        if (!canLinkMatterInState(state, ownerId, matter.id)) {
          throw new MatterDataError('invalid_owner', '原列表已不可用，请返回后重新选择');
        }
        this.appendItem(state, ownerId, matter.title, matter.id);
      }
      titles.forEach((title: string) => this.appendItem(state, matter.id, title));
      return matter.id;
    } });
  }

  async retrySave(matterId: string): Promise<CreateMatterResult> {
    const pending = this.pending.get(matterId);
    if (pending) return this.persist(matterId, pending);
    try {
      await this.repository.reload();
      if (this.findMatter(matterId)) return { success: true, matterId, errorCode: '', message: '事项已保存' };
      return this.failure('missing_matter', '事项已不存在，请返回首页确认');
    } catch (error) {
      return { success: false, matterId, errorCode: 'save_failed', message: matterErrorMessage(error as Error) };
    }
  }

  private appendItem(state: AppState, ownerId: string, title: string, targetId?: string): void {
    const now = Date.now();
    state.checklistItems.push({
      id: createId(targetId ? 'matter_link' : 'check'),
      matterId: ownerId,
      title,
      completed: false,
      entryType: targetId ? 'matter_ref' : 'text',
      targetMatterId: targetId,
      orderIndex: state.checklistItems.filter((item: ChecklistItem) => item.matterId === ownerId).length,
      createdAt: now,
      updatedAt: now
    });
  }

  private async persist(matterId: string, pending: PendingMatterSave): Promise<CreateMatterResult> {
    this.pending.set(matterId, pending);
    try {
      const savedId = await this.repository.transact(pending.operation, pending.apply);
      this.pending.delete(matterId);
      return { success: true, matterId: savedId, errorCode: '', message: '事项已保存' };
    } catch (error) {
      if (error instanceof MatterDataError && error.code.startsWith('invalid_')) {
        this.pending.delete(matterId);
        return this.failure(error.code, error.message);
      }
      return { success: false, matterId, errorCode: 'save_failed', message: matterErrorMessage(error as Error) };
    }
  }

  private failure(errorCode: string, message: string): CreateMatterResult {
    return { success: false, matterId: '', errorCode, message };
  }
}
