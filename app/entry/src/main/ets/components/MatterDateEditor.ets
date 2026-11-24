import { DateMode } from '../model/Types';
import { daysUntil, formatDate, pad2 } from '../common/DateFormat';
import { Colors, Radius, Space, TABULAR_NUMS, TypeSize, TypeWeight } from '../common/Theme';

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
  { label: '18:00', hour: 18, minute: 0 },
  { label: '21:00', hour: 21, minute: 0 },
  { label: '23:59', hour: 23, minute: 59 }
];
const MONTH_ROWS: number[][] = [
  [0, 1, 2, 3],
  [4, 5, 6, 7],
  [8, 9, 10, 11]
];
const TIME_WHEEL_HEIGHT: number = 156;
const TIME_SELECTION_HEIGHT: number = 38;

function addMonthsClamped(base: Date, deltaMonths: number): Date {
  const targetYear = base.getFullYear();
  const targetMonth = base.getMonth() + deltaMonths;
  const firstOfTarget = new Date(targetYear, targetMonth, 1);
  const lastDay = new Date(firstOfTarget.getFullYear(), firstOfTarget.getMonth() + 1, 0).getDate();
  const clampedDay = Math.min(base.getDate(), lastDay);
  return new Date(firstOfTarget.getFullYear(), firstOfTarget.getMonth(), clampedDay,
    base.getHours(), base.getMinutes(), 0, 0);
}

function sameCalendarDate(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate();
}

@Component
export struct MatterDateEditor {
  @Link @Watch('onDatePropChanged') date: Date;
  @Link mode: DateMode;
  @Link hasTime: boolean;

  @State private calendarOpen: boolean = false;
  @State private pickingYearMonth: boolean = false;
  @State private timeOpen: boolean = false;
  @State private viewYear: number = new Date().getFullYear();
  @State private viewMonth: number = new Date().getMonth();
  @State private yearPageStart: number = new Date().getFullYear() - 4;

  aboutToAppear(): void {
    this.syncCalendarView(this.date);
  }

  private onDatePropChanged(): void {
    this.syncCalendarView(this.date);
  }

  private syncCalendarView(target: Date): void {
    this.viewYear = target.getFullYear();
    this.viewMonth = target.getMonth();
    this.yearPageStart = Math.max(1900, Math.min(2089, target.getFullYear() - 4));
  }

  private dateLabel(): string {
    if (this.mode === 'elapsed') return '起始日期';
    if (this.mode === 'deadline') return '截止日期';
    return '目标日期';
  }

  private presets(): QuickDatePreset[] {
    return this.mode === 'elapsed' ? PAST_PRESETS : FUTURE_PRESETS;
  }

  private presetDate(preset: QuickDatePreset): Date {
    const now = new Date();
    now.setHours(this.date.getHours(), this.date.getMinutes(), 0, 0);
    if (preset.monthsOffset !== undefined) {
      return addMonthsClamped(now, preset.monthsOffset);
    }
    const next = new Date(now.getTime());
    next.setDate(next.getDate() + (preset.daysOffset ?? 0));
    return next;
  }

  private isPresetSelected(preset: QuickDatePreset): boolean {
    return sameCalendarDate(this.date, this.presetDate(preset));
  }

  private applyPreset(preset: QuickDatePreset): void {
    const next = this.presetDate(preset);
    this.date = next;
    this.syncCalendarView(next);
  }

  private isFutureDate(year: number, month: number, day: number): boolean {
    const now = new Date();
    const todayKey = now.getFullYear() * 10000 + now.getMonth() * 100 + now.getDate();
    const cellKey = year * 10000 + month * 100 + day;
    return cellKey > todayKey;
  }

  private isMonthDisabled(year: number, month: number): boolean {
    if (this.mode !== 'elapsed') return false;
    const now = new Date();
    return year > now.getFullYear() || (year === now.getFullYear() && month > now.getMonth());
  }

  private isYearDisabled(year: number): boolean {
    if (this.mode !== 'elapsed') return false;
    return year > new Date().getFullYear();
  }

  private canGoNextMonth(): boolean {
    if (this.viewYear > 2100 || (this.viewYear === 2100 && this.viewMonth >= 11)) return false;
    if (this.mode === 'elapsed') {
      const now = new Date();
      if (this.viewYear > now.getFullYear() || (this.viewYear === now.getFullYear() && this.viewMonth >= now.getMonth())) {
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
    const next = new Date(cell.year, cell.month, cell.day, this.date.getHours(), this.date.getMinutes(), 0, 0);
    this.date = next;
    this.viewYear = cell.year;
    this.viewMonth = cell.month;
  }

  private jumpToToday(): void {
    const now = new Date();
    const next = new Date(now.getFullYear(), now.getMonth(), now.getDate(),
      this.date.getHours(), this.date.getMinutes(), 0, 0);
    this.date = next;
    this.syncCalendarView(next);
    this.pickingYearMonth = false;
  }

  private calendarWeeks(): CalendarDayCell[][] {
    const first = new Date(this.viewYear, this.viewMonth, 1);
    const leading = (first.getDay() + 6) % 7;
    const daysInMonth = new Date(this.viewYear, this.viewMonth + 1, 0).getDate();
    const totalCells = Math.ceil((leading + daysInMonth) / 7) * 7;
    const today = new Date();
    const weeks: CalendarDayCell[][] = [];
    let currentWeek: CalendarDayCell[] = [];

    for (let i = 0; i < totalCells; i++) {
      const cellDate = new Date(this.viewYear, this.viewMonth, 1 - leading + i);
      const y = cellDate.getFullYear();
      const m = cellDate.getMonth();
      const d = cellDate.getDate();
      const disabled = y < 1900 || y > 2100 || (this.mode === 'elapsed' && this.isFutureDate(y, m, d));
      currentWeek.push({
        key: `${y}-${m}-${d}`,
        year: y,
        month: m,
        day: d,
        inMonth: y === this.viewYear && m === this.viewMonth,
        isToday: sameCalendarDate(cellDate, today),
        isSelected: sameCalendarDate(cellDate, this.date),
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

  private selectMode(mode: DateMode): void {
    this.mode = mode;
    if (mode !== 'deadline') {
      this.timeOpen = false;
    }
    if (mode === 'elapsed' && daysUntil(this.date.getTime()) > 0) {
      const today = new Date();
      today.setHours(this.date.getHours(), this.date.getMinutes(), 0, 0);
      this.date = today;
      this.syncCalendarView(today);
    }
  }

  private setClock(hour: number, minute: number): void {
    const next = new Date(this.date.getTime());
    next.setHours(hour, minute, 0, 0);
    this.date = next;
  }

  private formattedDateWithWeekday(): string {
    return `${formatDate(this.date.getTime())} · ${WEEKDAY_CN[this.date.getDay()]}`;
  }

  @Builder
  private modeOption(value: DateMode, title: string, help: string) {
    Row({ space: Space.md }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(20)
          .height(20)
          .borderRadius(10)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: this.mode === value ? Colors.ink : Colors.line });
        if (this.mode === value) {
          Column()
            .width(10)
            .height(10)
            .borderRadius(5)
            .backgroundColor(Colors.ink);
        }
      }
      .width(20)
      .height(20);

      Column({ space: Space.xs }) {
        Text(title)
          .fontSize(TypeSize.body)
          .fontWeight(this.mode === value ? TypeWeight.semibold : TypeWeight.regular)
          .fontColor(this.mode === value ? Colors.ink : Colors.inkSoft);
        Text(help)
          .fontSize(TypeSize.meta)
          .fontWeight(TypeWeight.regular)
          .fontColor(Colors.inkMuted);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding(Space.md)
    .margin({ bottom: Space.xs })
    .backgroundColor(this.mode === value ? Colors.wash : Color.Transparent)
    .borderRadius(Radius.card)
    .onClick(() => this.selectMode(value));
  }

  @Builder
  private QuickDateBar() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.presets(), (preset: QuickDatePreset) => {
        Button(preset.label)
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 36 })
          .fontSize(TypeSize.bodySmall)
          .fontWeight(this.isPresetSelected(preset) ? TypeWeight.semibold : TypeWeight.regular)
          .fontColor(this.isPresetSelected(preset) ? Colors.bg : Colors.inkSoft)
          .backgroundColor(this.isPresetSelected(preset) ? Colors.ink : Colors.wash)
          .borderRadius(Radius.chip)
          .padding({ left: Space.md, right: Space.md })
          .margin({ right: Space.sm, bottom: Space.xs })
          .onClick(() => this.applyPreset(preset));
      }, (preset: QuickDatePreset) => this.mode + '_' + preset.label);
    }
    .width('100%');
  }

  @Builder
  private CalendarPanel() {
    Column({ space: Space.sm }) {
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
        .constraintSize({ minHeight: 40 })
        .padding({ left: Space.xs, right: Space.sm })
        .backgroundColor(this.pickingYearMonth ? Colors.wash : Color.Transparent)
        .borderRadius(Radius.card)
        .accessibilityText(this.pickingYearMonth ? '返回日历' : '快速选择年份与月份')
        .onClick(() => {
          this.pickingYearMonth = !this.pickingYearMonth;
          if (this.pickingYearMonth) {
            this.yearPageStart = Math.max(1900, Math.min(2089, this.viewYear - 4));
          }
        });

        Blank();

        Button('今天')
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 40 })
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
            .width(40)
            .height(40)
            .padding(0)
            .fontSize(20)
            .fontColor(Colors.ink)
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .enabled(this.canGoPrevMonth())
            .opacity(this.canGoPrevMonth() ? 1 : 0.35)
            .accessibilityText('上个月')
            .onClick(() => this.shiftMonth(-1));
          Button('›')
            .type(ButtonType.Normal)
            .width(40)
            .height(40)
            .padding(0)
            .fontSize(20)
            .fontColor(Colors.ink)
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .enabled(this.canGoNextMonth())
            .opacity(this.canGoNextMonth() ? 1 : 0.35)
            .accessibilityText('下个月')
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
    .padding(Space.md)
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
          .fontWeight(TypeWeight.regular)
          .fontColor(Colors.inkMuted);
      }, (name: string) => name);
    }
    .width('100%')
    .padding({ top: Space.xs, bottom: Space.xs });

    Column({ space: 2 }) {
      ForEach(this.calendarWeeks(), (week: CalendarDayCell[], rowIndex: number) => {
        Row() {
          ForEach(week, (cell: CalendarDayCell) => {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 2 }) {
                Text(`${cell.day}`)
                  .fontSize(TypeSize.body)
                  .fontWeight(cell.isSelected || cell.isToday ? TypeWeight.semibold : TypeWeight.regular)
                  .fontColor(cell.isSelected ? Colors.bg : cell.inMonth ? Colors.ink : Colors.inkMuted)
                  .fontFeature(TABULAR_NUMS);
                Column()
                  .width(12)
                  .height(2)
                  .borderRadius(1)
                  .backgroundColor(cell.isToday
                    ? (cell.isSelected ? Colors.bg : Colors.red)
                    : Color.Transparent);
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center);
            }
            .layoutWeight(1)
            .height(40)
            .padding(0)
            .backgroundColor(cell.isSelected ? Colors.ink : cell.isToday ? Colors.wash : Color.Transparent)
            .borderRadius(Radius.card)
            .enabled(!cell.disabled)
            .opacity(cell.disabled ? 0.25 : cell.inMonth ? 1 : 0.45)
            .accessibilityText(`${cell.year}年${cell.month + 1}月${cell.day}日` +
              (cell.isToday ? ' 今天' : '') + (cell.isSelected ? ' 已选中' : ''))
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
    Column({ space: Space.sm }) {
      Row() {
        Text('年份')
          .fontSize(TypeSize.meta)
          .fontColor(Colors.inkMuted);
        Blank();
        Button('‹')
          .type(ButtonType.Normal)
          .width(36)
          .height(36)
          .padding(0)
          .fontSize(18)
          .fontColor(Colors.ink)
          .backgroundColor(Color.Transparent)
          .borderRadius(Radius.card)
          .enabled(this.yearPageStart > 1900)
          .opacity(this.yearPageStart > 1900 ? 1 : 0.35)
          .accessibilityText('前十二年')
          .onClick(() => {
            this.yearPageStart = Math.max(1900, this.yearPageStart - 12);
          });
        Text(`${this.yearPageStart}–${this.yearPageStart + 11}`)
          .fontSize(TypeSize.meta)
          .fontColor(Colors.inkSoft)
          .fontFeature(TABULAR_NUMS);
        Button('›')
          .type(ButtonType.Normal)
          .width(36)
          .height(36)
          .padding(0)
          .fontSize(18)
          .fontColor(Colors.ink)
          .backgroundColor(Color.Transparent)
          .borderRadius(Radius.card)
          .enabled(this.yearPageStart + 12 <= 2100 && (!this.isYearDisabled(this.yearPageStart + 12)))
          .opacity(this.yearPageStart + 12 <= 2100 && (!this.isYearDisabled(this.yearPageStart + 12)) ? 1 : 0.35)
          .accessibilityText('后十二年')
          .onClick(() => {
            this.yearPageStart = Math.min(2089, this.yearPageStart + 12);
          });
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Column({ space: Space.xs }) {
        ForEach(this.yearRows(), (row: number[], rIdx: number) => {
          Row({ space: Space.xs }) {
            ForEach(row, (year: number) => {
              Button(`${year}`)
                .type(ButtonType.Normal)
                .layoutWeight(1)
                .height(36)
                .padding(0)
                .fontSize(TypeSize.bodySmall)
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
          }
          .width('100%');
        }, (_row: number[], rIdx: number) => `yr_${this.yearPageStart}_${rIdx}`);
      }
      .width('100%');

      Divider().color(Colors.hairline);

      Text('月份')
        .fontSize(TypeSize.meta)
        .fontColor(Colors.inkMuted)
        .width('100%');

      Column({ space: Space.xs }) {
        ForEach(MONTH_ROWS, (row: number[], rIdx: number) => {
          Row({ space: Space.xs }) {
            ForEach(row, (monthIndex: number) => {
              Button(`${monthIndex + 1}月`)
                .type(ButtonType.Normal)
                .layoutWeight(1)
                .height(36)
                .padding(0)
                .fontSize(TypeSize.bodySmall)
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
          }
          .width('100%');
        }, (_row: number[], rIdx: number) => `mr_${this.viewYear}_${rIdx}`);
      }
      .width('100%');
    }
    .width('100%');
  }

  @Builder
  private TimePanel() {
    Column({ space: Space.sm }) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(TIME_PRESETS, (preset: QuickTimePreset) => {
          Button(preset.label)
            .type(ButtonType.Normal)
            .constraintSize({ minHeight: 36 })
            .fontSize(TypeSize.bodySmall)
            .fontWeight(this.date.getHours() === preset.hour && this.date.getMinutes() === preset.minute
              ? TypeWeight.semibold : TypeWeight.regular)
            .fontColor(this.date.getHours() === preset.hour && this.date.getMinutes() === preset.minute
              ? Colors.bg : Colors.inkSoft)
            .backgroundColor(this.date.getHours() === preset.hour && this.date.getMinutes() === preset.minute
              ? Colors.ink : Colors.wash)
            .borderRadius(Radius.chip)
            .padding({ left: Space.md, right: Space.md })
            .margin({ right: Space.xs, bottom: Space.xs })
            .onClick(() => this.setClock(preset.hour, preset.minute));
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
        TimePicker({ selected: this.date })
          .width(156)
          .height(TIME_WHEEL_HEIGHT)
          .backgroundColor(Color.Transparent)
          .useMilitaryTime(true)
          .dateTimeOptions({ hour: '2-digit', minute: '2-digit' })
          .selectedTextStyle({ color: Colors.ink, font: { size: 22, weight: TypeWeight.semibold } })
          .textStyle({ color: Colors.inkSoft, font: { size: 17 } })
          .disappearTextStyle({ color: Colors.inkMuted, font: { size: 13 } })
          .onChange((result: TimePickerResult) => {
            this.setClock(result.hour ?? this.date.getHours(), result.minute ?? this.date.getMinutes());
          });
      }
      .width('100%')
      .height(TIME_WHEEL_HEIGHT);
    }
    .width('100%')
    .padding(Space.md)
    .backgroundColor(Colors.bg)
    .borderRadius(Radius.card)
    .border({ width: 1, color: Colors.hairline });
  }

  @Builder
  private toggleField(label: string, value: string, open: boolean, onToggle: () => void) {
    Column({ space: Space.sm }) {
      Text(label)
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkSoft)
        .width('100%');
      Button({ type: ButtonType.Normal }) {
        Row() {
          Text(value)
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink)
            .fontFeature(TABULAR_NUMS);
          Blank();
          Text(open ? '收起 ⌃' : '选择 ⌄')
            .fontSize(TypeSize.meta)
            .fontColor(Colors.inkMuted);
        }
        .width('100%')
        .padding({ left: Space.md, right: Space.md });
      }
      .width('100%')
      .constraintSize({ minHeight: 44 })
      .backgroundColor(Colors.wash)
      .borderRadius(Radius.card)
      .onClick(onToggle);
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  build() {
    Column({ space: Space.sm }) {
      Text('你想怎样使用这个日期？')
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkSoft)
        .width('100%');

      this.modeOption('countdown', '倒数日', '看距离某一天还有多少天');
      this.modeOption('elapsed', '正数日', '看从某一天起已经过多少天');
      this.modeOption('deadline', '截止时间', '标记最晚何时完成');

      this.toggleField(this.dateLabel(), this.formattedDateWithWeekday(), this.calendarOpen, () => {
        this.calendarOpen = !this.calendarOpen;
        if (this.calendarOpen) {
          this.timeOpen = false;
          this.pickingYearMonth = false;
          this.syncCalendarView(this.date);
        }
      });

      this.QuickDateBar();

      if (this.calendarOpen) {
        this.CalendarPanel();
      }

      if (this.mode === 'deadline') {
        Row({ space: Space.md }) {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(20)
              .height(20)
              .borderRadius(Radius.chip)
              .backgroundColor(this.hasTime ? Colors.ink : Color.Transparent)
              .border({ width: 1, color: this.hasTime ? Colors.ink : Colors.line });
            if (this.hasTime) {
              Text('✓')
                .fontSize(TypeSize.meta)
                .fontWeight(TypeWeight.semibold)
                .fontColor(Colors.bg);
            }
          }
          .width(20)
          .height(20);

          Text('设置具体时间')
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.regular)
            .fontColor(Colors.ink);
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          if (!this.hasTime) {
            const next = new Date(this.date.getTime());
            next.setHours(18, 0, 0, 0);
            this.date = next;
            this.hasTime = true;
          } else {
            this.hasTime = false;
            this.timeOpen = false;
          }
        });

        if (this.hasTime) {
          this.toggleField('具体时间', pad2(this.date.getHours()) + ':' + pad2(this.date.getMinutes()),
            this.timeOpen, () => {
              this.timeOpen = !this.timeOpen;
              if (this.timeOpen) {
                this.calendarOpen = false;
              }
            });
          if (this.timeOpen) {
            this.TimePanel();
          }
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }
}
