import { applyEditor, editorDraft, EditorDraft, EditorItem } from './MatterEditor';
import { daysUntil } from '../common/DateFormat';
import { CreateMatterRequest, CreateMatterResult, MatterRepository, MatterService } from '../contracts/MatterService';
import { createId, createMatter, createModuleInstance } from '../model/Defaults';
import { AppState, ChecklistItem, Matter, ModuleInstance, ModuleType } from '../model/Types';
import { canLinkMatterInState } from './MatterLinks';

export class DefaultMatterService implements MatterService {
  private repository: MatterRepository;

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
    const state = this.repository.readState();
    if (draft.token && state.matters.some((m: Matter) => m.id === draft.id && m.lastEditorToken === draft.token)) {
      return this.persist(state, draft.id);
    }
    const error = applyEditor(state, draft, ownerId);
    if (error) return this.failure('invalid_editor', error);
    return this.persist(state, draft.id);
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

    const state = this.repository.readState();
    const matter = createMatter(intent, state.matters.length);
    state.matters.push(matter);
    const ownerId = request.ownerMatterId ?? '';
    if (ownerId.length > 0) {
      if (!canLinkMatterInState(state, ownerId, matter.id)) {
        return this.failure('invalid_owner', '原列表已不可用，请返回后重新选择');
      }
      this.appendItem(state, ownerId, matter.title, matter.id);
    }
    titles.forEach((title: string) => this.appendItem(state, matter.id, title));
    return this.persist(state, matter.id);
  }

  async retrySave(matterId: string): Promise<CreateMatterResult> {
    const state = this.repository.readState();
    if (!state.matters.some((matter: Matter) => matter.id === matterId)) {
      return this.failure('missing_matter', '事项已不存在，请返回首页确认');
    }
    return this.persist(state, matterId);
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

  private async persist(state: AppState, matterId: string): Promise<CreateMatterResult> {
    try {
      await this.repository.commitState(state);
      return { success: true, matterId, errorCode: '', message: '事项已保存' };
    } catch (error) {
      const retained = this.findMatter(matterId) !== undefined;
      return {
        success: false,
        matterId: retained ? matterId : '',
        errorCode: 'save_failed',
        message: retained ? '事项已暂存，但保存未确认。请重试保存，勿重复创建。' : '无法保存事项，请检查存储后重试。'
      };
    }
  }

  private failure(errorCode: string, message: string): CreateMatterResult {
    return { success: false, matterId: '', errorCode, message };
  }
}
