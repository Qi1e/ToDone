import { TimelineBlock, TimelineRepeat } from '../contracts/TimelineService';
import { nextOccurrence, overriddenOccurrence, timelineDateNumber } from './TimelineRecurrence';

export interface TimelinePlannedReminder {
  key: string;
  blockId: string;
  occurrenceStart: number;
  startAt: number;
  fireAt: number;
  title: string;
}

export interface TimelineReminderPlan {
  entries: TimelinePlannedReminder[];
  hasMore: boolean;
}

function addReminder(candidates: TimelinePlannedReminder[], block: TimelineBlock, now: number, until: number): void {
  if (block.reminderMinutes === undefined) return;
  const fireAt = block.startAt - block.reminderMinutes * 60000;
  if (fireAt <= now || fireAt > until) return;
  const original = block.occurrenceOriginalStart ?? block.startAt;
  candidates.push({ key: block.id + ':' + original, blockId: block.id, occurrenceStart: original,
    startAt: block.startAt, fireAt: fireAt, title: block.title });
}

function compareReminders(a: TimelinePlannedReminder, b: TimelinePlannedReminder): number {
  return a.fireAt - b.fireAt || a.startAt - b.startAt || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0);
}

// 每组只找最近的 capacity+1 个常规实例，否则无限重复会让规划无法结束。
// 提前量可因单次编辑而不同；单次例外另按实际时段参与全局排序。
export function planTimelineReminders(blocks: TimelineBlock[], now: number, capacity: number,
  until: number = Infinity): TimelineReminderPlan {
  const candidates: TimelinePlannedReminder[] = [];
  if (!Number.isFinite(now) || !Number.isSafeInteger(capacity) || capacity < 0 || !(until > now)) {
    return { entries: [], hasMore: false };
  }
  for (const block of blocks) {
    if (block.repeat === undefined || block.repeat === TimelineRepeat.None) {
      addReminder(candidates, block, now, until);
      continue;
    }
    const omitted = new Set<number>(block.excludedDays ?? []);
    for (const edit of block.overrides ?? []) {
      omitted.add(timelineDateNumber(edit.originalStart));
      addReminder(candidates, overriddenOccurrence(block, edit), now, until);
    }
    if (block.reminderMinutes === undefined) continue;
    const lead = block.reminderMinutes * 60000;
    let day = Math.max(timelineDateNumber(now + lead), block.repeatFromDay ?? timelineDateNumber(block.startAt));
    const lastDay = Math.min(block.repeatUntilDay ?? Infinity,
      Number.isFinite(until) ? timelineDateNumber(until + lead) + 1 : Infinity);
    const countBeforeSeries = candidates.length;
    while (day < lastDay && candidates.length - countBeforeSeries <= capacity) {
      const occurrence = nextOccurrence(block, day, lastDay, omitted);
      if (!occurrence) break;
      addReminder(candidates, occurrence, now, until);
      day = timelineDateNumber(occurrence.startAt) + 1;
    }
  }
  candidates.sort(compareReminders);
  return { entries: candidates.slice(0, capacity), hasMore: candidates.length > capacity };
}
