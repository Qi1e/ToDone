import {
  copyTimelineAttachments,
  TIMELINE_REMINDER_MINUTES,
  TimelineAttachment,
  TimelineBlock,
  TimelineEditScope,
  TimelineRepeat
} from '../contracts/TimelineService';
import { daysUntil, effectiveDayCountMode, effectiveSpan } from '../common/DateFormat';
import { createId, createMatter, createModuleInstance } from '../model/Defaults';
import {
  ActiveCounterMode,
  AppState,
  ChecklistItem,
  CounterConfig,
  DayCountMode,
  DeadlineConfig,
  EventRecordEntry,
  Matter,
  ModuleInstance,
  ModuleType,
  NoteConfig,
  TagConfig,
  TimeSpanMode
} from '../model/Types';
import { canLinkMatterInState } from './MatterLinks';
import {
  applyRecurringMatterEdit,
  effectiveMatterNote,
  effectiveMatterTagId,
  matterToTimelineBlock,
  normalizeSeriesRangeOnSave
} from './MatterSchedule';
import { nominalOccurrence, overriddenOccurrence } from './TimelineRecurrence';

export interface EditorItem {
  id: string;
  title: string;
  targetId?: string;
}

export class EditorDraft {
  id: string = createId('matter');
  token: string = '';
  editing: boolean = false;
  occurrenceStart?: number = undefined;
  isSeries: boolean = false;
  originalRepeat: TimelineRepeat = TimelineRepeat.None;
  editScope?: TimelineEditScope = undefined;
  baseline: string = '';
  title: string = '';
  types: ModuleType[] = [];

  // 时间模块
  span: TimeSpanMode = 'all_day';
  timestamp: number = Date.now();
  endAt: number = Date.now() + 3600000;
  dayCountMode: DayCountMode = 'countdown';
  reminderMinutes: number = -1;
  repeat: TimelineRepeat = TimelineRepeat.None;

  // 标签模块
  tagId: string = '';

  // 计数模块（合并计次 / 计量 / 每日打卡）
  counterMode: ActiveCounterMode = 'tally';
  unit: string = '次';
  initial: string = '0';
  step: string = '1';
  step2: string = '';

  // 备注与图文附件
  note: string = '';
  attachments: TimelineAttachment[] = [];

  // 列表模块
  items: EditorItem[] = [];
  pending: string = '';
}

function defaultEndFor(startAt: number): number {
  const base = new Date(startAt);
  if (base.getHours() === 23) {
    return startAt + 30 * 60000;
  }
  return startAt + 60 * 60000;
}

export function editorDraft(state: AppState, id: string, occurrenceStart?: number): EditorDraft | undefined {
  const draft = new EditorDraft();
  const rounded = new Date();
  rounded.setMinutes(0, 0, 0);
  rounded.setHours(Math.min(22, rounded.getHours() + 1));
  draft.timestamp = rounded.getTime();
  draft.endAt = rounded.getTime() + 3600000;
  if (!id) return draft;

  const matter = state.matters.find((m: Matter) => m.id === id);
  if (!matter) return undefined;
  draft.editing = true;
  draft.id = id;
  draft.title = matter.title;

  const normalizedTypes: ModuleType[] = [];
  const pushUnique = (t: ModuleType): void => {
    if (!normalizedTypes.includes(t)) normalizedTypes.push(t);
  };
  for (const mod of matter.enabledModules) {
    if (mod.moduleType === ModuleType.Countdown || mod.moduleType === ModuleType.Progress) continue;
    if (mod.moduleType === ModuleType.EventRecord) {
      pushUnique(ModuleType.Counter);
    } else {
      pushUnique(mod.moduleType);
    }
  }

  const mergedNote = effectiveMatterNote(matter);
  if ((mergedNote.text.trim().length > 0 || (mergedNote.attachments?.length ?? 0) > 0) &&
    !normalizedTypes.includes(ModuleType.Note) &&
    !(matter.disabledModules ?? []).some((m: ModuleInstance) => m.moduleType === ModuleType.Note)) {
    pushUnique(ModuleType.Note);
  }
  const activeTagId = effectiveMatterTagId(state, matter);
  if (activeTagId && !normalizedTypes.includes(ModuleType.Tag) &&
    !(matter.disabledModules ?? []).some((m: ModuleInstance) => m.moduleType === ModuleType.Tag)) {
    pushUnique(ModuleType.Tag);
  }
  draft.types = normalizedTypes;

  const modules = matter.enabledModules.concat(matter.disabledModules ?? []);
  let sawCounter = false;
  for (const module of modules) {
    if (module.moduleType === ModuleType.Deadline) {
      try {
        const date = JSON.parse(module.configJson) as DeadlineConfig;
        draft.span = effectiveSpan(date);
        draft.dayCountMode = effectiveDayCountMode(date);
        draft.timestamp = date.timestamp;
        draft.endAt = date.endAt && date.endAt > date.timestamp ? date.endAt : defaultEndFor(date.timestamp);
        draft.reminderMinutes = date.reminderMinutes !== undefined &&
          TIMELINE_REMINDER_MINUTES.includes(date.reminderMinutes) ? date.reminderMinutes : -1;
        draft.repeat = date.repeat ?? TimelineRepeat.None;
      } catch (error) {}
    } else if (module.moduleType === ModuleType.Tag) {
      try {
        const cfg = JSON.parse(module.configJson) as TagConfig;
        draft.tagId = cfg.tagId ?? '';
      } catch (error) {}
    } else if (module.moduleType === ModuleType.Counter) {
      sawCounter = true;
      try {
        const counter = JSON.parse(module.configJson) as CounterConfig;
        if (counter.mode === 'tally' || counter.mode === 'amount' || counter.mode === 'daily_once') {
          draft.counterMode = counter.mode;
        } else {
          draft.counterMode = 'amount';
        }
        draft.unit = counter.unit ?? (draft.counterMode === 'tally' ? '次' : '');
        draft.initial = String(counter.initialValue ?? 0);
        const steps = (counter.fixedSteps ?? []).filter((v: number) => Number.isFinite(v) && v > 0);
        draft.step = String(steps[0] ?? 1);
        draft.step2 = steps.length > 1 ? String(steps[1]) : '';
      } catch (error) {}
    } else if (module.moduleType === ModuleType.EventRecord && !sawCounter) {
      draft.counterMode = 'tally';
      draft.unit = '次';
      draft.initial = '0';
      draft.step = '1';
      draft.step2 = '';
    } else if (module.moduleType === ModuleType.Note) {
      try {
        const noteCfg = JSON.parse(module.configJson) as NoteConfig;
        draft.note = noteCfg.text ?? '';
        draft.attachments = copyTimelineAttachments(noteCfg.attachments) ?? [];
      } catch (error) {}
    }
  }
  if (!draft.tagId && activeTagId) {
    draft.tagId = activeTagId;
  }
  if (mergedNote.text.length > 0 && draft.types.includes(ModuleType.Note)) {
    draft.note = mergedNote.text;
  }
  if ((mergedNote.attachments?.length ?? 0) > 0 && draft.attachments.length === 0) {
    draft.attachments = mergedNote.attachments ?? [];
  }

  // 若指定了重复系列的某一次实例，加载该次实例的内容与时段
  const seriesBlock = matterToTimelineBlock(state, matter);
  if (seriesBlock && seriesBlock.repeat && seriesBlock.repeat !== TimelineRepeat.None) {
    draft.isSeries = true;
    draft.originalRepeat = seriesBlock.repeat;
    if (occurrenceStart !== undefined && Number.isSafeInteger(occurrenceStart)) {
      const nom = nominalOccurrence(seriesBlock, occurrenceStart);
      if (nom) {
        const ov = seriesBlock.overrides?.find((o) => o.originalStart === occurrenceStart);
        const target = ov ? overriddenOccurrence(seriesBlock, ov) : nom;
        draft.occurrenceStart = occurrenceStart;
        draft.title = target.title;
        draft.span = 'range';
        draft.timestamp = target.startAt;
        draft.endAt = target.endAt;
        draft.reminderMinutes = target.reminderMinutes ?? -1;
        draft.note = target.note;
        draft.attachments = copyTimelineAttachments(target.attachments) ?? [];
        if (target.note.trim().length > 0 || draft.attachments.length > 0) {
          if (!draft.types.includes(ModuleType.Note)) draft.types = draft.types.concat(ModuleType.Note);
        }
        if (target.tagId) {
          draft.tagId = target.tagId;
          if (!draft.types.includes(ModuleType.Tag)) draft.types = draft.types.concat(ModuleType.Tag);
        } else {
          draft.tagId = '';
          draft.types = draft.types.filter((t: ModuleType) => t !== ModuleType.Tag);
        }
      }
    }
  }

  draft.items = state.checklistItems
    .filter((i: ChecklistItem) => i.matterId === id)
    .sort((a: ChecklistItem, b: ChecklistItem) => a.orderIndex - b.orderIndex)
    .map((i: ChecklistItem): EditorItem => ({ id: i.id, title: i.title, targetId: i.targetMatterId }));
  draft.baseline = computeBaseline(state, matter);
  return draft;
}

function computeBaseline(state: AppState, matter: Matter): string {
  const modules = matter.enabledModules.concat(matter.disabledModules ?? []);
  const items = state.checklistItems
    .filter((i: ChecklistItem) => i.matterId === matter.id)
    .sort((a: ChecklistItem, b: ChecklistItem) => a.orderIndex - b.orderIndex)
    .map((i: ChecklistItem): EditorItem => ({ id: i.id, title: i.title, targetId: i.targetMatterId }));
  return JSON.stringify([
    matter.title,
    matter.description ?? '',
    matter.tagId ?? '',
    JSON.stringify(modules),
    JSON.stringify(items)
  ]);
}

export function invalidEditorField(d: EditorDraft): string {
  if (!d.title.trim()) return 'title';
  for (const type of d.types) {
    if (type === ModuleType.Deadline) {
      if (!Number.isFinite(d.timestamp)) return type;
      if (d.span === 'range' && (!Number.isFinite(d.endAt) || !(d.endAt > d.timestamp))) return type;
      if (d.dayCountMode === 'elapsed' && daysUntil(d.timestamp) > 0) return type;
    }
    if (type === ModuleType.Tag && !d.tagId.trim()) return type;
    if (type === ModuleType.Counter) {
      const initNum = Number(d.initial);
      const stepNum = Number(d.step);
      if (!d.initial.trim() || !Number.isFinite(initNum) || initNum < 0) return type;
      if (!d.step.trim() || !Number.isFinite(stepNum) || stepNum <= 0) return type;
      if (d.counterMode === 'amount' && d.step2.trim().length > 0) {
        const s2 = Number(d.step2);
        if (!Number.isFinite(s2) || s2 <= 0) return type;
      }
    }
    if (type === ModuleType.Note && !d.note.trim() && (!d.attachments || d.attachments.length === 0)) {
      return type;
    }
    if (type === ModuleType.Checklist && d.items.some((i: EditorItem) => !i.title.trim())) {
      return type;
    }
  }
  return '';
}

// The caller owns this snapshot and commits it only after all link checks succeed.
export function applyEditor(state: AppState, d: EditorDraft, ownerId: string): string {
  if (invalidEditorField(d)) return '请检查标记的输入';
  const existing = state.matters.find((m: Matter) => m.id === d.id);
  if (d.editing && (!existing || computeBaseline(state, existing) !== d.baseline)) {
    return '原事项已变更或删除，请放弃旧草稿后重新编辑';
  }
  if (!d.editing && existing) return '该事项已保存，请返回首页查看';

  // 若正在按特定范围（仅这次 / 这次及以后 / 整个系列）编辑某个重复时间段实例
  if (d.editing && existing && d.isSeries && d.occurrenceStart !== undefined && d.editScope !== undefined &&
    d.types.includes(ModuleType.Deadline) && d.span === 'range') {
    const draftBlock: TimelineBlock = {
      id: existing.id,
      title: d.title.trim(),
      startAt: d.timestamp,
      endAt: d.endAt,
      note: d.types.includes(ModuleType.Note) ? d.note.trim() : '',
      tagId: d.types.includes(ModuleType.Tag) && d.tagId.trim() ? d.tagId.trim() : undefined,
      repeat: d.repeat !== TimelineRepeat.None ? d.repeat : undefined,
      reminderMinutes: d.reminderMinutes >= 0 ? d.reminderMinutes : undefined,
      attachments: d.types.includes(ModuleType.Note) && d.attachments.length > 0
        ? copyTimelineAttachments(d.attachments) : undefined
    };
    const scopeErr = applyRecurringMatterEdit(state, existing, draftBlock, d.editScope, d.occurrenceStart, d.dayCountMode);
    if (scopeErr) return scopeErr;
    const updated = state.matters.find((m: Matter) => m.id === d.id);
    if (updated) updated.lastEditorToken = d.token;
    return applyChecklistAndCounterOnMatter(state, updated ?? existing, d, ownerId);
  }

  const previousSnapshot = existing ? JSON.parse(JSON.stringify(existing)) as Matter : undefined;
  const matter = existing ?? createMatter({ title: d.title }, state.matters.length);
  if (!existing) {
    matter.id = d.id;
    state.matters.push(matter);
  }
  matter.lastEditorToken = d.token;
  matter.title = d.title.trim();
  matter.description = undefined;

  // Deduplicate active module types (merge legacy EventRecord -> Counter)
  const cleanTypes: ModuleType[] = [];
  for (const rawType of d.types) {
    const mapped = rawType === ModuleType.EventRecord ? ModuleType.Counter : rawType;
    if (mapped === ModuleType.Countdown || mapped === ModuleType.Progress) continue;
    if (!cleanTypes.includes(mapped)) cleanTypes.push(mapped);
  }

  const all = matter.enabledModules.concat(matter.disabledModules ?? []);
  const selected: ModuleInstance[] = [];
  const now = Date.now();

  for (const type of cleanTypes) {
    const module = all.find((m: ModuleInstance) => m.moduleType === type) ?? createModuleInstance(d.id, type);
    module.matterId = d.id;
    module.updatedAt = now;
    if (type === ModuleType.Deadline) {
      const date: DeadlineConfig = {
        timestamp: d.timestamp,
        endAt: d.span === 'range' ? d.endAt : undefined,
        span: d.span,
        dayCountMode: d.dayCountMode,
        hasTime: d.span === 'range' || d.span === 'point',
        reminderMinutes: d.reminderMinutes >= 0 ? d.reminderMinutes : undefined,
        repeat: d.repeat !== TimelineRepeat.None ? d.repeat : undefined
      };
      normalizeSeriesRangeOnSave(state, previousSnapshot, date, now);
      module.name = undefined;
      module.configJson = JSON.stringify(date);
    } else if (type === ModuleType.Tag) {
      const tagCfg: TagConfig = { tagId: d.tagId.trim() };
      matter.tagId = tagCfg.tagId || undefined;
      module.configJson = JSON.stringify(tagCfg);
    } else if (type === ModuleType.Counter) {
      const mode: ActiveCounterMode = d.step !== '1' && d.counterMode === 'tally' ? 'amount' : d.counterMode;
      const steps: number[] = mode === 'amount'
        ? [Number(d.step)].concat(d.step2.trim().length > 0 ? [Number(d.step2)] : [])
        : [1];
      const config: CounterConfig = {
        mode,
        unit: d.unit.trim() || (mode === 'tally' ? '次' : undefined),
        initialValue: mode === 'daily_once' ? 0 : Number(d.initial),
        fixedSteps: steps
      };
      module.name = undefined;
      module.configJson = JSON.stringify(config);
      // 迁移该事项名下旧的 eventRecords 到统一的 counterEntries
      const legacyRecords = state.eventRecords.filter((e: EventRecordEntry) => e.matterId === d.id);
      if (legacyRecords.length > 0) {
        for (const entry of legacyRecords) {
          state.counterEntries.push({
            id: entry.id,
            matterId: d.id,
            value: 1,
            timestamp: entry.timestamp,
            note: entry.note
          });
        }
        state.eventRecords = state.eventRecords.filter((e: EventRecordEntry) => e.matterId !== d.id);
      }
    } else if (type === ModuleType.Note) {
      const note: NoteConfig = {
        text: d.note.trim(),
        attachments: copyTimelineAttachments(d.attachments)
      };
      module.configJson = JSON.stringify(note);
    }
    selected.push(module);
  }

  if (!cleanTypes.includes(ModuleType.Tag)) {
    matter.tagId = undefined;
  }

  matter.enabledModules = selected;
  const disabled: ModuleInstance[] = [];
  for (const mod of all) {
    if (mod.moduleType === ModuleType.Countdown || mod.moduleType === ModuleType.Progress ||
      mod.moduleType === ModuleType.EventRecord) {
      continue;
    }
    if (!cleanTypes.includes(mod.moduleType) && !disabled.some((x: ModuleInstance) => x.moduleType === mod.moduleType)) {
      disabled.push(mod);
    }
  }
  matter.disabledModules = disabled;
  matter.updatedAt = now;

  return applyChecklistAndCounterOnMatter(state, matter, d, ownerId);
}

function applyChecklistAndCounterOnMatter(state: AppState, matter: Matter, d: EditorDraft, ownerId: string): string {
  const now = Date.now();
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
      state.checklistItems.push({
        id: item.id,
        matterId: d.id,
        title: item.title.trim(),
        completed: old?.completed ?? false,
        entryType: item.targetId ? 'matter_ref' : 'text',
        targetMatterId: item.targetId,
        orderIndex: order++,
        createdAt: old?.createdAt ?? now,
        updatedAt: now
      });
    }
  }
  if (ownerId) {
    if (!canLinkMatterInState(state, ownerId, d.id)) return '原列表已不可用或无法嵌套关联';
    state.checklistItems.push({
      id: createId('link'),
      matterId: ownerId,
      title: matter.title,
      completed: false,
      entryType: 'matter_ref',
      targetMatterId: d.id,
      orderIndex: state.checklistItems.filter((i: ChecklistItem) => i.matterId === ownerId).length,
      createdAt: now,
      updatedAt: now
    });
  }
  return '';
}
