import { TimelineRepeat, timelineRepeatLabel } from '../contracts/TimelineService';
import { DateMode, DayCountMode, DeadlineConfig, TimeSpanMode } from '../model/Types';

export function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

export function formatDate(timestamp: number): string {
  const date = new Date(timestamp);
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

export function formatClock(timestamp: number): string {
  const date = new Date(timestamp);
  return `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
}

export function formatDateTime(timestamp: number): string {
  return `${formatDate(timestamp)} ${formatClock(timestamp)}`;
}

export function parseDate(value: string): number | undefined {
  const trimmed = value.trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    return undefined;
  }
  const timestamp = new Date(`${trimmed}T00:00:00`).getTime();
  return Number.isNaN(timestamp) ? undefined : timestamp;
}

function calendarDay(timestamp: number): number {
  const date = new Date(timestamp);
  return Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000;
}

export function daysUntil(timestamp: number, now: number = Date.now()): number {
  return calendarDay(timestamp) - calendarDay(now);
}

export function effectiveSpan(config: DeadlineConfig): TimeSpanMode {
  if (config.span === 'all_day' || config.span === 'range' || config.span === 'point') {
    return config.span;
  }
  if (config.endAt !== undefined && config.endAt > config.timestamp) {
    return 'range';
  }
  if ((config.mode ?? 'deadline') === 'deadline' && config.hasTime) {
    return 'point';
  }
  return 'all_day';
}

export function effectiveDayCountMode(config: DeadlineConfig): DayCountMode {
  if (config.dayCountMode === 'none' || config.dayCountMode === 'countdown' || config.dayCountMode === 'elapsed') {
    return config.dayCountMode;
  }
  if (config.mode === 'elapsed') return 'elapsed';
  if (config.mode === 'countdown') return 'countdown';
  return config.span !== undefined ? 'none' : 'countdown';
}

export function dateModeLabel(mode: DateMode): string {
  if (mode === 'elapsed') return '正数日';
  return mode === 'countdown' ? '倒数日' : '截止时间';
}

export function timeConfigTitle(config?: DeadlineConfig): string {
  if (!config) return '时间';
  const span = effectiveSpan(config);
  const dayMode = effectiveDayCountMode(config);
  if (span === 'range') {
    return dayMode === 'countdown' ? '时间段 · 倒数' : dayMode === 'elapsed' ? '时间段 · 正数' : '时间段';
  }
  if (span === 'point') {
    return '截止时刻';
  }
  if (dayMode === 'elapsed') return '正数日';
  if (dayMode === 'countdown' && config.span === undefined && (config.mode ?? 'deadline') === 'deadline') {
    return '截止时间';
  }
  return dayMode === 'countdown' ? '倒数日' : '全天日期';
}

function dayCountSuffix(days: number, mode: DayCountMode): string {
  if (mode === 'elapsed') return `已过 ${-days} 天`;
  if (mode === 'countdown') {
    if (days === 0) return '就是今天';
    return days > 0 ? `还有 ${days} 天` : `已过去 ${-days} 天`;
  }
  return '';
}

export function formatRangeLabel(startAt: number, endAt: number): string {
  const sameDay = calendarDay(startAt) === calendarDay(endAt);
  if (sameDay) {
    return `${formatDate(startAt)} ${formatClock(startAt)}–${formatClock(endAt)}`;
  }
  return `${formatDateTime(startAt)} – ${formatDateTime(endAt)}`;
}

export function dateSummary(config: DeadlineConfig, now: number = Date.now()): string {
  const days = daysUntil(config.timestamp, now);
  // 完全兼容未携带 span 的旧版 DeadlineConfig 摘要语义
  if (config.span === undefined && config.endAt === undefined) {
    if (config.mode === 'elapsed') return `已过 ${-days} 天`;
    if (config.mode === 'countdown') {
      if (days === 0) return '就是今天';
      return days > 0 ? `还有 ${days} 天` : `已过去 ${-days} 天`;
    }
    const label = config.hasTime ? formatDateTime(config.timestamp) : formatDate(config.timestamp);
    const late = config.hasTime ? config.timestamp < now : days < 0;
    return `${label} 截止 · ${late ? '已逾期' : days === 0 ? '今天截止' : `剩余 ${days} 天`}`;
  }

  const span = effectiveSpan(config);
  const dayMode = effectiveDayCountMode(config);
  const repeatSuffix = config.repeat && config.repeat !== TimelineRepeat.None
    ? ` · ${timelineRepeatLabel(config.repeat)}` : '';

  if (span === 'range' && config.endAt !== undefined && config.endAt > config.timestamp) {
    const range = formatRangeLabel(config.timestamp, config.endAt);
    const countText = dayCountSuffix(days, dayMode);
    return range + (countText ? ` · ${countText}` : '') + repeatSuffix;
  }

  if (span === 'point') {
    const label = `${formatDateTime(config.timestamp)} 截止`;
    const late = config.timestamp < now;
    if (late) return `${label} · 已逾期${repeatSuffix}`;
    if (dayMode === 'countdown') {
      return `${label} · ${days === 0 ? '今天截止' : `剩余 ${days} 天`}${repeatSuffix}`;
    }
    if (dayMode === 'elapsed') {
      return `${label} · 已过 ${-days} 天${repeatSuffix}`;
    }
    return label + repeatSuffix;
  }

  // all_day
  if (dayMode === 'elapsed') return `已过 ${-days} 天${repeatSuffix}`;
  if (dayMode === 'countdown') {
    const base = days === 0 ? '就是今天' : days > 0 ? `还有 ${days} 天` : `已过去 ${-days} 天`;
    return base + repeatSuffix;
  }
  return `${formatDate(config.timestamp)} 全天${repeatSuffix}`;
}

export function isSameLocalDay(left: number, right: number): boolean {
  const a = new Date(left);
  const b = new Date(right);
  return a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate();
}

export function isToday(timestamp: number, now: number = Date.now()): boolean {
  return isSameLocalDay(timestamp, now);
}

