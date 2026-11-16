// 月历与双日网格共享工具栏下方的高度。即使在小屏上，每行日期圈也保留上下间距。
export const BROWSE_TITLE_HEIGHT: number = 32;
export const BROWSE_WEEKDAYS_HEIGHT: number = 18;
export const PREVIEW_HEADER_HEIGHT: number = 36;
export const PREVIEW_ROW_HEIGHT: number = 40;

export interface BrowsePanelSizes {
  rowHeight: number;
  closedHeight: number;
  openHeight: number;
  calendarLimit: number;
}

export function browsePanelSizes(contentHeight: number): BrowsePanelSizes {
  const header = BROWSE_TITLE_HEIGHT + BROWSE_WEEKDAYS_HEIGHT;
  const preview = PREVIEW_HEADER_HEIGHT + PREVIEW_ROW_HEIGHT;
  const target = Math.round(contentHeight * 0.55);
  const row = Math.min(46, Math.max(40, (target - header - preview) / 6));
  const closed = header + row;
  const open = Math.max(closed, target);
  return { rowHeight: row, closedHeight: closed, openHeight: open,
    calendarLimit: Math.min(header + 6 * row, Math.max(closed, open - preview)) };
}

export function browseDragProgress(start: number, offset: number, travel: number): number {
  if (travel <= 0) return start;
  return Math.min(1, Math.max(0, start + offset / travel));
}

// 面板的两个行程均按实际高度计算，拖到端点时这一帧就已呈现完整月格。
export function browseHeight(progress: number, sizes: BrowsePanelSizes, fullHeight: number): number {
  return sizes.closedHeight + Math.min(1, progress) * (sizes.openHeight - sizes.closedHeight) +
    Math.max(0, progress - 1) * (fullHeight - sizes.openHeight);
}

export function browseLevelProgress(start: number, level: number, offset: number,
  sizes: BrowsePanelSizes, fullHeight: number): number {
  if (offset === 0) return start;
  const height = browseHeight(start, sizes, fullHeight) + offset;
  const position = height <= sizes.openHeight
    ? browseDragProgress(1, height - sizes.openHeight, sizes.openHeight - sizes.closedHeight)
    : 1 + browseDragProgress(0, height - sizes.openHeight, fullHeight - sizes.openHeight);
  // 动画中再次起手时，起点也须落在可拖范围内。
  const lower = level === 2 ? Math.min(1, start) : 0;
  const upper = level === 0 ? Math.max(1, start) : 2;
  return Math.min(upper, Math.max(lower, position));
}

export function browseOpensFullCalendar(startedExpanded: boolean, offset: number, velocity: number): boolean {
  return startedExpanded && (offset >= 32 || (offset >= 10 && velocity >= 520));
}

export function browseReleaseTarget(progress: number, offset: number, velocity: number, travel: number): boolean {
  if (Math.abs(velocity) >= 520 && Math.abs(offset) >= 10) return velocity > 0;
  if (Math.abs(offset) >= Math.min(52, travel * 0.28) && travel > 0) return offset > 0;
  return progress >= 0.5;
}
