import { compareTimelineIds, TimelineBlock, TimelineTag } from '../contracts/TimelineService';
import { localDayStart } from './TimelineLayout';
import { timelineOccurrences } from './TimelineRecurrence';

export interface TimelineRingArc {
  color: string;
  // 从十二点顺时针计量，包含两个圆头占用的角度。
  start: number;
  sweep: number;
}

export interface TimelineRingDay {
  day: number;
  count: number;
  arcs: TimelineRingArc[];
}

interface RingCategory {
  id: string;
  color: string;
  duration: number;
}

export const RING_RADIUS: number = 13.5;
export const RING_STROKE: number = 3.5;
export const RING_DOT_DEGREES: number = 2 * Math.asin(RING_STROKE / (2 * RING_RADIUS)) * 180 / Math.PI;
const GAP: number = 7;
const MAX_CATEGORIES: number = 6;
export const DEFAULT_RING_COLOR: string = '#4B85C4';

export interface TimelineRingWeek {
  days: TimelineRingDay[];
  key: string;
}

// 周行在 Swiper 中会复用。日期或弧段变化时更新该行，其余周继续使用已有节点。
export function calendarRingWeeks(days: TimelineRingDay[]): TimelineRingWeek[] {
  const weeks: TimelineRingWeek[] = [];
  for (let i = 0; i < days.length; i += 7) {
    const row = days.slice(i, i + 7);
    weeks.push({ days: row, key: JSON.stringify(row) });
  }
  return weeks;
}

function ringArcs(count: number, grouped: Map<string, RingCategory>): TimelineRingArc[] {
  if (count === 0) return [];
  const categories: RingCategory[] = [];
  grouped.forEach((category: RingCategory) => categories.push(category));
  categories.sort((a: RingCategory, b: RingCategory) => b.duration - a.duration || compareTimelineIds(a.id, b.id));
  if (count === 1) return [{ color: categories[0].color, start: 0, sweep: 90 }];
  if (categories.length > MAX_CATEGORIES) {
    const rest = categories.splice(MAX_CATEGORIES - 1);
    categories.push({ id: '', color: '#9DA4AE',
      duration: rest.reduce((sum: number, item: RingCategory) => sum + item.duration, 0) });
  }

  // 给极小类别保留一个圆点；其余空间按持续时长分配，不挤掉段间留白。
  let remaining = 360 - GAP * categories.length;
  let duration = categories.reduce((sum: number, item: RingCategory) => sum + item.duration, 0);
  const widths: number[] = categories.map(() => 0);
  const byDuration = categories.map((category: RingCategory, index: number) => index)
    .sort((a: number, b: number) => categories[a].duration - categories[b].duration);
  for (const index of byDuration) {
    const share = remaining * categories[index].duration / duration;
    widths[index] = Math.max(RING_DOT_DEGREES, share);
    remaining -= widths[index];
    duration -= categories[index].duration;
  }
  let start = 0;
  return categories.map((category: RingCategory, index: number): TimelineRingArc => {
    const arc: TimelineRingArc = { color: category.color, start: start, sweep: widths[index] };
    start += widths[index] + GAP;
    return arc;
  });
}

// 仅展开与这一周/月相交的日程，按真实本地午夜切分跨日和夏令时日程。
export function timelineRingDays(first: number, dayCount: number, blocks: TimelineBlock[],
  tags: TimelineTag[]): TimelineRingDay[] {
  if (dayCount <= 0) return [];
  const start = localDayStart(first);
  return timelineRingsForOccurrences(start, dayCount, timelineOccurrences(blocks, start, localDayStart(start, dayCount)), tags);
}

export function timelineRingsForOccurrences(start: number, dayCount: number, occurrences: TimelineBlock[],
  tags: TimelineTag[]): TimelineRingDay[] {
  const days: TimelineRingDay[] = [];
  const limit = localDayStart(start, dayCount);
  const dayIndex = new Map<number, number>();
  const colors = new Map<string, string>();
  const groups: Map<string, RingCategory>[] = [];
  tags.forEach((tag: TimelineTag) => colors.set(tag.id, tag.color));
  for (let i = 0; i < dayCount; i++) {
    const day = localDayStart(start, i);
    days.push({ day: day, count: 0, arcs: [] });
    dayIndex.set(day, i);
    groups.push(new Map<string, RingCategory>());
  }
  for (const block of occurrences) {
    const from = Math.max(start, block.startAt);
    const until = Math.min(limit, block.endAt);
    const id = block.tagId && colors.has(block.tagId) ? block.tagId : '';
    const i = dayIndex.get(localDayStart(from));
    if (i === undefined) continue;
    for (let index = i; index < days.length && days[index].day < until; index++) {
      const next = index + 1 < days.length ? days[index + 1].day : limit;
      const elapsed = Math.min(until, next) - Math.max(from, days[index].day);
      const group = groups[index];
      const category = group.get(id);
      if (category) category.duration += elapsed;
      else group.set(id, { id: id, color: colors.get(id) ?? DEFAULT_RING_COLOR, duration: elapsed });
      days[index].count++;
    }
  }
  days.forEach((day: TimelineRingDay, i: number) => { day.arcs = ringArcs(day.count, groups[i]); });
  return days;
}
