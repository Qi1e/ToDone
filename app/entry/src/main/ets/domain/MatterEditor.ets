import { createId, createMatter, createModuleInstance } from '../model/Defaults';
import { AppState, ChecklistItem, CounterConfig, DateMode, DeadlineConfig, Matter, ModuleInstance, ModuleType, NoteConfig } from '../model/Types';
import { daysUntil } from '../common/DateFormat';
import { canLinkMatterInState } from './MatterLinks';

export interface EditorItem {
  id: string;
  title: string;
  targetId?: string;
}

export class EditorDraft {
  id: string = createId('matter');
  token: string = '';
  editing: boolean = false;
  baseline: string = '';
  title: string = '';
  description: string = '';
  types: ModuleType[] = [];
  timestamp: number = Date.now();
  mode: DateMode = 'deadline';
  hasTime: boolean = false;
  location: string = '';
  note: string = '';
  initial: string = '0';
  step: string = '1';
  dateName: string = '';
  counterName: string = '';
  recordName: string = '';
  items: EditorItem[] = [];
  pending: string = '';
}

export function editorDraft(state: AppState, id: string): EditorDraft | undefined {
  const draft = new EditorDraft();
  if (!id) return draft;
  const matter = state.matters.find((m: Matter) => m.id === id);
  if (!matter) return undefined;
  draft.editing = true;
  draft.id = id;
  draft.title = matter.title;
  draft.description = matter.description ?? '';
  draft.types = matter.enabledModules.map((m: ModuleInstance) => m.moduleType)
    .filter((t: ModuleType) => t !== ModuleType.Countdown && t !== ModuleType.Progress);
  const modules = matter.enabledModules.concat(matter.disabledModules ?? []);
  for (const module of modules) {
    if (module.moduleType === ModuleType.Deadline) {
      const date = JSON.parse(module.configJson) as DeadlineConfig;
      draft.dateName = module.name ?? '';
      draft.timestamp = date.timestamp;
      draft.mode = date.mode ?? 'deadline';
      draft.hasTime = date.hasTime;
      draft.location = date.location ?? '';
    } else if (module.moduleType === ModuleType.Counter) {
      const counter = JSON.parse(module.configJson) as CounterConfig;
      draft.counterName = module.name ?? '';
      draft.initial = String(counter.initialValue ?? 0);
      draft.step = String(counter.fixedSteps?.[0] ?? 1);
    } else if (module.moduleType === ModuleType.Note) {
      draft.note = (JSON.parse(module.configJson) as NoteConfig).text;
    } else if (module.moduleType === ModuleType.EventRecord) {
      draft.recordName = module.name ?? '';
    }
  }
  draft.items = state.checklistItems.filter((i: ChecklistItem) => i.matterId === id)
    .sort((a: ChecklistItem, b: ChecklistItem) => a.orderIndex - b.orderIndex)
    .map((i: ChecklistItem): EditorItem => ({ id: i.id, title: i.title, targetId: i.targetMatterId }));
  draft.baseline = JSON.stringify([matter.title, matter.description ?? '', JSON.stringify(modules),
    JSON.stringify(draft.types), JSON.stringify(draft.items)]);
  return draft;
}

export function invalidEditorField(d: EditorDraft): string {
  if (!d.title.trim()) return 'title';
  for (const type of d.types) {
    if (type === ModuleType.Counter && (!d.initial.trim() || !Number.isFinite(Number(d.initial)) ||
      Number(d.initial) < 0 || !Number.isFinite(Number(d.step)) || Number(d.step) <= 0)) return type;
    if (type === ModuleType.Deadline && (!Number.isFinite(d.timestamp) ||
      (d.mode === 'elapsed' && daysUntil(d.timestamp) > 0))) return type;
    if (type === ModuleType.Note && !d.note.trim()) return type;
    if (type === ModuleType.Checklist && d.items.some((i: EditorItem) => !i.title.trim())) return type;
  }
  return '';
}

// The caller owns this snapshot and commits it only after all link checks succeed.
export function applyEditor(state: AppState, d: EditorDraft, ownerId: string): string {
  if (invalidEditorField(d)) return '请检查标记的输入';
  const existing = state.matters.find((m: Matter) => m.id === d.id);
  if (d.editing && (!existing || editorDraft(state, d.id)?.baseline !== d.baseline)) {
    return '原事项已变更或删除，请放弃旧草稿后重新编辑';
  }
  if (!d.editing && existing) return '该事项已保存，请返回首页查看';
  const matter = existing ?? createMatter({ title: d.title }, state.matters.length);
  if (!existing) {
    matter.id = d.id;
    state.matters.push(matter);
  }
  matter.lastEditorToken = d.token;
  matter.title = d.title.trim();
  matter.description = d.description.trim();
  const all = matter.enabledModules.concat(matter.disabledModules ?? []);
  const selected: ModuleInstance[] = [];
  for (const type of d.types) {
    const module = all.find((m: ModuleInstance) => m.moduleType === type) ?? createModuleInstance(d.id, type);
    if (type === ModuleType.Deadline) {
      const date: DeadlineConfig = { timestamp: d.timestamp, mode: d.mode, hasTime: d.mode === 'deadline' && d.hasTime,
        location: d.location };
      module.name = d.dateName.trim();
      module.configJson = JSON.stringify(date);
    } else if (type === ModuleType.Counter) {
      const config = JSON.parse(module.configJson) as CounterConfig;
      module.name = d.counterName.trim();
      config.initialValue = Number(d.initial);
      config.fixedSteps = [Number(d.step)].concat((config.fixedSteps ?? []).slice(1));
      module.configJson = JSON.stringify(config);
    } else if (type === ModuleType.Note) {
      const note: NoteConfig = { text: d.note.trim() };
      module.configJson = JSON.stringify(note);
    } else if (type === ModuleType.EventRecord) {
      module.name = d.recordName.trim();
    }
    selected.push(module);
  }
  if (d.types.includes(ModuleType.Deadline)) selected.push(all.find((m: ModuleInstance) =>
    m.moduleType === ModuleType.Countdown) ?? createModuleInstance(d.id, ModuleType.Countdown));
  matter.enabledModules = selected.concat(all.filter((m: ModuleInstance) => m.moduleType === ModuleType.Progress));
  matter.disabledModules = all.filter((m: ModuleInstance) => m.moduleType !== ModuleType.Countdown &&
    m.moduleType !== ModuleType.Progress && !d.types.includes(m.moduleType));
  matter.updatedAt = Date.now();
  if (d.types.includes(ModuleType.Checklist)) {
    const previous = state.checklistItems.filter((i: ChecklistItem) => i.matterId === d.id);
    state.checklistItems = state.checklistItems.filter((i: ChecklistItem) => i.matterId !== d.id);
    const items = d.items.slice();
    if (d.pending.trim()) items.push({ id: createId('check'), title: d.pending.trim() });
    let order = 0;
    for (const item of items) {
      const old = previous.find((i: ChecklistItem) => i.id === item.id);
      if (item.targetId && old?.targetMatterId !== item.targetId &&
        (!canLinkMatterInState(state, d.id, item.targetId) || state.matters.find((m: Matter) => m.id === item.targetId)
          ?.enabledModules.some((module: ModuleInstance) => module.moduleType === ModuleType.Checklist))) {
        return '所选事项已不可关联，请重新选择';
      }
      state.checklistItems.push({ id: item.id, matterId: d.id, title: item.title.trim(), completed: old?.completed ?? false,
        entryType: item.targetId ? 'matter_ref' : 'text', targetMatterId: item.targetId, orderIndex: order++,
        createdAt: old?.createdAt ?? matter.updatedAt, updatedAt: matter.updatedAt });
    }
  }
  if (ownerId) {
    if (!canLinkMatterInState(state, ownerId, d.id)) return '原列表已不可用或无法嵌套关联';
    state.checklistItems.push({ id: createId('link'), matterId: ownerId, title: matter.title, completed: false,
      entryType: 'matter_ref', targetMatterId: d.id, orderIndex: state.checklistItems.filter((i: ChecklistItem) =>
        i.matterId === ownerId).length, createdAt: matter.updatedAt, updatedAt: matter.updatedAt });
  }
  return '';
}
