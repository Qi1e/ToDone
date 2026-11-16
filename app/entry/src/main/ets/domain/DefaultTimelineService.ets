import { timelineReadCode } from './TimelineReadError';
import { compareTimelineIds, copyTimelineAttachments, copyTimelineMetadata, isTimelineAttachmentUrl, TIMELINE_REMINDER_MINUTES,
  TimelineAttachment, TimelineAttachmentKind, TimelineBlock, TimelineDeleteScope, TimelineEditScope,
  TimelineEventMetadata, TimelineOverride, TimelineRepeat, TimelineService, TimelineTag } from '../contracts/TimelineService';
import { firstTimelineOccurrence, firstVisibleTimelineOccurrence, nominalOccurrence, overriddenOccurrence, restoreOccurrenceStart, timelineDateNumber, timelineOccurrences } from './TimelineRecurrence';
import { StateStorage } from '../store/StateStorage';

interface TimelineSnapshot {
  version: number;
  blocks: TimelineBlock[];
  tags: TimelineTag[];
}

function initialTags(): TimelineTag[] {
  return [
    { id: 'study', name: '📚 学习', color: '#4384BB' },
    { id: 'project', name: '项目', color: '#9A7BC7' },
    { id: 'life', name: '生活', color: '#60AC87' },
    { id: 'urgent', name: '急事儿', color: '#DD6664' },
    { id: 'exercise', name: '运动', color: '#E0BD3D' }
  ];
}

function isValidTag(tag: TimelineTag): boolean {
  return tag !== null && typeof tag === 'object' && typeof tag.id === 'string' && tag.id.trim().length > 0 &&
    typeof tag.name === 'string' && tag.name.trim().length > 0 &&
    typeof tag.color === 'string' && /^#[0-9a-fA-F]{6}$/.test(tag.color);
}

function validDay(day: number): boolean {
  return Number.isSafeInteger(day) && Math.abs(day) <= 100000000;
}

function validRepeatLimits(block: TimelineBlock): boolean {
  if (block.repeatFromDay === undefined && block.repeatUntilDay === undefined && block.excludedDays === undefined) {
    return true;
  }
  if (!block.repeat || block.repeat === TimelineRepeat.None) return false;
  return (block.repeatFromDay === undefined || block.repeatUntilDay === undefined || block.repeatFromDay < block.repeatUntilDay) &&
    (block.repeatFromDay === undefined || validDay(block.repeatFromDay)) &&
    (block.repeatUntilDay === undefined || validDay(block.repeatUntilDay)) &&
    (block.excludedDays === undefined || (Array.isArray(block.excludedDays) &&
      block.excludedDays.every((day: number) => validDay(day)) &&
      new Set<number>(block.excludedDays).size === block.excludedDays.length));
}

function validMetadata(value: TimelineEventMetadata): boolean {
  if (value.reminderMinutes !== undefined && !TIMELINE_REMINDER_MINUTES.includes(value.reminderMinutes)) return false;
  if (value.attachments === undefined) return true;
  if (!Array.isArray(value.attachments)) return false;
  const ids = new Set<string>();
  for (const item of value.attachments) {
    if (!item || typeof item.id !== 'string' || !item.id.trim() || ids.has(item.id) ||
      typeof item.name !== 'string' || !item.name.trim() || typeof item.source !== 'string') return false;
    if (item.kind === TimelineAttachmentKind.Url) {
      if (!isTimelineAttachmentUrl(item.source)) return false;
    } else {
      if (item.kind !== TimelineAttachmentKind.File && item.kind !== TimelineAttachmentKind.Audio &&
        item.kind !== TimelineAttachmentKind.Image) return false;
      if (!/^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$/.test(item.source)) return false;
    }
    ids.add(item.id);
  }
  return true;
}

function isValidBlock(block: TimelineBlock): boolean {
  return block !== null && typeof block === 'object' &&
    typeof block.id === 'string' && block.id.trim().length > 0 &&
    typeof block.title === 'string' && block.title.trim().length > 0 &&
    typeof block.note === 'string' && validMetadata(block) &&
    (block.repeat === undefined || block.repeat === TimelineRepeat.None || block.repeat === TimelineRepeat.Daily ||
      block.repeat === TimelineRepeat.Weekdays || block.repeat === TimelineRepeat.Weekly ||
      block.repeat === TimelineRepeat.Monthly) &&
    (block.tagId === undefined || (typeof block.tagId === 'string' && block.tagId.trim().length > 0)) &&
    Number.isSafeInteger(block.startAt) && Number.isSafeInteger(block.endAt) &&
    Number.isFinite(new Date(block.startAt).getTime()) && Number.isFinite(new Date(block.endAt).getTime()) &&
    block.endAt > block.startAt;
}

function copyFields(block: TimelineBlock): TimelineBlock {
  const copy: TimelineBlock = {
    id: block.id, title: block.title, startAt: block.startAt, endAt: block.endAt, note: block.note
  };
  if (block.tagId !== undefined) copy.tagId = block.tagId;
  if (block.repeat !== undefined && block.repeat !== TimelineRepeat.None) copy.repeat = block.repeat;
  copyTimelineMetadata(block, copy);
  return copy;
}

function copyBlock(block: TimelineBlock): TimelineBlock {
  const copy = copyFields(block);
  if (block.repeatFromDay !== undefined) copy.repeatFromDay = block.repeatFromDay;
  if (block.repeatUntilDay !== undefined) copy.repeatUntilDay = block.repeatUntilDay;
  if (block.excludedDays !== undefined) copy.excludedDays = block.excludedDays.slice();
  if (block.overrides !== undefined) copy.overrides = block.overrides.map((item: TimelineOverride): TimelineOverride => {
    const edit: TimelineOverride = { originalStart: item.originalStart, startAt: item.startAt, endAt: item.endAt, title: item.title,
      note: item.note, tagId: item.tagId };
    copyTimelineMetadata(item, edit);
    return edit;
  });
  return copy;
}

function restoreOverrides(block: TimelineBlock, tagIds: Set<string>): boolean {
  if (block.overrides === undefined) return true;
  if (!Array.isArray(block.overrides) || !block.repeat || block.repeat === TimelineRepeat.None) return false;
  const used = new Set<number>();
  for (const edit of block.overrides) {
    if (!edit || !validMetadata(edit) || !Number.isSafeInteger(edit.originalStart) ||
      !isValidBlock(overriddenOccurrence(block, edit)) || (edit.tagId !== undefined && !tagIds.has(edit.tagId))) return false;
    const start = restoreOccurrenceStart(block, edit.originalStart);
    if (start === undefined || used.has(start)) return false;
    used.add(start);
    edit.originalStart = start;
  }
  return true;
}

function nextBlockId(state: TimelineSnapshot, prefix: string): string {
  let candidate = prefix;
  let suffix = 0;
  while (state.blocks.some((block: TimelineBlock) => block.id === candidate)) {
    suffix++;
    candidate = prefix + '-' + suffix;
  }
  return candidate;
}

function keepPastSingle(state: TimelineSnapshot, original: TimelineBlock): void {
  const history = copyFields(original);
  history.id = nextBlockId(state, original.id + '-single-' + original.startAt);
  state.blocks.push(history);
}

function editDate(stamp: number, previous: number, next: number): number {
  if (previous === next) return stamp;
  const date = new Date(stamp);
  const time = new Date(next);
  date.setDate(date.getDate() + timelineDateNumber(next) - timelineDateNumber(previous));
  return date.setHours(time.getHours(), time.getMinutes(), time.getSeconds(), time.getMilliseconds());
}

function sameAttachment(a: TimelineAttachment, b: TimelineAttachment): boolean {
  return a.id === b.id && a.name === b.name && a.kind === b.kind && a.source === b.source;
}

function sameAttachments(a: TimelineAttachment[] = [], b: TimelineAttachment[] = []): boolean {
  return a.length === b.length && a.every((item: TimelineAttachment, i: number) => sameAttachment(item, b[i]));
}

// 编辑整个系列时，只增删本次草稿中改过的附件；其他日期专有的资料仍保留。
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

// 对整个系列或后段应用此次实际修改的字段，避免把一次例外中的其他字段复制到每一天。
function applyChanges(target: TimelineBlock, previous: TimelineBlock, draft: TimelineBlock): TimelineBlock {
  const result = copyFields(target);
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
      if (!Number.isFinite(first.getTime())) throw new Error('日期超出可用范围');
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
  const result: TimelineOverride = { originalStart: originalStart, title: draft.title, note: draft.note, tagId: draft.tagId,
    startAt: draft.startAt, endAt: draft.endAt };
  copyTimelineMetadata(draft, result);
  return result;
}

function seriesPart(series: TimelineBlock, beforeDay: number): TimelineBlock | undefined {
  const head = copyBlock(series);
  head.repeatUntilDay = beforeDay;
  if (head.excludedDays) head.excludedDays = head.excludedDays.filter((d: number) => d < beforeDay);
  if (head.overrides) head.overrides = head.overrides.filter((item: TimelineOverride) =>
    timelineDateNumber(item.originalStart) < beforeDay);
  return firstVisibleTimelineOccurrence(head) ? head : undefined;
}

function updatedOverrides(state: TimelineSnapshot, series: TimelineBlock, target: TimelineBlock, previous: TimelineBlock,
  draft: TimelineBlock, fromDay: number, align: TimelineBlock = previous): TimelineOverride[] {
  const edits: TimelineOverride[] = [];
  for (const edit of series.overrides ?? []) {
    if (timelineDateNumber(edit.originalStart) < fromDay) continue;
    const expected = editDate(edit.originalStart, align.startAt, draft.startAt);
    const updated = applyChanges(overriddenOccurrence(series, edit), previous, draft);
    if (!isValidBlock(updated)) throw new Error('个别日程的结束时间须晚于开始时间');
    if (nominalOccurrence(target, expected)) {
      edits.push(asOverride(expected, updated));
    } else {
      // 改频率后某次不再属于新周期，保留用户写过的内容和实际时段。
      const single = copyFields(updated);
      single.repeat = undefined;
      single.id = nextBlockId(state, series.id + '-single-' + edit.originalStart);
      state.blocks.push(single);
    }
  }
  return edits;
}

function copyTag(tag: TimelineTag): TimelineTag {
  return { id: tag.id, name: tag.name.trim(), color: tag.color.toUpperCase() };
}

export class DefaultTimelineService implements TimelineService {
  private storage: StateStorage;
  private clock: () => number;
  private committed: TimelineSnapshot = { version: 6, blocks: [], tags: initialTags() };
  private pending: Promise<void> = Promise.resolve();

  constructor(storage: StateStorage, clock: () => number = Date.now) {
    this.clock = clock;
    this.storage = storage;
    let raw: string;
    try {
      raw = storage.read();
    } catch (error) {
      throw new Error(timelineReadCode(error as Error, 'READ'));
    }
    if (raw === '') return;
    if (typeof raw !== 'string') throw new Error('TL-FORMAT');
    let stored: TimelineSnapshot | TimelineBlock[];
    try {
      stored = JSON.parse(raw) as TimelineSnapshot | TimelineBlock[];
    } catch (error) {
      throw new Error('TL-JSON');
    }
    let snapshot: TimelineSnapshot;
    if (Array.isArray(stored)) {
      snapshot = { version: 2, blocks: stored as TimelineBlock[], tags: initialTags() };
    } else {
      snapshot = stored as TimelineSnapshot;
    }
    if (!snapshot || typeof snapshot !== 'object' ||
      !Array.isArray(snapshot.blocks) || !Array.isArray(snapshot.tags)) throw new Error('TL-FORMAT');
    if (![2, 3, 4, 5, 6].includes(snapshot.version)) {
      throw new Error(Number.isSafeInteger(snapshot.version) ? 'TL-VERSION:' + snapshot.version : 'TL-VERSION');
    }
    const tagIds = new Set<string>();
    const names = new Set<string>();
    for (const tag of snapshot.tags) {
      if (!isValidTag(tag) || tagIds.has(tag.id) || names.has(tag.name.trim())) {
        throw new Error('TL-TAG#' + (tagIds.size + 1));
      }
      tagIds.add(tag.id);
      names.add(tag.name.trim());
    }
    const ids = new Set<string>();
    for (const block of snapshot.blocks) {
      const position = '#' + (ids.size + 1);
      if (!isValidBlock(block)) throw new Error('TL-BLOCK' + position);
      if (!validRepeatLimits(block)) throw new Error('TL-RANGE' + position);
      if (!restoreOverrides(block, tagIds)) throw new Error('TL-OVERRIDE' + position);
      if (ids.has(block.id)) throw new Error('TL-DUPLICATE' + position);
      if (block.tagId !== undefined && !tagIds.has(block.tagId)) throw new Error('TL-TAGREF' + position);
      ids.add(block.id);
    }
    this.committed = snapshot;
  }

  list(): TimelineBlock[] {
    return this.committed.blocks.map(copyBlock).sort((a: TimelineBlock, b: TimelineBlock) =>
      a.startAt - b.startAt || a.endAt - b.endAt || compareTimelineIds(a.id, b.id));
  }

  listTags(): TimelineTag[] {
    const uses = new Map<string, number>();
    for (const block of this.committed.blocks) {
      if (block.tagId !== undefined) uses.set(block.tagId, (uses.get(block.tagId) ?? 0) + 1);
    }
    return this.committed.tags.map(copyTag).sort((a: TimelineTag, b: TimelineTag) =>
      (uses.get(b.id) ?? 0) - (uses.get(a.id) ?? 0));
  }

  async saveTag(tag: TimelineTag): Promise<void> {
    if (!isValidTag(tag)) throw new Error('请填写标签名称并选择颜色');
    const draft = copyTag(tag);
    await this.change((state: TimelineSnapshot): void => {
      if (state.tags.some((item: TimelineTag) => item.id !== draft.id && item.name.trim() === draft.name)) {
        throw new Error('这个标签名称已存在');
      }
      const index = state.tags.findIndex((item: TimelineTag) => item.id === draft.id);
      if (index < 0) state.tags.push(draft);
      else state.tags[index] = draft;
    });
  }

  async save(block: TimelineBlock, editing: boolean = false): Promise<void> {
    if (!isValidBlock(block)) throw new Error('请填写日程名称并确认起止时间');
    const draft = copyFields(block);
    draft.title = draft.title.trim();
    const now = this.clock();
    await this.change((state: TimelineSnapshot): void => {
      const index = state.blocks.findIndex((item: TimelineBlock) => item.id === draft.id);
      const previous = state.blocks[index];
      if (editing && !previous) throw new Error('这段日程已删除');
      if (draft.tagId !== undefined && !state.tags.some((tag: TimelineTag) => tag.id === draft.tagId)) {
        throw new Error('该日程标签不存在');
      }
      let saved = draft;
      if (draft.repeat !== undefined) {
        const existingSeries = previous && previous.repeat !== undefined && previous.repeat !== TimelineRepeat.None;
        // 从已提交的系列继承删除记录，避免过期表单和队列中的重试把删除的实例写回来。
        const from = existingSeries ? previous.repeatFromDay ?? timelineDateNumber(previous.startAt) : timelineDateNumber(now);
        saved = copyFields(firstTimelineOccurrence(draft, existingSeries ? draft.startAt : now));
        saved.repeatFromDay = from;
        if (existingSeries) {
          if (previous.repeatUntilDay !== undefined) saved.repeatUntilDay = previous.repeatUntilDay;
          if (previous.excludedDays !== undefined) saved.excludedDays = previous.excludedDays.slice();
          if (previous.overrides) saved.overrides = updatedOverrides(state, previous, saved, previous, draft, -Infinity);
        } else if (previous && timelineDateNumber(previous.startAt) < from) {
          keepPastSingle(state, previous);
        }
        if (!isValidBlock(saved) || !firstVisibleTimelineOccurrence(saved)) throw new Error('该范围内没有可保存的日程');
      }
      if (index < 0) state.blocks.push(saved);
      else state.blocks[index] = saved;
    });
  }

  async saveOccurrence(block: TimelineBlock, scope: TimelineEditScope, occurrenceStart: number): Promise<TimelineBlock> {
    if (!isValidBlock(block) || !Number.isSafeInteger(occurrenceStart)) throw new Error('请确认日程内容和时段');
    const draft = copyFields(block);
    draft.title = draft.title.trim();
    let focus = draft;
    await this.change((state: TimelineSnapshot): void => {
      const index = state.blocks.findIndex((item: TimelineBlock) => item.id === draft.id);
      const series = state.blocks[index];
      if (!series || !series.repeat || series.repeat === TimelineRepeat.None) throw new Error('重复日程已变更');
      const original = nominalOccurrence(series, occurrenceStart);
      if (!original) throw new Error('这次日程已变更');
      if (draft.tagId !== undefined && !state.tags.some((tag: TimelineTag) => tag.id === draft.tagId)) {
        throw new Error('该日程标签不存在');
      }
      const day = timelineDateNumber(occurrenceStart);
      const edit = series.overrides?.find((item: TimelineOverride) => item.originalStart === occurrenceStart);
      const clicked = edit ? overriddenOccurrence(series, edit) : original;
      if (scope === TimelineEditScope.One) {
        if (draft.repeat && draft.repeat !== series.repeat) throw new Error('变更重复频率请选择这次及以后或整组');
        const saved = copyBlock(series);
        const one = asOverride(occurrenceStart, draft);
        saved.overrides = (saved.overrides ?? []).filter((item: TimelineOverride) => item.originalStart !== occurrenceStart);
        const differs = draft.startAt !== original.startAt || draft.endAt !== original.endAt ||
          draft.title !== original.title || draft.note !== original.note || draft.tagId !== original.tagId ||
          draft.reminderMinutes !== original.reminderMinutes || !sameAttachments(draft.attachments, original.attachments);
        if (differs) saved.overrides.push(one);
        if (saved.overrides.length === 0) saved.overrides = undefined;
        state.blocks[index] = saved;
        focus = differs ? overriddenOccurrence(saved, one) : original;
        return;
      }
      if (scope !== TimelineEditScope.Following && scope !== TimelineEditScope.All) throw new Error('请选择修改范围');
      const following = scope === TimelineEditScope.Following;
      const head = following ? seriesPart(series, day) : undefined;
      // 整组改为单次时保留用户正在编辑的时段。修改后段时，前段与新段一起原子写入。
      const target = following ? original : series;
      const saved = draft.repeat ? applyChanges(target, clicked, draft) : copyFields(draft);
      // 从改过日期的例外再次调整起止时刻时，以编辑后的实际位置作为后段的新锚点。
      if (edit && draft.startAt !== clicked.startAt && saved.repeat) {
        saved.startAt = editDate(target.startAt, original.startAt, draft.startAt);
        saved.endAt = editDate(target.endAt, original.endAt, draft.endAt);
      }
      if (head) saved.id = nextBlockId(state, series.id + '-from-' + occurrenceStart);
      if (saved.repeat) {
        if (!following && saved.repeat !== series.repeat) alignChangedFrequency(saved, draft);
        const floor = series.repeatFromDay ?? timelineDateNumber(series.startAt);
        saved.repeatFromDay = following ? Math.max(floor, timelineDateNumber(saved.startAt)) : floor;
        saved.repeatUntilDay = series.repeatUntilDay;
        saved.excludedDays = series.excludedDays?.filter((d: number) => !following || d >= day);
        const align = edit && draft.startAt !== clicked.startAt ? original : clicked;
        const overrides = updatedOverrides(state, series, saved, clicked, draft, following ? day : -Infinity, align);
        if (overrides.length > 0) saved.overrides = overrides;
      }
      const first = firstVisibleTimelineOccurrence(saved);
      if (!isValidBlock(saved) || !validRepeatLimits(saved) || !first) throw new Error('该范围内没有有效的日程');
      if (head) {
        state.blocks[index] = head;
        state.blocks.push(saved);
      } else {
        state.blocks[index] = saved;
      }
      const expected = edit && draft.startAt !== clicked.startAt ? draft.startAt :
        editDate(occurrenceStart, clicked.startAt, draft.startAt);
      const updated = saved.overrides?.find((one: TimelineOverride) => one.originalStart === expected);
      focus = updated ? overriddenOccurrence(saved, updated) : nominalOccurrence(saved, expected) ?? first;
    });
    const view = copyFields(focus);
    if (focus.occurrenceOriginalStart !== undefined) view.occurrenceOriginalStart = focus.occurrenceOriginalStart;
    return view;
  }

  remove(id: string, scope: TimelineDeleteScope = TimelineDeleteScope.All, occurrenceStart?: number): Promise<void> {
    return this.change((state: TimelineSnapshot): void => {
      const index = state.blocks.findIndex((block: TimelineBlock) => block.id === id);
      if (index < 0) return;
      if (scope === TimelineDeleteScope.All) {
        state.blocks.splice(index, 1);
        return;
      }
      const block = state.blocks[index];
      if (!block.repeat || block.repeat === TimelineRepeat.None ||
        (scope !== TimelineDeleteScope.One && scope !== TimelineDeleteScope.Following) ||
        occurrenceStart === undefined || !Number.isSafeInteger(occurrenceStart)) throw new Error('请选择要删除的那次日程');
      const day = timelineDateNumber(occurrenceStart);
      if (!validDay(day)) throw new Error('日期无效');
      if ((block.repeatUntilDay !== undefined && day >= block.repeatUntilDay) ||
        (scope === TimelineDeleteScope.One && block.excludedDays?.includes(day))) return;
      // 撤销同日单次后仍可截断该日。先验证原始规则，避免误删改期后的另一场。
      const template = copyFields(block);
      template.repeatFromDay = block.repeatFromDay;
      if (!timelineOccurrences([template], occurrenceStart, occurrenceStart + 1)
        .some((item: TimelineBlock) => item.startAt === occurrenceStart)) throw new Error('这次日程已变更');
      const saved = copyBlock(block);
      if (scope === TimelineDeleteScope.One) {
        saved.excludedDays = (saved.excludedDays ?? []).concat(day).sort((a: number, b: number) => a - b);
      } else {
        saved.repeatUntilDay = day;
        if (saved.excludedDays !== undefined) saved.excludedDays = saved.excludedDays.filter((d: number) => d < day);
      }
      if (saved.overrides) saved.overrides = saved.overrides.filter((item: TimelineOverride) => {
        const originalDay = timelineDateNumber(item.originalStart);
        return scope === TimelineDeleteScope.One ? originalDay !== day : originalDay < day;
      });
      if (firstVisibleTimelineOccurrence(saved)) state.blocks[index] = saved;
      else state.blocks.splice(index, 1);
    });
  }

  private change(update: (state: TimelineSnapshot) => void): Promise<void> {
    const operation = this.pending.then(async (): Promise<void> => {
      const next: TimelineSnapshot = {
        version: 6, blocks: this.committed.blocks.slice(), tags: this.committed.tags.slice()
      };
      update(next);
      await this.storage.write(JSON.stringify(next));
      this.committed = next;
    });
    // 队列在一次写入失败后继续；调用方收到该次 operation 的真实结果。
    this.pending = operation.catch((): void => {});
    return operation;
  }
}
