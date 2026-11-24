import {
  compareTimelineIds,
  copyTimelineAttachments,
  copyTimelineMetadata,
  TIMELINE_REMINDER_MINUTES,
  TimelineAttachment,
  TimelineBlock,
  TimelineDeleteScope,
  TimelineEditScope,
  TimelineOverride,
  TimelineRepeat,
  TimelineTag
} from '../contracts/TimelineService';
import { effectiveDayCountMode, effectiveSpan, isSameLocalDay } from '../common/DateFormat';
import { createId, createMatter, createModuleInstance, DEFAULT_MATTER_TAGS, stripTagEmoji } from '../model/Defaults';
import {
  AppState,
  DeadlineConfig,
  Matter,
  ModuleInstance,
  ModuleType,
  NoteConfig,
  TagConfig
} from '../model/Types';
import { localDayStart, timelineBlocksForDay } from './TimelineLayout';
import {
  firstTimelineOccurrence,
  firstVisibleTimelineOccurrence,
  nominalOccurrence,
  overriddenOccurrence,
  timelineDateNumber,
  timelineOccurrences
} from './TimelineRecurrence';
import { MatterDataError } from './MatterSnapshot';

function copyOverride(item: TimelineOverride): TimelineOverride {
  const edit: TimelineOverride = {
    originalStart: item.originalStart,
    startAt: item.startAt,
    endAt: item.endAt,
    title: item.title,
    note: item.note,
    tagId: item.tagId
  };
  copyTimelineMetadata(item, edit);
  return edit;
}

function readModuleJson<T>(matter: Matter, type: ModuleType): T | undefined {
  const mod = matter.enabledModules.find((m: ModuleInstance) => m.moduleType === type);
  if (!mod) return undefined;
  try {
    return JSON.parse(mod.configJson) as T;
  } catch (error) {
    return undefined;
  }
}

export function effectiveMatterNote(matter: Matter): NoteConfig {
  const raw = readModuleJson<NoteConfig>(matter, ModuleType.Note);
  const deadline = readModuleJson<DeadlineConfig>(matter, ModuleType.Deadline);
  const parts: string[] = [];
  const desc = matter.description?.trim() ?? '';
  const loc = deadline?.location?.trim() ?? '';
  const body = raw?.text?.trim() ?? '';
  if (desc.length > 0 && !body.includes(desc)) parts.push(desc);
  if (loc.length > 0 && !body.includes(loc)) parts.push(`地点：${loc}`);
  if (raw?.text && raw.text.length > 0) parts.push(raw.text);
  return {
    text: parts.join('\n'),
    attachments: copyTimelineAttachments(raw?.attachments)
  };
}

export function effectiveMatterTagId(state: AppState, matter: Matter): string | undefined {
  const tagModule = readModuleJson<TagConfig>(matter, ModuleType.Tag);
  const candidate = tagModule ? tagModule.tagId : (matter.tagId ?? '');
  if (!candidate) return undefined;
  const tags = state.tags ?? DEFAULT_MATTER_TAGS;
  return tags.some((t: TimelineTag) => t.id === candidate) ? candidate : undefined;
}

export function matterToTimelineBlock(state: AppState, matter: Matter): TimelineBlock | undefined {
  if (matter.archived) return undefined;
  const deadline = readModuleJson<DeadlineConfig>(matter, ModuleType.Deadline);
  if (!deadline || effectiveSpan(deadline) !== 'range') return undefined;
  if (deadline.endAt === undefined || !(deadline.endAt > deadline.timestamp)) return undefined;
  const note = effectiveMatterNote(matter);
  const tagId = effectiveMatterTagId(state, matter);
  const block: TimelineBlock = {
    id: matter.id,
    title: matter.title,
    startAt: deadline.timestamp,
    endAt: deadline.endAt,
    note: note.text
  };
  if (tagId) block.tagId = tagId;
  if (deadline.repeat && deadline.repeat !== TimelineRepeat.None) {
    block.repeat = deadline.repeat;
    if (deadline.repeatFromDay !== undefined) block.repeatFromDay = deadline.repeatFromDay;
    if (deadline.repeatUntilDay !== undefined) block.repeatUntilDay = deadline.repeatUntilDay;
    if (deadline.excludedDays && deadline.excludedDays.length > 0) {
      block.excludedDays = deadline.excludedDays.slice();
    }
    if (deadline.overrides && deadline.overrides.length > 0) {
      block.overrides = deadline.overrides.map(copyOverride);
    }
  }
  if (deadline.reminderMinutes !== undefined && TIMELINE_REMINDER_MINUTES.includes(deadline.reminderMinutes)) {
    block.reminderMinutes = deadline.reminderMinutes;
  }
  if (note.attachments && note.attachments.length > 0) {
    block.attachments = note.attachments;
  }
  return block;
}

export function stateTimelineBlocks(state: AppState): TimelineBlock[] {
  const result: TimelineBlock[] = [];
  for (const matter of state.matters) {
    const block = matterToTimelineBlock(state, matter);
    if (block) result.push(block);
  }
  return result.sort((a: TimelineBlock, b: TimelineBlock) =>
    a.startAt - b.startAt || a.endAt - b.endAt || compareTimelineIds(a.id, b.id));
}

export function stateReminderBlocks(state: AppState): TimelineBlock[] {
  const result: TimelineBlock[] = [];
  for (const matter of state.matters) {
    if (matter.archived) continue;
    const rangeBlock = matterToTimelineBlock(state, matter);
    if (rangeBlock) {
      result.push(rangeBlock);
      continue;
    }
    const deadline = readModuleJson<DeadlineConfig>(matter, ModuleType.Deadline);
    if (!deadline || deadline.reminderMinutes === undefined ||
      !TIMELINE_REMINDER_MINUTES.includes(deadline.reminderMinutes)) {
      continue;
    }
    const span = effectiveSpan(deadline);
    let fireBase = deadline.timestamp;
    if (span === 'all_day') {
      const morning = new Date(deadline.timestamp);
      morning.setHours(9, 0, 0, 0);
      fireBase = morning.getTime();
    }
    const pointBlock: TimelineBlock = {
      id: matter.id,
      title: matter.title,
      startAt: fireBase,
      endAt: fireBase + 60000,
      note: effectiveMatterNote(matter).text,
      reminderMinutes: deadline.reminderMinutes,
      repeat: deadline.repeat,
      repeatFromDay: deadline.repeatFromDay,
      repeatUntilDay: deadline.repeatUntilDay,
      excludedDays: deadline.excludedDays?.slice()
    };
    result.push(pointBlock);
  }
  return result;
}

export function isLightScheduleMatter(matter: Matter): boolean {
  const deadline = readModuleJson<DeadlineConfig>(matter, ModuleType.Deadline);
  if (!deadline || effectiveSpan(deadline) !== 'range') return false;
  if (effectiveDayCountMode(deadline) !== 'none') return false;
  const hasLongTermModule = matter.enabledModules.some((m: ModuleInstance) =>
    m.moduleType === ModuleType.Counter ||
    m.moduleType === ModuleType.EventRecord ||
    m.moduleType === ModuleType.Checklist);
  return !hasLongTermModule;
}

export function matterMatchesDay(state: AppState, matter: Matter, dayTimestamp: number): boolean {
  if (matter.archived) return false;
  const day = localDayStart(dayTimestamp);
  const nextDay = localDayStart(day, 1);
  const block = matterToTimelineBlock(state, matter);
  if (block) {
    return timelineOccurrences([block], day, nextDay).length > 0;
  }
  const deadline = readModuleJson<DeadlineConfig>(matter, ModuleType.Deadline);
  if (!deadline) return false;
  if (deadline.repeat && deadline.repeat !== TimelineRepeat.None) {
    const start = localDayStart(deadline.timestamp);
    const pseudo: TimelineBlock = {
      id: matter.id,
      title: matter.title,
      startAt: start + 9 * 3600000,
      endAt: start + 10 * 3600000,
      note: '',
      repeat: deadline.repeat,
      repeatFromDay: deadline.repeatFromDay,
      repeatUntilDay: deadline.repeatUntilDay,
      excludedDays: deadline.excludedDays
    };
    return timelineOccurrences([pseudo], day, nextDay).length > 0;
  }
  return isSameLocalDay(deadline.timestamp, day);
}

export function mattersForDayInState(state: AppState, dayTimestamp: number): Matter[] {
  const day = localDayStart(dayTimestamp);
  const dayBlocks = timelineBlocksForDay(day, stateTimelineBlocks(state));
  const blockMap = new Map<string, TimelineBlock>();
  for (const item of dayBlocks) {
    const prev = blockMap.get(item.id);
    if (!prev || item.startAt < prev.startAt) blockMap.set(item.id, item);
  }
  return state.matters
    .filter((m: Matter) => !m.archived && (blockMap.has(m.id) || matterMatchesDay(state, m, day)))
    .map((m: Matter): Matter => {
      const projected = blockMap.get(m.id);
      if (!projected || projected.title === m.title) return m;
      const copy = JSON.parse(JSON.stringify(m)) as Matter;
      copy.title = projected.title;
      return copy;
    })
    .sort((a: Matter, b: Matter) => {
      const aTime = blockMap.get(a.id)?.startAt;
      const bTime = blockMap.get(b.id)?.startAt;
      if (aTime !== undefined && bTime !== undefined && aTime !== bTime) return aTime - bTime;
      if (aTime !== undefined && bTime === undefined) return -1;
      if (aTime === undefined && bTime !== undefined) return 1;
      return a.orderIndex - b.orderIndex;
    });
}

export function dayOccurrenceStartForMatter(state: AppState, matterId: string, dayTimestamp: number): number | undefined {
  const day = localDayStart(dayTimestamp);
  const hit = timelineBlocksForDay(day, stateTimelineBlocks(state)).find((b: TimelineBlock) => b.id === matterId);
  if (!hit) return undefined;
  return hit.occurrenceOriginalStart ?? hit.startAt;
}

function nextMatterId(state: AppState, prefix: string): string {
  let candidate = prefix;
  let suffix = 0;
  while (state.matters.some((m: Matter) => m.id === candidate)) {
    suffix++;
    candidate = `${prefix}-${suffix}`;
  }
  return candidate;
}

function writeBlockBackToMatter(state: AppState, base: Matter | undefined, block: TimelineBlock,
  dayCountMode?: 'none' | 'countdown' | 'elapsed'): Matter {
  const now = Date.now();
  const matter: Matter = base ? JSON.parse(JSON.stringify(base)) as Matter : createMatter({
    title: block.title
  }, state.matters.length, block.id);
  matter.id = block.id;
  matter.title = block.title.trim();
  matter.description = undefined;
  matter.updatedAt = now;

  const existingDeadline = readModuleJson<DeadlineConfig>(matter, ModuleType.Deadline);
  const deadlineConfig: DeadlineConfig = {
    timestamp: block.startAt,
    endAt: block.endAt,
    span: 'range',
    dayCountMode: dayCountMode ?? (existingDeadline ? effectiveDayCountMode(existingDeadline) : 'none'),
    hasTime: true,
    reminderMinutes: block.reminderMinutes,
    repeat: block.repeat && block.repeat !== TimelineRepeat.None ? block.repeat : undefined,
    repeatFromDay: block.repeat && block.repeat !== TimelineRepeat.None ? block.repeatFromDay : undefined,
    repeatUntilDay: block.repeat && block.repeat !== TimelineRepeat.None ? block.repeatUntilDay : undefined,
    excludedDays: block.repeat && block.repeat !== TimelineRepeat.None ? block.excludedDays?.slice() : undefined,
    overrides: block.repeat && block.repeat !== TimelineRepeat.None ? block.overrides?.map(copyOverride) : undefined
  };

  const modules = matter.enabledModules.filter((m: ModuleInstance) =>
    m.moduleType !== ModuleType.Deadline &&
    m.moduleType !== ModuleType.Countdown &&
    m.moduleType !== ModuleType.Tag &&
    m.moduleType !== ModuleType.Note);

  const deadlineMod = matter.enabledModules.find((m: ModuleInstance) => m.moduleType === ModuleType.Deadline) ??
    createModuleInstance(matter.id, ModuleType.Deadline);
  deadlineMod.matterId = matter.id;
  deadlineMod.configJson = JSON.stringify(deadlineConfig);
  deadlineMod.updatedAt = now;
  const nextEnabled: ModuleInstance[] = [deadlineMod];

  if (block.tagId && block.tagId.trim().length > 0) {
    matter.tagId = block.tagId.trim();
    const tagMod = matter.enabledModules.find((m: ModuleInstance) => m.moduleType === ModuleType.Tag) ??
      createModuleInstance(matter.id, ModuleType.Tag);
    tagMod.matterId = matter.id;
    const tagCfg: TagConfig = { tagId: matter.tagId };
    tagMod.configJson = JSON.stringify(tagCfg);
    tagMod.updatedAt = now;
    nextEnabled.push(tagMod);
  } else {
    matter.tagId = undefined;
  }

  nextEnabled.push(...modules);

  const hasNote = block.note.trim().length > 0 || (block.attachments && block.attachments.length > 0);
  if (hasNote) {
    const noteMod = matter.enabledModules.find((m: ModuleInstance) => m.moduleType === ModuleType.Note) ??
      createModuleInstance(matter.id, ModuleType.Note);
    noteMod.matterId = matter.id;
    const noteCfg: NoteConfig = {
      text: block.note.trim(),
      attachments: copyTimelineAttachments(block.attachments)
    };
    noteMod.configJson = JSON.stringify(noteCfg);
    noteMod.updatedAt = now;
    nextEnabled.push(noteMod);
  }

  matter.enabledModules = nextEnabled;
  return matter;
}

function sameAttachment(a: TimelineAttachment, b: TimelineAttachment): boolean {
  return a.id === b.id && a.name === b.name && a.kind === b.kind && a.source === b.source;
}

function sameAttachments(a: TimelineAttachment[] = [], b: TimelineAttachment[] = []): boolean {
  return a.length === b.length && a.every((item: TimelineAttachment, i: number) => sameAttachment(item, b[i]));
}

function applyAttachmentChanges(target: TimelineAttachment[] = [], previous: TimelineAttachment[] = [],
  draft: TimelineAttachment[] = []): TimelineAttachment[] | undefined {
  if (sameAttachments(previous, draft)) return copyTimelineAttachments(target);
  if (sameAttachments(target, previous)) return copyTimelineAttachments(draft);
  const result = target.filter((item: TimelineAttachment) =>
    !previous.some((entry: TimelineAttachment) => entry.id === item.id) ||
    draft.some((entry: TimelineAttachment) => entry.id === item.id));
  for (const item of draft) {
    const old = previous.find((entry: TimelineAttachment) => entry.id === item.id);
    if (old && sameAttachment(old, item)) continue;
    const index = result.findIndex((entry: TimelineAttachment) => entry.id === item.id);
    if (index < 0) result.push(item);
    else result[index] = item;
  }
  return copyTimelineAttachments(result);
}

function copyBlockFields(block: TimelineBlock): TimelineBlock {
  const copy: TimelineBlock = {
    id: block.id,
    title: block.title,
    startAt: block.startAt,
    endAt: block.endAt,
    note: block.note
  };
  if (block.tagId !== undefined) copy.tagId = block.tagId;
  if (block.repeat !== undefined && block.repeat !== TimelineRepeat.None) copy.repeat = block.repeat;
  copyTimelineMetadata(block, copy);
  return copy;
}

function copyFullBlock(block: TimelineBlock): TimelineBlock {
  const copy = copyBlockFields(block);
  if (block.repeatFromDay !== undefined) copy.repeatFromDay = block.repeatFromDay;
  if (block.repeatUntilDay !== undefined) copy.repeatUntilDay = block.repeatUntilDay;
  if (block.excludedDays !== undefined) copy.excludedDays = block.excludedDays.slice();
  if (block.overrides !== undefined) copy.overrides = block.overrides.map(copyOverride);
  return copy;
}

function editDate(stamp: number, previous: number, next: number): number {
  if (previous === next) return stamp;
  const date = new Date(stamp);
  const time = new Date(next);
  date.setDate(date.getDate() + timelineDateNumber(next) - timelineDateNumber(previous));
  return date.setHours(time.getHours(), time.getMinutes(), time.getSeconds(), time.getMilliseconds());
}

function applyBlockChanges(target: TimelineBlock, previous: TimelineBlock, draft: TimelineBlock): TimelineBlock {
  const result = copyBlockFields(target);
  if (draft.title !== previous.title) result.title = draft.title;
  if (draft.note !== previous.note) result.note = draft.note;
  if (draft.tagId !== previous.tagId) result.tagId = draft.tagId;
  if (draft.repeat !== previous.repeat) result.repeat = draft.repeat;
  if (draft.reminderMinutes !== previous.reminderMinutes) result.reminderMinutes = draft.reminderMinutes;
  result.attachments = applyAttachmentChanges(target.attachments, previous.attachments, draft.attachments);
  result.startAt = editDate(target.startAt, previous.startAt, draft.startAt);
  result.endAt = editDate(target.endAt, previous.endAt, draft.endAt);
  return result;
}

function alignChangedFrequency(saved: TimelineBlock, draft: TimelineBlock): void {
  const first = new Date(saved.startAt);
  const anchor = new Date(draft.startAt);
  if (saved.repeat === TimelineRepeat.Weekly) {
    first.setDate(first.getDate() + (anchor.getDay() - first.getDay() + 7) % 7);
  } else if (saved.repeat === TimelineRepeat.Monthly) {
    while (first.getDate() !== anchor.getDate()) {
      first.setDate(first.getDate() + 1);
      if (!Number.isFinite(first.getTime())) throw new MatterDataError('invalid_deadline', '日期超出可用范围');
    }
  } else if (saved.repeat === TimelineRepeat.Weekdays) {
    if (first.getDay() === 6) first.setDate(first.getDate() + 2);
    else if (first.getDay() === 0) first.setDate(first.getDate() + 1);
  }
  const end = new Date(saved.endAt);
  end.setDate(end.getDate() + timelineDateNumber(first.getTime()) - timelineDateNumber(saved.startAt));
  saved.endAt = end.getTime();
  saved.startAt = first.getTime();
}

function asOverride(originalStart: number, draft: TimelineBlock): TimelineOverride {
  const result: TimelineOverride = {
    originalStart,
    title: draft.title,
    note: draft.note,
    tagId: draft.tagId,
    startAt: draft.startAt,
    endAt: draft.endAt
  };
  copyTimelineMetadata(draft, result);
  return result;
}

function seriesHeadPart(series: TimelineBlock, beforeDay: number): TimelineBlock | undefined {
  const head = copyFullBlock(series);
  head.repeatUntilDay = beforeDay;
  if (head.excludedDays) head.excludedDays = head.excludedDays.filter((d: number) => d < beforeDay);
  if (head.overrides) {
    head.overrides = head.overrides.filter((item: TimelineOverride) =>
      timelineDateNumber(item.originalStart) < beforeDay);
  }
  return firstVisibleTimelineOccurrence(head) ? head : undefined;
}

export function applyRecurringMatterEdit(
  state: AppState,
  matter: Matter,
  draftBlock: TimelineBlock,
  scope: TimelineEditScope,
  occurrenceStart: number,
  dayCountMode: 'none' | 'countdown' | 'elapsed'
): string {
  const series = matterToTimelineBlock(state, matter);
  if (!series || !series.repeat || series.repeat === TimelineRepeat.None) {
    return '重复日程已变更，请返回重试';
  }
  const original = nominalOccurrence(series, occurrenceStart);
  if (!original) return '这次日程已变更，请返回刷新';

  const draft = copyBlockFields(draftBlock);
  draft.title = draft.title.trim();
  if (!(draft.endAt > draft.startAt)) return '结束时间须晚于开始时间';

  const day = timelineDateNumber(occurrenceStart);
  const edit = series.overrides?.find((item: TimelineOverride) => item.originalStart === occurrenceStart);
  const clicked = edit ? overriddenOccurrence(series, edit) : original;

  if (scope === TimelineEditScope.One) {
    if (draft.repeat && draft.repeat !== series.repeat) {
      return '变更重复频率请选择这次及以后或整个系列';
    }
    const saved = copyFullBlock(series);
    const one = asOverride(occurrenceStart, draft);
    saved.overrides = (saved.overrides ?? []).filter((item: TimelineOverride) => item.originalStart !== occurrenceStart);
    const differs = draft.startAt !== original.startAt || draft.endAt !== original.endAt ||
      draft.title !== original.title || draft.note !== original.note || draft.tagId !== original.tagId ||
      draft.reminderMinutes !== original.reminderMinutes || !sameAttachments(draft.attachments, original.attachments);
    if (differs) saved.overrides.push(one);
    if (saved.overrides.length === 0) saved.overrides = undefined;
    const idx = state.matters.findIndex((m: Matter) => m.id === matter.id);
    state.matters[idx] = writeBlockBackToMatter(state, matter, saved);
    return '';
  }

  const following = scope === TimelineEditScope.Following;
  const head = following ? seriesHeadPart(series, day) : undefined;
  const target = following ? original : series;
  const saved = draft.repeat ? applyBlockChanges(target, clicked, draft) : copyBlockFields(draft);
  if (edit && draft.startAt !== clicked.startAt && saved.repeat) {
    saved.startAt = editDate(target.startAt, original.startAt, draft.startAt);
    saved.endAt = editDate(target.endAt, original.endAt, draft.endAt);
  }
  if (head) saved.id = nextMatterId(state, `${series.id}-from-${occurrenceStart}`);
  if (saved.repeat) {
    if (!following && saved.repeat !== series.repeat) alignChangedFrequency(saved, draft);
    const floor = series.repeatFromDay ?? timelineDateNumber(series.startAt);
    saved.repeatFromDay = following ? Math.max(floor, timelineDateNumber(saved.startAt)) : floor;
    saved.repeatUntilDay = series.repeatUntilDay;
    saved.excludedDays = series.excludedDays?.filter((d: number) => !following || d >= day);
    const align = edit && draft.startAt !== clicked.startAt ? original : clicked;
    const nextOverrides: TimelineOverride[] = [];
    for (const ov of series.overrides ?? []) {
      if (timelineDateNumber(ov.originalStart) < (following ? day : -Infinity)) continue;
      const expected = editDate(ov.originalStart, align.startAt, draft.startAt);
      const updated = applyBlockChanges(overriddenOccurrence(series, ov), clicked, draft);
      if (!(updated.endAt > updated.startAt)) return '个别日程的结束时间须晚于开始时间';
      if (nominalOccurrence(saved, expected)) {
        nextOverrides.push(asOverride(expected, updated));
      } else {
        const single = copyBlockFields(updated);
        single.repeat = undefined;
        single.id = nextMatterId(state, `${series.id}-single-${ov.originalStart}`);
        const detached = writeBlockBackToMatter(state, undefined, single, dayCountMode);
        detached.orderIndex = state.matters.length;
        state.matters.push(detached);
      }
    }
    if (nextOverrides.length > 0) saved.overrides = nextOverrides;
  }
  if (!firstVisibleTimelineOccurrence(saved)) return '该范围内没有有效的日程';

  const idx = state.matters.findIndex((m: Matter) => m.id === matter.id);
  if (head) {
    state.matters[idx] = writeBlockBackToMatter(state, matter, head);
    const tailMatter = writeBlockBackToMatter(state, matter, saved, dayCountMode);
    tailMatter.orderIndex = state.matters.length;
    state.matters.push(tailMatter);
  } else {
    state.matters[idx] = writeBlockBackToMatter(state, matter, saved, dayCountMode);
  }
  return '';
}

export function normalizeSeriesRangeOnSave(
  state: AppState,
  previousMatter: Matter | undefined,
  draftDeadline: DeadlineConfig,
  now: number = Date.now()
): void {
  if (!draftDeadline.repeat || draftDeadline.repeat === TimelineRepeat.None || effectiveSpan(draftDeadline) !== 'range' ||
    draftDeadline.endAt === undefined) {
    draftDeadline.repeat = undefined;
    draftDeadline.repeatFromDay = undefined;
    draftDeadline.repeatUntilDay = undefined;
    draftDeadline.excludedDays = undefined;
    draftDeadline.overrides = undefined;
    return;
  }
  const prevBlock = previousMatter ? matterToTimelineBlock(state, previousMatter) : undefined;
  const existingSeries = prevBlock && prevBlock.repeat !== undefined && prevBlock.repeat !== TimelineRepeat.None;
  const fromDay = existingSeries
    ? (prevBlock.repeatFromDay ?? timelineDateNumber(prevBlock.startAt))
    : timelineDateNumber(now);
  const candidate: TimelineBlock = {
    id: previousMatter?.id ?? 'draft',
    title: 'draft',
    startAt: draftDeadline.timestamp,
    endAt: draftDeadline.endAt,
    note: '',
    repeat: draftDeadline.repeat
  };
  const first = firstTimelineOccurrence(candidate, existingSeries ? draftDeadline.timestamp : now);
  draftDeadline.timestamp = first.startAt;
  draftDeadline.endAt = first.endAt;
  draftDeadline.repeatFromDay = fromDay;
  if (existingSeries && prevBlock) {
    draftDeadline.repeatUntilDay = prevBlock.repeatUntilDay;
    draftDeadline.excludedDays = prevBlock.excludedDays?.slice();
    draftDeadline.overrides = prevBlock.overrides?.map(copyOverride);
  } else if (prevBlock && timelineDateNumber(prevBlock.startAt) < fromDay && previousMatter) {
    // 过去的单次日程转为重复系列时保留历史那一次
    const single = copyBlockFields(prevBlock);
    single.repeat = undefined;
    single.id = nextMatterId(state, `${prevBlock.id}-single-${prevBlock.startAt}`);
    const historyMatter = writeBlockBackToMatter(state, undefined, single, 'none');
    historyMatter.orderIndex = state.matters.length;
    state.matters.push(historyMatter);
  }
}

export function deleteMatterScheduleScope(
  state: AppState,
  matterId: string,
  scope: TimelineDeleteScope,
  occurrenceStart?: number
): boolean {
  const index = state.matters.findIndex((m: Matter) => m.id === matterId);
  if (index < 0) return false;
  if (scope === TimelineDeleteScope.All) {
    return true; // 调用方执行整条事项删除
  }
  const matter = state.matters[index];
  const block = matterToTimelineBlock(state, matter);
  if (!block || !block.repeat || block.repeat === TimelineRepeat.None ||
    occurrenceStart === undefined || !Number.isSafeInteger(occurrenceStart)) {
    throw new MatterDataError('MAT-SCOPE', '请选择要删除的那次日程');
  }
  const day = timelineDateNumber(occurrenceStart);
  if ((block.repeatUntilDay !== undefined && day >= block.repeatUntilDay) ||
    (scope === TimelineDeleteScope.One && block.excludedDays?.includes(day))) {
    return false;
  }
  const template = copyBlockFields(block);
  template.repeatFromDay = block.repeatFromDay;
  if (!timelineOccurrences([template], occurrenceStart, occurrenceStart + 1)
    .some((item: TimelineBlock) => item.startAt === occurrenceStart)) {
    throw new MatterDataError('MAT-SCOPE', '这次日程已变更');
  }
  const saved = copyFullBlock(block);
  if (scope === TimelineDeleteScope.One) {
    saved.excludedDays = (saved.excludedDays ?? []).concat(day).sort((a: number, b: number) => a - b);
  } else {
    saved.repeatUntilDay = day;
    if (saved.excludedDays !== undefined) saved.excludedDays = saved.excludedDays.filter((d: number) => d < day);
  }
  if (saved.overrides) {
    saved.overrides = saved.overrides.filter((item: TimelineOverride) => {
      const originalDay = timelineDateNumber(item.originalStart);
      return scope === TimelineDeleteScope.One ? originalDay !== day : originalDay < day;
    });
    if (saved.overrides.length === 0) saved.overrides = undefined;
  }
  if (firstVisibleTimelineOccurrence(saved)) {
    state.matters[index] = writeBlockBackToMatter(state, matter, saved);
    return false;
  }
  return true;
}

export function importLegacyTimelineIntoState(
  state: AppState,
  blocks: TimelineBlock[],
  legacyTags: TimelineTag[]
): number {
  const mergedTags: TimelineTag[] = (state.tags && state.tags.length > 0
    ? state.tags.slice()
    : DEFAULT_MATTER_TAGS.map((t: TimelineTag): TimelineTag => ({ id: t.id, name: t.name, color: t.color })));
  const tagIdRemap = new Map<string, string>();

  for (const rawTag of legacyTags) {
    const cleanName = stripTagEmoji(rawTag.name) || rawTag.name.trim();
    const byId = mergedTags.find((t: TimelineTag) => t.id === rawTag.id);
    if (byId) {
      byId.name = cleanName;
      byId.color = rawTag.color.toUpperCase();
      tagIdRemap.set(rawTag.id, byId.id);
      continue;
    }
    const byName = mergedTags.find((t: TimelineTag) => t.name === cleanName);
    if (byName) {
      tagIdRemap.set(rawTag.id, byName.id);
      continue;
    }
    mergedTags.push({ id: rawTag.id, name: cleanName, color: rawTag.color.toUpperCase() });
    tagIdRemap.set(rawTag.id, rawTag.id);
  }
  state.tags = mergedTags;

  let importedCount = 0;
  for (const rawBlock of blocks) {
    if (state.matters.some((m: Matter) => m.id === rawBlock.id)) continue;
    const mapped = copyFullBlock(rawBlock);
    if (mapped.tagId) {
      mapped.tagId = tagIdRemap.get(mapped.tagId) ?? mapped.tagId;
    }
    if (mapped.overrides) {
      mapped.overrides = mapped.overrides.map((ov: TimelineOverride): TimelineOverride => {
        const nextOv = copyOverride(ov);
        if (nextOv.tagId) nextOv.tagId = tagIdRemap.get(nextOv.tagId) ?? nextOv.tagId;
        return nextOv;
      });
    }
    const created = writeBlockBackToMatter(state, undefined, mapped, 'none');
    created.orderIndex = state.matters.length;
    state.matters.push(created);
    importedCount++;
  }
  state.timelineImported = true;
  return importedCount;
}
