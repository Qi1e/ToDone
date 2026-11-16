import { DateMode, DeadlineConfig } from '../model/Types';

export function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

export function formatDate(timestamp: number): string {
  const date = new Date(timestamp);
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

export function formatDateTime(timestamp: number): string {
  const date = new Date(timestamp);
  return `${formatDate(timestamp)} ${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
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

export function dateModeLabel(mode: DateMode): string {
  if (mode === 'elapsed') return '正数日';
  return mode === 'countdown' ? '倒数日' : '截止时间';
}

export function dateSummary(config: DeadlineConfig, now: number = Date.now()): string {
  const days = daysUntil(config.timestamp, now);
  if (config.mode === 'elapsed') return `已过 ${-days} 天`;
  if (config.mode === 'countdown') {
    if (days === 0) return '就是今天';
    return days > 0 ? `还有 ${days} 天` : `已过去 ${-days} 天`;
  }
  const label = config.hasTime ? formatDateTime(config.timestamp) : formatDate(config.timestamp);
  const late = config.hasTime ? config.timestamp < now : days < 0;
  return `${label} 截止 · ${late ? '已逾期' : days === 0 ? '今天截止' : `剩余 ${days} 天`}`;
}

export function isToday(timestamp: number): boolean {
  const date = new Date(timestamp);
  const today = new Date();
  return date.getFullYear() === today.getFullYear() &&
    date.getMonth() === today.getMonth() &&
    date.getDate() === today.getDate();
}

