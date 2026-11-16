import { copyTimelineMetadata, TimelineBlock, TimelineOverride, TimelineRepeat } from '../contracts/TimelineService';

// 只对日历日期编号，用当地午夜的毫秒差会在夏令时切换时多算或少算一天。
export function timelineDateNumber(stamp: number): number {
  const date = new Date(stamp);
  const utc = new Date(0);
  return utc.setUTCFullYear(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000;
}

function shiftLocalDate(stamp: number, days: number): number {
  const date = new Date(stamp);
  return date.setDate(date.getDate() + days);
}

function occurrence(block: TimelineBlock, days: number): TimelineBlock {
  const start = days === 0 ? block.startAt : shiftLocalDate(block.startAt, days);
  const end = days === 0 ? block.endAt : shiftLocalDate(block.endAt, days);
  // 缺失的当地钟点会向后归一化。若两个端点因此相遇，仍保留原来的实际时长。
  const view: TimelineBlock = { id: block.id, title: block.title, note: block.note,
    startAt: start, endAt: end > start ? end : start + (block.endAt - block.startAt) };
  if (block.tagId !== undefined) view.tagId = block.tagId;
  if (block.repeat !== undefined) view.repeat = block.repeat;
  copyTimelineMetadata(block, view);
  return view;
}

function matchesDay(repeat: TimelineRepeat, date: Date, anchor: Date): boolean {
  switch (repeat) {
    case TimelineRepeat.Weekdays: return date.getDay() >= 1 && date.getDay() <= 5;
    case TimelineRepeat.Weekly: return date.getDay() === anchor.getDay();
    case TimelineRepeat.Monthly: return date.getDate() === anchor.getDate();
    default: return repeat === TimelineRepeat.Daily;
  }
}

export function nextOccurrence(block: TimelineBlock, fromDay: number, untilDay: number, excluded: Set<number>): TimelineBlock | undefined {
  const repeat = block.repeat;
  if (repeat === undefined || repeat === TimelineRepeat.None) return occurrence(block, 0);
  const anchor = new Date(block.startAt);
  const anchorDay = timelineDateNumber(block.startAt);
  const date = new Date(block.startAt);
  date.setHours(12, 0, 0, 0);
  date.setDate(date.getDate() + Math.max(0, fromDay - anchorDay));
  for (let day = timelineDateNumber(date.getTime()); day < untilDay; day = timelineDateNumber(date.getTime())) {
    if (!excluded.has(day) && matchesDay(repeat, date, anchor)) return occurrence(block, day - anchorDay);
    date.setDate(date.getDate() + 1);
  }
  return undefined;
}

export function nominalOccurrence(block: TimelineBlock, originalStart: number): TimelineBlock | undefined {
  const day = timelineDateNumber(originalStart);
  const anchorDay = timelineDateNumber(block.startAt);
  if (day < Math.max(anchorDay, block.repeatFromDay ?? anchorDay) || day >= (block.repeatUntilDay ?? Infinity) ||
    block.excludedDays?.includes(day) || !block.repeat ||
    !matchesDay(block.repeat, new Date(originalStart), new Date(block.startAt))) return undefined;
  const item = occurrence(block, day - anchorDay);
  return item.startAt === originalStart ? item : undefined;
}

// v5、v6 仅保存例外对应实例的绝对时刻。换时区后，跨夏令时的同一
// 次重复可能由本地日历排在相邻钟点。只在读取时尝试恢复该关联。
export function restoreOccurrenceStart(series: TimelineBlock, originalStart: number): number | undefined {
  if (nominalOccurrence(series, originalStart)) return originalStart;
  const elapsed = originalStart - series.startAt;
  const days = Math.round(elapsed / 86400000);
  if (days <= 0) return undefined;
  const local = occurrence(series, days).startAt;
  const drift = Math.abs(local - originalStart);
  // 支持常见的一小时、半小时以及两小时夏令时变更。任意偏移的时间戳
  // 不能借此通过检查；候选仍须符合原重复频率、生效日、截止日及删除记录。
  if (drift !== 1800000 && drift !== 3600000 && drift !== 7200000) return undefined;
  return nominalOccurrence(series, local) ? local : undefined;
}

export function overriddenOccurrence(series: TimelineBlock, item: TimelineOverride): TimelineBlock {
  const view: TimelineBlock = { id: series.id, title: item.title, note: item.note, tagId: item.tagId, startAt: item.startAt,
    endAt: item.endAt, repeat: series.repeat, occurrenceOriginalStart: item.originalStart };
  copyTimelineMetadata(item, view);
  return view;
}

// 新启用重复时，保留原选日期的星期或日号，从设置日开始找第一项。
export function firstTimelineOccurrence(block: TimelineBlock, notBefore: number = block.startAt): TimelineBlock {
  const first = nextOccurrence(block, timelineDateNumber(notBefore), Infinity, new Set<number>());
  if (!first) throw new Error('首次日程超出可用日期范围');
  return first;
}

export function firstVisibleTimelineOccurrence(block: TimelineBlock): TimelineBlock | undefined {
  const omitted = new Set<number>(block.excludedDays ?? []);
  let earliest: TimelineBlock | undefined = undefined;
  for (const item of block.overrides ?? []) {
    omitted.add(timelineDateNumber(item.originalStart));
    if (!earliest || item.startAt < earliest.startAt) earliest = overriddenOccurrence(block, item);
  }
  const next = nextOccurrence(block, block.repeatFromDay ?? timelineDateNumber(block.startAt),
    block.repeatUntilDay ?? Infinity, omitted);
  return earliest && (!next || earliest.startAt < next.startAt) ? earliest : next;
}

// 只查看与窗口可能相交的开始日期，浏览多年后的月历也不必遍历中间的月份。
export function timelineOccurrences(blocks: TimelineBlock[], from: number, until: number): TimelineBlock[] {
  const result: TimelineBlock[] = [];
  if (!(from < until)) return result;
  const lastDay = timelineDateNumber(until - 1);
  for (const block of blocks) {
    const excluded = new Set<number>(block.excludedDays ?? []);
    for (const edit of block.overrides ?? []) {
      excluded.add(timelineDateNumber(edit.originalStart));
      if (edit.startAt < until && edit.endAt > from) result.push(overriddenOccurrence(block, edit));
    }
    if (block.startAt >= until || !(block.startAt < block.endAt)) continue;
    const repeat = block.repeat;
    if (repeat === undefined || repeat === TimelineRepeat.None) {
      if (block.endAt > from) result.push(occurrence(block, 0));
      continue;
    }
    const anchor = new Date(block.startAt);
    const anchorDay = timelineDateNumber(block.startAt);
    const span = timelineDateNumber(block.endAt) - anchorDay;
    const earliest = new Date(from);
    earliest.setHours(12, 0, 0, 0);
    // 包含横跨边界的实例，额外一天容纳夏令时对端点钟点的归一化。
    earliest.setDate(earliest.getDate() - span - 1);
    const firstDay = Math.max(anchorDay, timelineDateNumber(earliest.getTime()), block.repeatFromDay ?? anchorDay);
    const limit = Math.min(lastDay + 1, block.repeatUntilDay ?? Infinity);
    if (firstDay >= limit) continue;
    const date = new Date(block.startAt);
    date.setHours(12, 0, 0, 0);
    date.setDate(date.getDate() + firstDay - anchorDay);
    for (let day = timelineDateNumber(date.getTime()); day < limit; day = timelineDateNumber(date.getTime())) {
      if (!excluded.has(day) && matchesDay(repeat, date, anchor)) {
        const item = occurrence(block, day - anchorDay);
        if (item.startAt < until && item.endAt > from) result.push(item);
      }
      date.setDate(date.getDate() + 1);
    }
  }
  return result;
}
