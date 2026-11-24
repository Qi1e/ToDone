import {
  TIMELINE_REMINDER_MINUTES,
  timelineReminderLabel,
  TimelineRepeat,
  timelineRepeatLabel
} from '../contracts/TimelineService';
import { daysUntil, formatClock, formatDate, isSameLocalDay } from '../common/DateFormat';
import { Colors, Radius, Space, TABULAR_NUMS, TypeSize, TypeWeight } from '../common/Theme';
import { DayCountMode, TimeSpanMode } from '../model/Types';

interface CalendarDayCell {
  key: string;
  year: number;
  month: number;
  day: number;
  inMonth: boolean;
  isToday: boolean;
  isSelected: boolean;
  disabled: boolean;
}

interface QuickDatePreset {
  label: string;
  daysOffset?: number;
  monthsOffset?: number;
}

interface QuickTimePreset {
  label: string;
  hour: number;
  minute: number;
}

enum ActiveDrawer {
  None = 'none',
  StartDay = 'start_day',
  EndDay = 'end_day',
  StartClock = 'start_clock',
  EndClock = 'end_clock'
}

enum ActivePopup {
  None = 'none',
  DayCount = 'day_count',
  Reminder = 'reminder',
  Repeat = 'repeat'
}

const WEEKDAY_HEADERS: string[] = ['一', '二', '三', '四', '五', '六', '日'];
const WEEKDAY_CN: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const FUTURE_PRESETS: QuickDatePreset[] = [
  { label: '今天', daysOffset: 0 },
  { label: '明天', daysOffset: 1 },
  { label: '3天后', daysOffset: 3 },
  { label: '1周后', daysOffset: 7 },
  { label: '1月后', monthsOffset: 1 }
];
const PAST_PRESETS: QuickDatePreset[] = [
  { label: '今天', daysOffset: 0 },
  { label: '昨天', daysOffset: -1 },
  { label: '3天前', daysOffset: -3 },
  { label: '1周前', daysOffset: -7 },
  { label: '1月前', monthsOffset: -1 }
];
const TIME_PRESETS: QuickTimePreset[] = [
  { label: '09:00', hour: 9, minute: 0 },
  { label: '12:00', hour: 12, minute: 0 },
  { label: '14:00', hour: 14, minute: 0 },
  { label: '18:00', hour: 18, minute: 0 },
  { label: '21:00', hour: 21, minute: 0 }
];
const REMINDER_ITEMS: number[] = [-1].concat(TIMELINE_REMINDER_MINUTES);
const REPEAT_ITEMS: TimelineRepeat[] = [
  TimelineRepeat.None,
  TimelineRepeat.Daily,
  TimelineRepeat.Weekdays,
  TimelineRepeat.Weekly,
  TimelineRepeat.Monthly
];
const MONTH_ROWS: number[][] = [
  [0, 1, 2, 3],
  [4, 5, 6, 7],
  [8, 9, 10, 11]
];
const TIME_WHEEL_HEIGHT: number = 152;
const TIME_SELECTION_HEIGHT: number = 36;

function addMonthsClamped(base: Date, deltaMonths: number): Date {
  const targetYear = base.getFullYear();
  const targetMonth = base.getMonth() + deltaMonths;
  const firstOfTarget = new Date(targetYear, targetMonth, 1);
  const lastDay = new Date(firstOfTarget.getFullYear(), firstOfTarget.getMonth() + 1, 0).getDate();
  const clampedDay = Math.min(base.getDate(), lastDay);
  return new Date(
    firstOfTarget.getFullYear(),
    firstOfTarget.getMonth(),
    clampedDay,
    base.getHours(),
    base.getMinutes(),
    0,
    0
  );
}

@Component
export struct MatterDateEditor {
  @Link @Watch('onTimestampPropChanged') startAt: number;
  @Link endAt: number;
  @Link span: TimeSpanMode;
  @Link dayCountMode: DayCountMode;
  @Link reminderMinutes: number;
  @Link repeat: TimelineRepeat;
  initialFocusClock: string = '';
  onChanged: () => void = () => {};

  @State private drawer: ActiveDrawer = ActiveDrawer.None;
  @State private popup: ActivePopup = ActivePopup.None;
  @State private pickingYearMonth: boolean = false;
  @State private viewYear: number = new Date().getFullYear();
  @State private viewMonth: number = new Date().getMonth();
  @State private yearPageStart: number = new Date().getFullYear() - 4;

  aboutToAppear(): void {
    this.syncCalendarView(this.startAt);
    if (this.initialFocusClock === 'start') {
      this.drawer = ActiveDrawer.StartClock;
    } else if (this.initialFocusClock === 'end') {
      this.drawer = ActiveDrawer.EndClock;
    }
  }

  private onTimestampPropChanged(): void {
    if (this.drawer !== ActiveDrawer.EndDay) {
      this.syncCalendarView(this.startAt);
    }
  }

  private activeCalendarStamp(): number {
    return this.drawer === ActiveDrawer.EndDay ? this.endAt : this.startAt;
  }

  private syncCalendarView(stamp: number): void {
    const target = new Date(stamp);
    this.viewYear = target.getFullYear();
    this.viewMonth = target.getMonth();
    this.yearPageStart = Math.max(1900, Math.min(2089, target.getFullYear() - 4));
  }

  private toggleDrawer(target: ActiveDrawer): void {
    this.popup = ActivePopup.None;
    if (this.drawer === target) {
      this.drawer = ActiveDrawer.None;
      return;
    }
    this.drawer = target;
    this.pickingYearMonth = false;
    if (target === ActiveDrawer.StartDay) {
      this.syncCalendarView(this.startAt);
    } else if (target === ActiveDrawer.EndDay) {
      this.syncCalendarView(this.endAt);
    }
  }

  private selectSpan(next: TimeSpanMode): void {
    if (this.span === next) return;
    this.span = next;
    this.drawer = ActiveDrawer.None;
    this.popup = ActivePopup.None;
    if (next === 'range') {
      const s = new Date(this.startAt);
      if (s.getHours() === 0 && s.getMinutes() === 0) {
        s.setHours(9, 0, 0, 0);
        this.startAt = s.getTime();
      }
      if (!(this.endAt > this.startAt)) {
        this.endAt = this.startAt + 3600000;
      }
    } else if (next === 'point') {
      const s = new Date(this.startAt);
      if (s.getHours() === 0 && s.getMinutes() === 0) {
        s.setHours(18, 0, 0, 0);
        this.startAt = s.getTime();
      }
    }
    this.onChanged();
  }

  private selectDayCount(next: DayCountMode): void {
    this.dayCountMode = next;
    this.popup = ActivePopup.None;
    if (next === 'elapsed') {
      this.repeat = TimelineRepeat.None;
      if (daysUntil(this.startAt) > 0) {
        const now = new Date();
        const cur = new Date(this.startAt);
        now.setHours(cur.getHours(), cur.getMinutes(), 0, 0);
        const length = Math.max(3600000, this.endAt - this.startAt);
        this.startAt = now.getTime();
        this.endAt = this.startAt + length;
        this.syncCalendarView(this.startAt);
      }
    }
    this.onChanged();
  }

  private presets(): QuickDatePreset[] {
    return this.dayCountMode === 'elapsed' ? PAST_PRESETS : FUTURE_PRESETS;
  }

  private presetTimestamp(preset: QuickDatePreset): number {
    const cur = new Date(this.startAt);
    const now = new Date();
    now.setHours(cur.getHours(), cur.getMinutes(), 0, 0);
    if (preset.monthsOffset !== undefined) {
      return addMonthsClamped(now, preset.monthsOffset).getTime();
    }
    const next = new Date(now.getTime());
    next.setDate(next.getDate() + (preset.daysOffset ?? 0));
    return next.getTime();
  }

  private isPresetSelected(preset: QuickDatePreset): boolean {
    return isSameLocalDay(this.startAt, this.presetTimestamp(preset));
  }

  private applyPreset(preset: QuickDatePreset): void {
    const nextStamp = this.presetTimestamp(preset);
    const duration = Math.max(3600000, this.endAt - this.startAt);
    this.startAt = nextStamp;
    this.endAt = nextStamp + duration;
    this.syncCalendarView(nextStamp);
    this.onChanged();
  }

  private isFutureDate(year: number, month: number, day: number): boolean {
    const now = new Date();
    const todayKey = now.getFullYear() * 10000 + now.getMonth() * 100 + now.getDate();
    const cellKey = year * 10000 + month * 100 + day;
    return cellKey > todayKey;
  }

  private isMonthDisabled(year: number, month: number): boolean {
    if (this.dayCountMode !== 'elapsed' || this.drawer === ActiveDrawer.EndDay) return false;
    const now = new Date();
    return year > now.getFullYear() || (year === now.getFullYear() && month > now.getMonth());
  }

  private isYearDisabled(year: number): boolean {
    if (this.dayCountMode !== 'elapsed' || this.drawer === ActiveDrawer.EndDay) return false;
    return year > new Date().getFullYear();
  }

  private canGoNextMonth(): boolean {
    if (this.viewYear > 2100 || (this.viewYear === 2100 && this.viewMonth >= 11)) return false;
    if (this.dayCountMode === 'elapsed' && this.drawer !== ActiveDrawer.EndDay) {
      const now = new Date();
      if (this.viewYear > now.getFullYear() ||
        (this.viewYear === now.getFullYear() && this.viewMonth >= now.getMonth())) {
        return false;
      }
    }
    return true;
  }

  private canGoPrevMonth(): boolean {
    return this.viewYear > 1900 || (this.viewYear === 1900 && this.viewMonth > 0);
  }

  private shiftMonth(delta: number): void {
    const next = new Date(this.viewYear, this.viewMonth + delta, 1);
    if (next.getFullYear() < 1900 || next.getFullYear() > 2100) return;
    if (this.isMonthDisabled(next.getFullYear(), next.getMonth())) return;
    this.viewYear = next.getFullYear();
    this.viewMonth = next.getMonth();
  }

  private selectCalendarCell(cell: CalendarDayCell): void {
    if (cell.disabled) return;
    if (this.drawer === ActiveDrawer.EndDay) {
      const base = new Date(this.endAt);
      const next = new Date(cell.year, cell.month, cell.day, base.getHours(), base.getMinutes(), 0, 0);
      this.endAt = next.getTime();
    } else {
      const base = new Date(this.startAt);
      const duration = this.endAt - this.startAt;
      const next = new Date(cell.year, cell.month, cell.day, base.getHours(), base.getMinutes(), 0, 0);
      this.startAt = next.getTime();
      if (duration > 0) this.endAt = this.startAt + duration;
    }
    this.viewYear = cell.year;
    this.viewMonth = cell.month;
    this.drawer = ActiveDrawer.None;
    this.onChanged();
  }

  private jumpToToday(): void {
    const now = new Date();
    this.selectCalendarCell({
      key: 'today',
      year: now.getFullYear(),
      month: now.getMonth(),
      day: now.getDate(),
      inMonth: true,
      isToday: true,
      isSelected: true,
      disabled: false
    });
    this.pickingYearMonth = false;
  }

  private calendarWeeks(): CalendarDayCell[][] {
    const first = new Date(this.viewYear, this.viewMonth, 1);
    const leading = (first.getDay() + 6) % 7;
    const daysInMonth = new Date(this.viewYear, this.viewMonth + 1, 0).getDate();
    const totalCells = Math.ceil((leading + daysInMonth) / 7) * 7;
    const todayStamp = Date.now();
    const selectedStamp = this.activeCalendarStamp();
    const weeks: CalendarDayCell[][] = [];
    let currentWeek: CalendarDayCell[] = [];

    for (let i = 0; i < totalCells; i++) {
      const cellDate = new Date(this.viewYear, this.viewMonth, 1 - leading + i);
      const y = cellDate.getFullYear();
      const m = cellDate.getMonth();
      const d = cellDate.getDate();
      const disabled = y < 1900 || y > 2100 ||
        (this.dayCountMode === 'elapsed' && this.drawer !== ActiveDrawer.EndDay && this.isFutureDate(y, m, d));
      currentWeek.push({
        key: `${y}-${m}-${d}`,
        year: y,
        month: m,
        day: d,
        inMonth: y === this.viewYear && m === this.viewMonth,
        isToday: isSameLocalDay(cellDate.getTime(), todayStamp),
        isSelected: isSameLocalDay(cellDate.getTime(), selectedStamp),
        disabled
      });
      if (currentWeek.length === 7) {
        weeks.push(currentWeek);
        currentWeek = [];
      }
    }
    return weeks;
  }

  private yearRows(): number[][] {
    const rows: number[][] = [];
    for (let r = 0; r < 3; r++) {
      const row: number[] = [];
      for (let c = 0; c < 4; c++) {
        row.push(this.yearPageStart + r * 4 + c);
      }
      rows.push(row);
    }
    return rows;
  }

  private setClockFor(isEnd: boolean, hour: number, minute: number): void {
    if (isEnd) {
      const next = new Date(this.endAt);
      next.setHours(hour, minute, 0, 0);
      this.endAt = next.getTime();
    } else {
      const length = this.endAt - this.startAt;
      const next = new Date(this.startAt);
      next.setHours(hour, minute, 0, 0);
      this.startAt = next.getTime();
      if (this.span === 'range' && length > 0) {
        this.endAt = this.startAt + length;
      }
    }
    this.onChanged();
  }

  private shortDayLabel(stamp: number): string {
    const d = new Date(stamp);
    const sameYear = d.getFullYear() === new Date().getFullYear();
    const prefix = sameYear ? '' : `${d.getFullYear()}年`;
    return `${prefix}${d.getMonth() + 1}月${d.getDate()}日 ${WEEKDAY_CN[d.getDay()]}`;
  }

  private fullDayLabel(stamp: number): string {
    const d = new Date(stamp);
    return `${formatDate(stamp)} · ${WEEKDAY_CN[d.getDay()]}`;
  }

  private durationHint(): string {
    const mins = Math.round((this.endAt - this.startAt) / 60000);
    if (mins <= 0) return '结束时间须晚于开始时间，跨日可点选结束日期';
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    return `共 ${h > 0 ? `${h} 小时` : ''}${h > 0 && m > 0 ? ' ' : ''}${m > 0 ? `${m} 分钟` : ''}`;
  }

  private repeatHint(): string {
    if (this.repeat === TimelineRepeat.Weekdays) return '按每周一至周五重复';
    const dom = new Date(this.startAt).getDate();
    if (this.repeat === TimelineRepeat.Monthly && dom >= 29) {
      return `每月 ${dom} 日，自动跳过没有该日期的月份`;
    }
    return '';
  }

  private dayCountChipLabel(): string {
    if (this.dayCountMode === 'countdown') return '倒数日';
    if (this.dayCountMode === 'elapsed') return '正数日';
    return '天数计算';
  }

  @Builder
  private SpanSegment() {
    Row({ space: 4 }) {
      this.SpanTab('all_day', '全天');
      this.SpanTab('range', '时间段');
      this.SpanTab('point', '截止时刻');
    }
    .width('100%')
    .padding(3)
    .backgroundColor(Colors.wash)
    .borderRadius(Radius.card);
  }

  @Builder
  private SpanTab(value: TimeSpanMode, label: string) {
    Button(label, { type: ButtonType.Normal })
      .layoutWeight(1)
      .height(34)
      .padding(0)
      .fontSize(TypeSize.bodySmall)
      .fontWeight(this.span === value ? TypeWeight.semibold : TypeWeight.regular)
      .fontColor(this.span === value ? Colors.ink : Colors.inkSoft)
      .backgroundColor(this.span === value ? Colors.card : Color.Transparent)
      .borderRadius(Radius.chip)
      .border({ width: this.span === value ? 1 : 0, color: Colors.hairline })
      .onClick(() => this.selectSpan(value));
  }

  @Builder
  private SingleDateRow() {
    Row({ space: Space.xs }) {
      Button({ type: ButtonType.Normal }) {
        Row() {
          Text(this.fullDayLabel(this.startAt))
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink)
            .fontFeature(TABULAR_NUMS);
          Blank();
          Text(this.drawer === ActiveDrawer.StartDay ? '▴' : '▾')
            .fontSize(TypeSize.meta)
            .fontColor(Colors.inkMuted);
        }
        .width('100%')
        .padding({ left: Space.md, right: Space.md });
      }
      .layoutWeight(1)
      .constraintSize({ minHeight: 42 })
      .backgroundColor(this.drawer === ActiveDrawer.StartDay ? Colors.card : Colors.wash)
      .borderRadius(Radius.card)
      .border({ width: this.drawer === ActiveDrawer.StartDay ? 1 : 0, color: Colors.line })
      .onClick(() => this.toggleDrawer(ActiveDrawer.StartDay));

      if (this.span === 'point') {
        Button(formatClock(this.startAt), { type: ButtonType.Normal })
          .constraintSize({ minHeight: 42 })
          .padding({ left: Space.md, right: Space.md })
          .fontSize(TypeSize.title)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink)
          .fontFeature(TABULAR_NUMS)
          .backgroundColor(this.drawer === ActiveDrawer.StartClock ? Colors.card : Colors.wash)
          .borderRadius(Radius.card)
          .border({ width: this.drawer === ActiveDrawer.StartClock ? 1 : 0, color: Colors.line })
          .onClick(() => this.toggleDrawer(ActiveDrawer.StartClock));
      }
    }
    .width('100%');

    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.presets(), (preset: QuickDatePreset) => {
        Button(preset.label)
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 32 })
          .fontSize(TypeSize.meta)
          .fontWeight(this.isPresetSelected(preset) ? TypeWeight.semibold : TypeWeight.regular)
          .fontColor(this.isPresetSelected(preset) ? Colors.bg : Colors.inkSoft)
          .backgroundColor(this.isPresetSelected(preset) ? Colors.ink : Colors.wash)
          .borderRadius(Radius.chip)
          .padding({ left: Space.sm, right: Space.sm })
          .margin({ right: Space.xs, bottom: Space.xs })
          .onClick(() => this.applyPreset(preset));
      }, (preset: QuickDatePreset) => `${this.dayCountMode}_${preset.label}`);
    }
    .width('100%');
  }

  @Builder
  private RangeRows() {
    Column({ space: 2 }) {
      this.RangeEndpointRow('开始', this.startAt, ActiveDrawer.StartDay, ActiveDrawer.StartClock);
      this.RangeEndpointRow('结束', this.endAt, ActiveDrawer.EndDay, ActiveDrawer.EndClock);
      Text(this.durationHint())
        .width('100%')
        .textAlign(TextAlign.End)
        .fontSize(TypeSize.meta)
        .fontWeight(this.endAt > this.startAt ? TypeWeight.regular : TypeWeight.semibold)
        .fontColor(this.endAt > this.startAt ? Colors.inkMuted : Colors.red)
        .fontFeature(TABULAR_NUMS);
    }
    .width('100%');
  }

  @Builder
  private RangeEndpointRow(label: string, stamp: number, dayDrawer: ActiveDrawer, clockDrawer: ActiveDrawer) {
    Row({ space: Space.xs }) {
      Text(label)
        .fontSize(TypeSize.bodySmall)
        .fontColor(Colors.inkSoft);
      Blank();
      Button(this.shortDayLabel(stamp), { type: ButtonType.Normal })
        .height(40)
        .padding({ left: Space.sm, right: Space.sm })
        .fontSize(TypeSize.bodySmall)
        .fontColor(this.drawer === dayDrawer ? Colors.ink : Colors.inkSoft)
        .fontWeight(this.drawer === dayDrawer ? TypeWeight.semibold : TypeWeight.regular)
        .backgroundColor(this.drawer === dayDrawer ? Colors.wash : Color.Transparent)
        .borderRadius(Radius.card)
        .fontFeature(TABULAR_NUMS)
        .onClick(() => this.toggleDrawer(dayDrawer));
      Button(formatClock(stamp), { type: ButtonType.Normal })
        .height(40)
        .padding({ left: Space.sm, right: Space.sm })
        .fontSize(19)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.ink)
        .backgroundColor(this.drawer === clockDrawer ? Colors.wash : Color.Transparent)
        .borderRadius(Radius.card)
        .fontFeature(TABULAR_NUMS)
        .onClick(() => this.toggleDrawer(clockDrawer));
    }
    .width('100%');
  }

  @Builder
  private CalendarPanel() {
    Column({ space: Space.xs }) {
      Row({ space: Space.xs }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: Space.xs }) {
            Text(`${this.viewYear}年 ${this.viewMonth + 1}月`)
              .fontSize(TypeSize.body)
              .fontWeight(TypeWeight.semibold)
              .fontColor(Colors.ink)
              .fontFeature(TABULAR_NUMS);
            Text(this.pickingYearMonth ? '▴' : '▾')
              .fontSize(TypeSize.meta)
              .fontColor(Colors.inkMuted);
          }
          .alignItems(VerticalAlign.Center);
        }
        .constraintSize({ minHeight: 36 })
        .padding({ left: Space.xs, right: Space.sm })
        .backgroundColor(this.pickingYearMonth ? Colors.wash : Color.Transparent)
        .borderRadius(Radius.card)
        .onClick(() => {
          this.pickingYearMonth = !this.pickingYearMonth;
          if (this.pickingYearMonth) {
            this.yearPageStart = Math.max(1900, Math.min(2089, this.viewYear - 4));
          }
        });

        Blank();

        Button('今天')
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 36 })
          .fontSize(TypeSize.bodySmall)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.inkSoft)
          .backgroundColor(Color.Transparent)
          .borderRadius(Radius.card)
          .padding({ left: Space.sm, right: Space.sm })
          .onClick(() => this.jumpToToday());

        if (!this.pickingYearMonth) {
          Button('‹')
            .type(ButtonType.Normal)
            .width(36)
            .height(36)
            .padding(0)
            .fontSize(18)
            .fontColor(Colors.ink)
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .enabled(this.canGoPrevMonth())
            .opacity(this.canGoPrevMonth() ? 1 : 0.35)
            .onClick(() => this.shiftMonth(-1));
          Button('›')
            .type(ButtonType.Normal)
            .width(36)
            .height(36)
            .padding(0)
            .fontSize(18)
            .fontColor(Colors.ink)
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .enabled(this.canGoNextMonth())
            .opacity(this.canGoNextMonth() ? 1 : 0.35)
            .onClick(() => this.shiftMonth(1));
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      if (this.pickingYearMonth) {
        this.YearMonthGrid();
      } else {
        this.MonthDaysGrid();
      }
    }
    .width('100%')
    .padding(Space.sm)
    .backgroundColor(Colors.bg)
    .borderRadius(Radius.card)
    .border({ width: 1, color: Colors.hairline });
  }

  @Builder
  private MonthDaysGrid() {
    Row() {
      ForEach(WEEKDAY_HEADERS, (name: string) => {
        Text(name)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontSize(TypeSize.meta)
          .fontColor(Colors.inkMuted);
      }, (name: string) => name);
    }
    .width('100%')
    .padding({ top: 2, bottom: 2 });

    Column({ space: 2 }) {
      ForEach(this.calendarWeeks(), (week: CalendarDayCell[], rowIndex: number) => {
        Row() {
          ForEach(week, (cell: CalendarDayCell) => {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 2 }) {
                Text(`${cell.day}`)
                  .fontSize(TypeSize.bodySmall)
                  .fontWeight(cell.isSelected || cell.isToday ? TypeWeight.semibold : TypeWeight.regular)
                  .fontColor(cell.isSelected ? Colors.bg : cell.inMonth ? Colors.ink : Colors.inkMuted)
                  .fontFeature(TABULAR_NUMS);
                Column()
                  .width(10)
                  .height(2)
                  .borderRadius(1)
                  .backgroundColor(cell.isToday ? (cell.isSelected ? Colors.bg : Colors.red) : Color.Transparent);
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center);
            }
            .layoutWeight(1)
            .height(36)
            .padding(0)
            .backgroundColor(cell.isSelected ? Colors.ink : cell.isToday ? Colors.wash : Color.Transparent)
            .borderRadius(Radius.card)
            .enabled(!cell.disabled)
            .opacity(cell.disabled ? 0.25 : cell.inMonth ? 1 : 0.45)
            .onClick(() => this.selectCalendarCell(cell));
          }, (cell: CalendarDayCell) => `${cell.key}_${cell.isSelected}_${cell.disabled}`);
        }
        .width('100%');
      }, (week: CalendarDayCell[], rowIndex: number) => `${this.viewYear}-${this.viewMonth}-r${rowIndex}-${week[0]?.key}`);
    }
    .width('100%');
  }

  @Builder
  private YearMonthGrid() {
    Column({ space: Space.xs }) {
      Row() {
        Text('年份').fontSize(TypeSize.meta).fontColor(Colors.inkMuted);
        Blank();
        Button('‹')
          .type(ButtonType.Normal)
          .width(32).height(32).padding(0).fontSize(16).fontColor(Colors.ink)
          .backgroundColor(Color.Transparent).borderRadius(Radius.card)
          .enabled(this.yearPageStart > 1900)
          .onClick(() => { this.yearPageStart = Math.max(1900, this.yearPageStart - 12); });
        Text(`${this.yearPageStart}–${this.yearPageStart + 11}`)
          .fontSize(TypeSize.meta).fontColor(Colors.inkSoft).fontFeature(TABULAR_NUMS);
        Button('›')
          .type(ButtonType.Normal)
          .width(32).height(32).padding(0).fontSize(16).fontColor(Colors.ink)
          .backgroundColor(Color.Transparent).borderRadius(Radius.card)
          .enabled(this.yearPageStart + 12 <= 2100 && (!this.isYearDisabled(this.yearPageStart + 12)))
          .onClick(() => { this.yearPageStart = Math.min(2089, this.yearPageStart + 12); });
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      ForEach(this.yearRows(), (row: number[], rIdx: number) => {
        Row({ space: Space.xs }) {
          ForEach(row, (year: number) => {
            Button(`${year}`)
              .type(ButtonType.Normal).layoutWeight(1).height(32).padding(0)
              .fontSize(TypeSize.meta)
              .fontWeight(this.viewYear === year ? TypeWeight.semibold : TypeWeight.regular)
              .fontColor(this.viewYear === year ? Colors.bg : Colors.ink)
              .backgroundColor(this.viewYear === year ? Colors.ink : Colors.wash)
              .borderRadius(Radius.chip)
              .enabled(!this.isYearDisabled(year))
              .opacity(this.isYearDisabled(year) ? 0.28 : 1)
              .onClick(() => {
                this.viewYear = year;
                if (this.isMonthDisabled(this.viewYear, this.viewMonth)) {
                  this.viewMonth = new Date().getMonth();
                }
              });
          }, (year: number) => `y_${year}_${this.viewYear === year}`);
        }.width('100%');
      }, (_row: number[], rIdx: number) => `yr_${this.yearPageStart}_${rIdx}`);

      Divider().color(Colors.hairline);

      ForEach(MONTH_ROWS, (row: number[], rIdx: number) => {
        Row({ space: Space.xs }) {
          ForEach(row, (monthIndex: number) => {
            Button(`${monthIndex + 1}月`)
              .type(ButtonType.Normal).layoutWeight(1).height(32).padding(0)
              .fontSize(TypeSize.meta)
              .fontWeight(this.viewMonth === monthIndex ? TypeWeight.semibold : TypeWeight.regular)
              .fontColor(this.viewMonth === monthIndex ? Colors.bg : Colors.ink)
              .backgroundColor(this.viewMonth === monthIndex ? Colors.ink : Colors.wash)
              .borderRadius(Radius.chip)
              .enabled(!this.isMonthDisabled(this.viewYear, monthIndex))
              .opacity(this.isMonthDisabled(this.viewYear, monthIndex) ? 0.28 : 1)
              .onClick(() => {
                this.viewMonth = monthIndex;
                this.pickingYearMonth = false;
              });
          }, (monthIndex: number) => `m_${this.viewYear}_${monthIndex}_${this.viewMonth === monthIndex}`);
        }.width('100%');
      }, (_row: number[], rIdx: number) => `mr_${this.viewYear}_${rIdx}`);
    }
    .width('100%');
  }

  @Builder
  private TimePanel(isEnd: boolean) {
    Column({ space: Space.xs }) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(TIME_PRESETS, (preset: QuickTimePreset) => {
          Button(preset.label)
            .type(ButtonType.Normal)
            .constraintSize({ minHeight: 32 })
            .fontSize(TypeSize.meta)
            .fontWeight(new Date(isEnd ? this.endAt : this.startAt).getHours() === preset.hour &&
              new Date(isEnd ? this.endAt : this.startAt).getMinutes() === preset.minute
              ? TypeWeight.semibold : TypeWeight.regular)
            .fontColor(new Date(isEnd ? this.endAt : this.startAt).getHours() === preset.hour &&
              new Date(isEnd ? this.endAt : this.startAt).getMinutes() === preset.minute
              ? Colors.bg : Colors.inkSoft)
            .backgroundColor(new Date(isEnd ? this.endAt : this.startAt).getHours() === preset.hour &&
              new Date(isEnd ? this.endAt : this.startAt).getMinutes() === preset.minute
              ? Colors.ink : Colors.wash)
            .borderRadius(Radius.chip)
            .padding({ left: Space.sm, right: Space.sm })
            .margin({ right: Space.xs, bottom: Space.xs })
            .onClick(() => this.setClockFor(isEnd, preset.hour, preset.minute));
        }, (preset: QuickTimePreset) => preset.label);
      }
      .width('100%');

      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width('100%')
          .height(TIME_SELECTION_HEIGHT)
          .borderRadius(Radius.card)
          .backgroundColor(Colors.wash)
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no');
        TimePicker({ selected: new Date(isEnd ? this.endAt : this.startAt) })
          .key(isEnd ? 'matter-end-clock' : 'matter-start-clock')
          .width(152)
          .height(TIME_WHEEL_HEIGHT)
          .backgroundColor(Color.Transparent)
          .useMilitaryTime(true)
          .dateTimeOptions({ hour: '2-digit', minute: '2-digit' })
          .selectedTextStyle({ color: Colors.ink, font: { size: 21, weight: TypeWeight.semibold } })
          .textStyle({ color: Colors.inkSoft, font: { size: 16 } })
          .disappearTextStyle({ color: Colors.inkMuted, font: { size: 13 } })
          .onChange((result: TimePickerResult) => {
            const cur = new Date(isEnd ? this.endAt : this.startAt);
            this.setClockFor(isEnd, result.hour ?? cur.getHours(), result.minute ?? cur.getMinutes());
          });
      }
      .width('100%')
      .height(TIME_WHEEL_HEIGHT);
    }
    .width('100%')
    .padding(Space.sm)
    .backgroundColor(Colors.bg)
    .borderRadius(Radius.card)
    .border({ width: 1, color: Colors.hairline });
  }

  @Builder
  private DayCountPopupMenu() {
    Column() {
      this.PopupOptionRow('不计算天数', this.dayCountMode === 'none', () => this.selectDayCount('none'));
      this.PopupOptionRow('倒数日（距离还有几天）', this.dayCountMode === 'countdown', () => this.selectDayCount('countdown'));
      this.PopupOptionRow('正数日（起始已过几天）', this.dayCountMode === 'elapsed', () => this.selectDayCount('elapsed'));
    }
    .width(204)
    .padding(Space.xs);
  }

  @Builder
  private ReminderPopupMenu() {
    Scroll() {
      Column() {
        ForEach(REMINDER_ITEMS, (mins: number) => {
          this.PopupOptionRow(
            timelineReminderLabel(mins < 0 ? undefined : mins),
            mins === this.reminderMinutes,
            () => {
              this.reminderMinutes = mins;
              this.popup = ActivePopup.None;
              this.onChanged();
            }
          );
        }, (mins: number) => `${mins}`);
      }
      .width('100%')
      .padding(Space.xs);
    }
    .width(176)
    .constraintSize({ maxHeight: 248 });
  }

  @Builder
  private RepeatPopupMenu() {
    Scroll() {
      Column() {
        ForEach(REPEAT_ITEMS, (rule: TimelineRepeat) => {
          this.PopupOptionRow(
            timelineRepeatLabel(rule),
            rule === this.repeat,
            () => {
              this.repeat = rule;
              this.popup = ActivePopup.None;
              this.onChanged();
            }
          );
        }, (rule: TimelineRepeat) => rule);
      }
      .width('100%')
      .padding(Space.xs);
    }
    .width(168)
    .constraintSize({ maxHeight: 224 });
  }

  @Builder
  private PopupOptionRow(label: string, selected: boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row() {
        Text(label)
          .layoutWeight(1)
          .fontSize(TypeSize.bodySmall)
          .fontWeight(selected ? TypeWeight.semibold : TypeWeight.regular)
          .fontColor(selected ? Colors.ink : Colors.inkSoft);
        if (selected) {
          Text('✓')
            .fontSize(TypeSize.bodySmall)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink);
        }
      }
      .width('100%');
    }
    .width('100%')
    .height(40)
    .padding({ left: Space.sm, right: Space.sm })
    .backgroundColor(selected ? Colors.wash : Color.Transparent)
    .borderRadius(Radius.card)
    .onClick(action);
  }

  @Builder
  private FeatureChipsRow() {
    Flex({ wrap: FlexWrap.Wrap }) {
      // 1. 天数胶囊
      Button({ type: ButtonType.Normal }) {
        Row({ space: 4 }) {
          Text(this.dayCountChipLabel())
            .fontSize(TypeSize.meta)
            .fontWeight(this.dayCountMode !== 'none' ? TypeWeight.semibold : TypeWeight.regular)
            .fontColor(this.dayCountMode !== 'none' ? Colors.bg : Colors.inkSoft);
          Text('▾')
            .fontSize(11)
            .fontColor(this.dayCountMode !== 'none' ? Colors.bg : Colors.inkMuted);
        }
      }
      .constraintSize({ minHeight: 34 })
      .padding({ left: Space.sm, right: Space.sm })
      .margin({ right: Space.xs, bottom: Space.xs })
      .backgroundColor(this.dayCountMode !== 'none' ? Colors.ink : Colors.wash)
      .borderRadius(Radius.chip)
      .onClick(() => {
        this.drawer = ActiveDrawer.None;
        this.popup = this.popup === ActivePopup.DayCount ? ActivePopup.None : ActivePopup.DayCount;
      })
      .bindPopup(this.popup === ActivePopup.DayCount, {
        builder: this.DayCountPopupMenu,
        placement: Placement.Bottom,
        enableArrow: false,
        popupColor: Colors.card,
        autoCancel: true,
        onStateChange: (ev) => { if (!ev.isVisible && this.popup === ActivePopup.DayCount) this.popup = ActivePopup.None; }
      });

      // 2. 提醒胶囊
      Button({ type: ButtonType.Normal }) {
        Row({ space: 4 }) {
          Text(this.reminderMinutes >= 0
            ? `提醒 · ${timelineReminderLabel(this.reminderMinutes)}`
            : '提醒')
            .fontSize(TypeSize.meta)
            .fontWeight(this.reminderMinutes >= 0 ? TypeWeight.semibold : TypeWeight.regular)
            .fontColor(this.reminderMinutes >= 0 ? Colors.bg : Colors.inkSoft);
          Text('▾')
            .fontSize(11)
            .fontColor(this.reminderMinutes >= 0 ? Colors.bg : Colors.inkMuted);
        }
      }
      .constraintSize({ minHeight: 34 })
      .padding({ left: Space.sm, right: Space.sm })
      .margin({ right: Space.xs, bottom: Space.xs })
      .backgroundColor(this.reminderMinutes >= 0 ? Colors.ink : Colors.wash)
      .borderRadius(Radius.chip)
      .onClick(() => {
        this.drawer = ActiveDrawer.None;
        this.popup = this.popup === ActivePopup.Reminder ? ActivePopup.None : ActivePopup.Reminder;
      })
      .bindPopup(this.popup === ActivePopup.Reminder, {
        builder: this.ReminderPopupMenu,
        placement: Placement.Bottom,
        enableArrow: false,
        popupColor: Colors.card,
        autoCancel: true,
        onStateChange: (ev) => { if (!ev.isVisible && this.popup === ActivePopup.Reminder) this.popup = ActivePopup.None; }
      });

      // 3. 重复胶囊（正数日不重复）
      if (this.dayCountMode !== 'elapsed') {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 4 }) {
            Text(this.repeat !== TimelineRepeat.None
              ? `重复 · ${timelineRepeatLabel(this.repeat)}`
              : '重复')
              .fontSize(TypeSize.meta)
              .fontWeight(this.repeat !== TimelineRepeat.None ? TypeWeight.semibold : TypeWeight.regular)
              .fontColor(this.repeat !== TimelineRepeat.None ? Colors.bg : Colors.inkSoft);
            Text('▾')
              .fontSize(11)
              .fontColor(this.repeat !== TimelineRepeat.None ? Colors.bg : Colors.inkMuted);
          }
        }
        .constraintSize({ minHeight: 34 })
        .padding({ left: Space.sm, right: Space.sm })
        .margin({ right: Space.xs, bottom: Space.xs })
        .backgroundColor(this.repeat !== TimelineRepeat.None ? Colors.ink : Colors.wash)
        .borderRadius(Radius.chip)
        .onClick(() => {
          this.drawer = ActiveDrawer.None;
          this.popup = this.popup === ActivePopup.Repeat ? ActivePopup.None : ActivePopup.Repeat;
        })
        .bindPopup(this.popup === ActivePopup.Repeat, {
          builder: this.RepeatPopupMenu,
          placement: Placement.Bottom,
          enableArrow: false,
          popupColor: Colors.card,
          autoCancel: true,
          onStateChange: (ev) => { if (!ev.isVisible && this.popup === ActivePopup.Repeat) this.popup = ActivePopup.None; }
        });
      }
    }
    .width('100%');

    if (this.repeatHint().length > 0) {
      Text(this.repeatHint())
        .width('100%')
        .fontSize(TypeSize.meta)
        .fontColor(Colors.inkMuted);
    }
  }

  build() {
    Column({ space: Space.sm }) {
      this.SpanSegment();

      if (this.span === 'range') {
        this.RangeRows();
      } else {
        this.SingleDateRow();
      }

      if (this.drawer === ActiveDrawer.StartDay || this.drawer === ActiveDrawer.EndDay) {
        this.CalendarPanel();
      } else if (this.drawer === ActiveDrawer.StartClock) {
        this.TimePanel(false);
      } else if (this.drawer === ActiveDrawer.EndClock) {
        this.TimePanel(true);
      }

      Divider().color(Colors.hairline);

      this.FeatureChipsRow();
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }
}
