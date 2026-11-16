import { isTimelineAttachmentUrl } from '../contracts/TimelineService';

export interface TimelineNotePart {
  start: number;
  text: string;
  href?: string;
}

function closingExcess(value: string, open: string, close: string): number {
  let depth = 0;
  for (const char of value) {
    if (char === open) depth++;
    if (char === close) depth--;
  }
  return -depth;
}

function trimSentenceEnd(value: string): string {
  let end = value.length;
  let parens = closingExcess(value, '(', ')');
  let brackets = closingExcess(value, '[', ']');
  while (end > 0) {
    const char = value[end - 1];
    if (char === ')' && parens > 0) parens--;
    else if (char === ']' && brackets > 0) brackets--;
    else if (!'.,;:!?'.includes(char)) break;
    end--;
  }
  return value.slice(0, end);
}

function linkLabel(token: string): string {
  const label = trimSentenceEnd(token);
  // 如「https://example.com请看」，ASCII 域名后紧跟的中文说明属于备注正文。
  // 含路径或中文域名时保留 Unicode 字符。
  const suffix = /^((?:https?:\/\/|www\.)(?:[a-z0-9-]+\.)+[a-z]+(?::\d+)?)([\u3400-\u9fff]+)$/i.exec(label);
  return suffix ? suffix[1] : label;
}

function destination(label: string): string | undefined {
  const bare = /^www\./i.test(label);
  const href = bare ? 'https://' + label : label;
  const parts = /^https?:\/\/([^/?#]+)(?:[/?#].*)?$/i.exec(href);
  if (!parts || !isTimelineAttachmentUrl(href)) return undefined;
  // 只接受完整主机及端口；带用户信息的地址保留为纯文字。
  const authority = /^(\[[a-f0-9:.]+\]|[a-z0-9\u00c0-\u02ff\u3400-\u9fff-]+(?:\.[a-z0-9\u00c0-\u02ff\u3400-\u9fff-]+)*)(?::\d{1,5})?$/i.exec(parts[1]);
  if (!authority || (bare && authority[1].split('.').length < 3)) return undefined;
  return href;
}

// 始终用原文的 UTF-16 偏移，供 ArkUI 富文本的选区和 Span 共用。
export function timelineNoteParts(note: string): TimelineNotePart[] {
  const parts: TimelineNotePart[] = [];
  const url = /(?:https?:\/\/|www\.)(?:(?![,;](?:https?:\/\/|www\.))[^\s\u0000-\u001f\u007f"'<>{}，。；！？、：《》「」【】（）“”‘’])+/gi;
  let consumed = 0;
  let match = url.exec(note);
  while (match !== null) {
    const start = match.index;
    const label = linkLabel(match[0]);
    const href = destination(label);
    const prev = start > 0 ? note[start - 1] : '';
    if (href && !/[a-z0-9_.@/]/i.test(prev)) {
      if (start > consumed) parts.push({ start: consumed, text: note.slice(consumed, start) });
      parts.push({ start: start, text: label, href: href });
      consumed = start + label.length;
    }
    match = url.exec(note);
  }
  if (consumed < note.length) parts.push({ start: consumed, text: note.slice(consumed) });
  return parts;
}
