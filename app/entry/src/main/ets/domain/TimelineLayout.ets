import { compareTimelineIds, TimelineBlock } from '../contracts/TimelineService';
import { timelineOccurrences } from './TimelineRecurrence';

export interface TimelineSegment {
  block: TimelineBlock;
  startMinute: number;
  endMinute: number;
  lane: number;
  laneCount: number;
}

export interface TimelineDayLayout {
  day: number;
  nextDay: number;
  busyMinutes: number;
  segments: TimelineSegment[];
}

export function localDayStart(time: number, offsetDays: number = 0): number {
  const date = new Date(time);
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + offsetDays).getTime();
}

// 原生周分页只保留前一周、当前周和后一周。下标从 2 回到 0 时仍是向后翻一周。
export function weekPageOffset(page: number, activePage: number): number {
  const steps = (page - activePage + 3) % 3;
  return steps === 2 ? -1 : steps;
}

export function timelineDayHeading(stamp: number, today: number): string {
  const date = new Date(stamp);
  const weekday = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  let suffix = weekday[date.getDay()];
  if (localDayStart(stamp) === localDayStart(today)) {
    suffix = '今天';
  } else if (localDayStart(stamp) === localDayStart(today, 1)) {
    suffix = '明天';
  }
  return (date.getMonth() + 1) + '月' + date.getDate() + '日 · ' + suffix;
}

// 两列共用 24 个当地钟点。回拨时，两次出现的同一小时共享该小时的高度。
export function gridMinute(time: number): number {
  const date = new Date(time);
  const hour = date.getHours();
  const start = new Date(date.getFullYear(), date.getMonth(), date.getDate(), hour).getTime();
  const end = new Date(date.getFullYear(), date.getMonth(), date.getDate(), hour + 1).getTime();
  return (hour + (time - start) / (end - start)) * 60;
}

export function timelineBlocksForDay(time: number, blocks: TimelineBlock[]): TimelineBlock[] {
  const start = localDayStart(time);
  const end = localDayStart(start, 1);
  return timelineOccurrences(blocks, start, end)
    .sort((a: TimelineBlock, b: TimelineBlock) =>
      a.startAt - b.startAt || a.endAt - b.endAt || compareTimelineIds(a.id, b.id));
}

export function layoutTimelineDay(time: number, blocks: TimelineBlock[]): TimelineDayLayout {
  const day = localDayStart(time);
  const nextDay = localDayStart(time, 1);
  const segments: TimelineSegment[] = [];
  const ordered = timelineBlocksForDay(day, blocks);

  let groupStart = 0;
  let coveredUntil = day;
  let busyMs = 0;
  // 每个连通的重叠组单独确定列宽；相邻而不相交的两个时段可以复用一列。
  const laneEnds: number[] = [];
  const finishGroup = (): void => {
    for (let i = groupStart; i < segments.length; i++) {
      segments[i].laneCount = laneEnds.length;
    }
    groupStart = segments.length;
    laneEnds.length = 0;
  };

  ordered.forEach((block: TimelineBlock) => {
    const start = Math.max(day, block.startAt);
    const end = Math.min(nextDay, block.endAt);
    if (start >= coveredUntil) {
      finishGroup();
    }
    busyMs += Math.max(0, end - Math.max(start, coveredUntil));
    coveredUntil = Math.max(coveredUntil, end);

    let lane = laneEnds.findIndex((previousEnd: number) => previousEnd <= start);
    if (lane < 0) {
      lane = laneEnds.length;
    }
    laneEnds[lane] = end;
    segments.push({ block: block, startMinute: gridMinute(start),
      endMinute: end === nextDay ? 1440 : gridMinute(end), lane: lane, laneCount: 1 });
  });
  finishGroup();
  return { day: day, nextDay: nextDay, busyMinutes: busyMs / 60000, segments: segments };
}
