// 内部 ID 仅用于打破排序平局，不依赖系统语言或 ICU 排序规则。
export function compareTimelineIds(left: string, right: string): number {
  if (left === right) return 0;
  return left < right ? -1 : 1;
}

export interface TimelineTag {
  id: string;
  name: string;
  color: string;
}

export enum TimelineAttachmentKind {
  File = 'file',
  Image = 'image',
  Audio = 'audio',
  Url = 'url'
}

export interface TimelineAttachment {
  id: string;
  name: string;
  kind: TimelineAttachmentKind;
  // 本地文件只记录沙箱内的文件名，网址记录完整的 HTTP(S) 地址。
  source: string;
}

export interface TimelineEventMetadata {
  reminderMinutes?: number;
  attachments?: TimelineAttachment[];
}

export const TIMELINE_REMINDER_MINUTES: number[] = [0, 5, 10, 15, 30, 60, 1440];

export function timelineReminderLabel(minutes?: number): string {
  if (minutes === undefined) return '不提醒';
  if (minutes === 0) return '开始时';
  if (minutes === 60) return '提前 1 小时';
  if (minutes === 1440) return '提前 1 天';
  return '提前 ' + minutes + ' 分钟';
}

export function isTimelineAttachmentUrl(value: string): boolean {
  if (typeof value !== 'string' || /[\s\\\u0000-\u001f\u007f]/.test(value)) return false;
  const parts = /^https?:\/\/([^/?#]+)(?:[/?#].*)?$/i.exec(value);
  if (!parts) return false;
  const hostPort = parts[1].slice(parts[1].lastIndexOf('@') + 1);
  const host = /^(?:\[[0-9a-f:.]+\]|[^:@\[\]]+)(?::(\d{1,5}))?$/i.exec(hostPort);
  return host !== null && (host[1] === undefined || Number(host[1]) <= 65535);
}

export function copyTimelineAttachments(items?: TimelineAttachment[]): TimelineAttachment[] | undefined {
  if (!items || items.length === 0) return undefined;
  return items.map((item: TimelineAttachment): TimelineAttachment => {
    return { id: item.id, kind: item.kind, name: item.name, source: item.source };
  });
}

export function copyTimelineMetadata(source: TimelineEventMetadata, target: TimelineEventMetadata): void {
  if (source.reminderMinutes !== undefined) target.reminderMinutes = source.reminderMinutes;
  if (source.attachments && source.attachments.length > 0) target.attachments = copyTimelineAttachments(source.attachments);
}

export enum TimelineRepeat {
  None = 'none',
  Daily = 'daily',
  Weekdays = 'weekdays',
  Weekly = 'weekly',
  Monthly = 'monthly'
}

export enum TimelineDeleteScope {
  One = 'one',
  Following = 'following',
  All = 'all'
}

export enum TimelineEditScope {
  One = 'one',
  Following = 'following',
  All = 'all'
}

export interface TimelineOverride extends TimelineEventMetadata {
  originalStart: number;
  startAt: number;
  endAt: number;
  title: string;
  note: string;
  tagId?: string;
}

export function timelineRepeatLabel(rule: TimelineRepeat): string {
  switch (rule) {
    case TimelineRepeat.Daily: return '每天';
    case TimelineRepeat.Weekdays: return '仅工作日';
    case TimelineRepeat.Weekly: return '每周';
    case TimelineRepeat.Monthly: return '每月';
    default: return '不重复';
  }
}

export interface TimelineBlock extends TimelineEventMetadata {
  id: string;
  title: string;
  startAt: number;
  endAt: number;
  note: string;
  tagId?: string;
  repeat?: TimelineRepeat;
  // 当地日历日期编号。截止日不含在系列中，修改钟点不影响已排除的日期。
  repeatFromDay?: number;
  repeatUntilDay?: number;
  excludedDays?: number[];
  overrides?: TimelineOverride[];
  // 仅投影出来的单次改期便签使用，用于找到它原来属于哪一次。
  occurrenceOriginalStart?: number;
}

export interface TimelineService {
  list(): TimelineBlock[];
  listTags(): TimelineTag[];
  saveTag(tag: TimelineTag): Promise<void>;
  // 新建、改期及失败重试使用同一 ID。Promise 在本地存储确认后完成。
  save(block: TimelineBlock, editing?: boolean): Promise<void>;
  saveOccurrence(draft: TimelineBlock, scope: TimelineEditScope, occurrenceStart: number): Promise<TimelineBlock>;
  remove(id: string, scope?: TimelineDeleteScope, occurrenceStart?: number): Promise<void>;
}
