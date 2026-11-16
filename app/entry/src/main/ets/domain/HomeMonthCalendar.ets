import { compareTimelineIds, TimelineBlock, TimelineTag } from '../contracts/TimelineService';
import { DEFAULT_RING_COLOR, TimelineRingDay, timelineRingsForOccurrences } from './TimelineDayRing';
import { calendarAnnotation } from './CalendarAnnotation';
import { localDayStart } from './TimelineLayout';
import { timelineDateNumber, timelineOccurrences } from './TimelineRecurrence';

export interface CalendarEntryStrip {
  key: string;
  title: string;
  fill: string;
  ink: string;
}

export const MAX_CALENDAR_STRIPS: number = 3;

export interface HomeCalendarDay {
  day: number;
  ring: TimelineRingDay;
  entries: TimelineBlock[];
  annotation: string;
  strips: CalendarEntryStrip[];
}

export interface HomeCalendarWeek {
  key: string;
  days: HomeCalendarDay[];
}

// 月份和数据变化时重建一次。行键只包含月历显示所需的信息，备注和附件不参与渲染。
const WEEK_KEY_FIELDS: string[] = ['day', 'ring', 'count', 'arcs', 'color', 'start', 'sweep', 'entries',
  'id', 'title', 'startAt', 'endAt', 'tagId', 'occurrenceOriginalStart', 'strips', 'key', 'fill'];

function linearChannel(value: number): number {
  const channel = value / 255;
  return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4);
}

function luminance(red: number, green: number, blue: number): number {
  return 0.2126 * linearChannel(red) + 0.7152 * linearChannel(green) + 0.0722 * linearChannel(blue);
}

// 保留标签原色。优先用同色系的浅字或深字，临界色退到纯白/纯黑以维持 4.5:1。
export function calendarStripInk(fill: string): string {
  const rgb = parseInt(fill.slice(1), 16);
  const red = (rgb >> 16) & 255;
  const green = (rgb >> 8) & 255;
  const blue = rgb & 255;
  const background = luminance(red, green, blue) + 0.05;
  const light = 1.05 / background >= background / 0.05;
  const limit = light ? 255 : 0;
  const r = Math.round(limit + (red - limit) * 0.12);
  const g = Math.round(limit + (green - limit) * 0.12);
  const b = Math.round(limit + (blue - limit) * 0.12);
  const foreground = luminance(r, g, b) + 0.05;
  if (Math.max(foreground, background) / Math.min(foreground, background) < 4.5) {
    return light ? '#FFFFFF' : '#000000';
  }
  return '#' + (r * 65536 + g * 256 + b).toString(16).padStart(6, '0').toUpperCase();
}

export function homeCalendarWeeks(month: number, blocks: TimelineBlock[], tags: TimelineTag[]): HomeCalendarWeek[] {
  const first = new Date(month);
  first.setDate(1);
  const leading = (first.getDay() + 6) % 7;
  const last = new Date(first.getTime());
  last.setMonth(first.getMonth() + 1, 0);
  const dayCount = 7 * Math.ceil((leading + last.getDate()) / 7);
  const start = localDayStart(first.getTime(), -leading);
  const until = localDayStart(start, dayCount);
  const occurrences = timelineOccurrences(blocks, start, until);
  const days = timelineRingsForOccurrences(start, dayCount, occurrences, tags).map((ring: TimelineRingDay): HomeCalendarDay => {
    return { day: ring.day, ring: ring, entries: [], annotation: calendarAnnotation(ring.day), strips: [] };
  });
  occurrences.sort((a: TimelineBlock, b: TimelineBlock) =>
    a.startAt - b.startAt || a.endAt - b.endAt || compareTimelineIds(a.id, b.id));

  const startDay = timelineDateNumber(start);
  const colors = new Map<string, string>();
  tags.forEach((tag: TimelineTag) => colors.set(tag.id, tag.color));
  for (const entry of occurrences) {
    const fill = colors.get(entry.tagId ?? '') ?? DEFAULT_RING_COLOR;
    const strip: CalendarEntryStrip = { key: entry.id + ':' + (entry.occurrenceOriginalStart ?? entry.startAt),
      title: entry.title, fill: fill, ink: calendarStripInk(fill) };
    const index = timelineDateNumber(Math.max(start, entry.startAt)) - startDay;
    for (let i = index; i < days.length && days[i].day < entry.endAt; i++) {
      days[i].entries.push(entry);
      if (days[i].strips.length < MAX_CALENDAR_STRIPS) days[i].strips.push(strip);
    }
  }

  const weeks: HomeCalendarWeek[] = [];
  for (let i = 0; i < days.length; i += 7) {
    const row = days.slice(i, i + 7);
    weeks.push({ key: JSON.stringify(row, WEEK_KEY_FIELDS), days: row });
  }
  return weeks;
}
