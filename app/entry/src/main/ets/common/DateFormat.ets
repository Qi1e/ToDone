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

export function daysUntil(timestamp: number): number {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const target = new Date(timestamp);
  target.setHours(0, 0, 0, 0);
  return Math.ceil((target.getTime() - start.getTime()) / (24 * 60 * 60 * 1000));
}

export function isToday(timestamp: number): boolean {
  const date = new Date(timestamp);
  const today = new Date();
  return date.getFullYear() === today.getFullYear() &&
    date.getMonth() === today.getMonth() &&
    date.getDate() === today.getDate();
}

