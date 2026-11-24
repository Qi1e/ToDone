import { Colors, Radius, Space, TABULAR_NUMS, TypeSize, TypeWeight } from '../common/Theme';
import { formatDate } from '../common/DateFormat';
import { TimelineBlock, TimelineTag } from '../contracts/TimelineService';
import { CalendarEntryStrip, HomeCalendarDay, HomeCalendarWeek, homeCalendarWeeks, MAX_CALENDAR_STRIPS } from '../domain/HomeMonthCalendar';
import { calendarRingWeeks, RING_DOT_DEGREES, RING_RADIUS, RING_STROKE, TimelineRingArc, TimelineRingDay,
  TimelineRingWeek, timelineRingDays } from '../domain/TimelineDayRing';

export const TIMELINE_WEEKDAYS: string[] = ['一', '二', '三', '四', '五', '六', '日'];
const ROW_HEIGHT: number = 44;
const RING_SIZE: number = 32;
const CIRCLE_SIZE: number = 24;
const PAN_THRESHOLD: number = 32;
const SETTLE_MS: number = 160;

export function monthStart(day: number, offset: number = 0): number {
  const date = new Date(day);
  return new Date(date.getFullYear(), date.getMonth() + offset, 1, 12).getTime();
}

function mondayOfWeek(day: number): number {
  const date = new Date(day);
  date.setHours(12, 0, 0, 0);
  date.setDate(date.getDate() - (date.getDay() + 6) % 7);
  return date.getTime();
}

export function monthWeekCount(month: number): number {
  const first = new Date(month);
  const last = new Date(first.getFullYear(), first.getMonth() + 1, 0);
  return Math.ceil(((first.getDay() + 6) % 7 + last.getDate()) / 7);
}

@Component
struct DateRingCanvas {
  @Prop @Watch('paint') arcs: TimelineRingArc[] = [];
  @Prop @Watch('paint') fraction: number = 1;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;

  private paint(): void {
    if (!this.ready) return;
    const center = RING_SIZE / 2;
    const ctx = this.context;
    ctx.clearRect(0, 0, RING_SIZE, RING_SIZE);
    ctx.lineCap = 'round';
    ctx.lineWidth = RING_STROKE;
    if (this.fraction <= 0) return;
    for (const arc of this.arcs) {
      const sweep = arc.sweep * this.fraction;
      const origin = arc.start * this.fraction - 90;
      ctx.beginPath();
      if (sweep <= RING_DOT_DEGREES + 0.001) {
        const angle = (origin + sweep / 2) * Math.PI / 180;
        const radius = Math.min(RING_STROKE / 2, RING_RADIUS * Math.sin(sweep * Math.PI / 360));
        ctx.fillStyle = arc.color;
        ctx.arc(center + RING_RADIUS * Math.cos(angle), center + RING_RADIUS * Math.sin(angle), radius, 0, 2 * Math.PI);
        ctx.fill();
      } else {
        const start = (origin + RING_DOT_DEGREES / 2) * Math.PI / 180;
        const end = (origin + sweep - RING_DOT_DEGREES / 2) * Math.PI / 180;
        ctx.strokeStyle = arc.color;
        ctx.arc(center, center, RING_RADIUS, start, end);
        ctx.stroke();
      }
    }
  }

  build() {
    Canvas(this.context).width(RING_SIZE).height(RING_SIZE)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      .onReady(() => { this.ready = true; this.paint(); });
  }
}

@Component
export struct TimelineDayNumber {
  @Prop day: number;
  @Prop selected: boolean = false;
  @Prop muted: boolean = false;
  @Prop today: number = Date.now();
  @Prop ringFraction: number = 1;

  @Prop ring: TimelineRingDay = { day: 0, count: 0, arcs: [] };

  private isToday(): boolean {
    return formatDate(this.day) === formatDate(this.today);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.ringFraction > 0 && this.ring.count > 0) {
        DateRingCanvas({ arcs: this.ring.arcs, fraction: this.ringFraction });
      }
      Text(new Date(this.day).getDate().toString())
        .width(CIRCLE_SIZE).height(CIRCLE_SIZE).textAlign(TextAlign.Center)
        .fontSize(TypeSize.body).fontWeight(this.isToday() || this.selected ? TypeWeight.semibold : TypeWeight.regular)
        .fontFeature(TABULAR_NUMS)
        .fontColor(this.isToday() ? Colors.bg : this.selected ? Colors.ink : this.muted ? Colors.inkMuted : Colors.ink)
        .borderRadius(CIRCLE_SIZE / 2)
        .backgroundColor(this.isToday() ? Colors.ink : this.selected ? Colors.wash : Color.Transparent);
    }.width(RING_SIZE).height(RING_SIZE);
  }
}

const ANNOTATION_HEIGHT: number = 13;
const STRIP_HEIGHT: number = 15;
const STRIP_GAP: number = 2;

@Component
export struct TimelineMonthDay {
  @Prop cell: HomeCalendarDay;
  @Prop day: number;
  @Prop today: number;
  @Prop muted: boolean = false;
  @Prop prepareDetail: boolean = false;
  @Prop showScheduleRings: boolean = true;
  @Prop detail: number = 0;
  @Prop rowHeight: number = ROW_HEIGHT;
  @Prop fullRowHeight: number = ROW_HEIGHT;
  onPick: (day: number) => void = () => {};

  private visibleCount(): number {
    return Math.min(MAX_CALENDAR_STRIPS, Math.max(1,
      Math.floor((this.fullRowHeight - RING_SIZE - ANNOTATION_HEIGHT - STRIP_GAP) / (STRIP_HEIGHT + STRIP_GAP))));
  }

  private dateTop(): number {
    // 同一个日期数字沿已展开的周行从居中移向格子顶部。
    return Math.max(0, (this.rowHeight - RING_SIZE - (this.fullRowHeight - RING_SIZE) * this.detail) / 2);
  }

  private accessibleLabel(): string {
    const label = formatDate(this.cell.day) + (formatDate(this.cell.day) === formatDate(this.today) ? ' 今天' : '') +
      (formatDate(this.cell.day) === formatDate(this.day) ? ' 已选中' : '') +
      (this.cell.ring.count > 0 ? '，' + this.cell.ring.count + ' 项安排' : '，暂无安排');
    if (this.detail < 1) return label;
    return label + ' ' + this.cell.annotation + ' ' + this.cell.strips.slice(0, this.visibleCount())
      .map((strip: CalendarEntryStrip) => strip.title).join('，');
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Row() {
          TimelineDayNumber({ day: this.cell.day, today: this.today, muted: this.muted,
            selected: formatDate(this.cell.day) === formatDate(this.day), ring: this.cell.ring,
            ringFraction: this.showScheduleRings ? 1 - this.detail : 0 });
        }.width('100%').height(RING_SIZE).justifyContent(FlexAlign.Center).position({ x: 0, y: this.dateTop() });
        if (this.prepareDetail || this.detail > 0) {
          if (this.cell.entries.length > this.visibleCount()) {
            Row() {
              Text('+' + (this.cell.entries.length - this.visibleCount())).fontSize(TypeSize.meta)
                .fontColor(Colors.inkMuted).fontFeature(TABULAR_NUMS).maxLines(1);
            }.width('100%').justifyContent(FlexAlign.End).padding({ right: 2 }).opacity(this.detail)
            .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants');
          }
          Column({ space: STRIP_GAP }) {
            Text(this.cell.annotation).fontSize(TypeSize.meta).fontColor(Colors.inkMuted).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center)
              .width('100%').height(ANNOTATION_HEIGHT);
            ForEach(this.cell.strips, (strip: CalendarEntryStrip, index: number) => {
              if (index < this.visibleCount()) {
                Text(strip.title).fontSize(TypeSize.meta).fontWeight(TypeWeight.semibold).fontColor(strip.ink)
                  .width('100%').height(STRIP_HEIGHT).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding({ left: 3, right: 2 }).backgroundColor(strip.fill).borderRadius(Radius.chip);
              }
            }, (strip: CalendarEntryStrip) => strip.key);
          }.width('100%').padding({ left: 3, right: 3 }).position({ x: 0, y: this.dateTop() + RING_SIZE })
          .opacity(this.detail).hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants');
          // 每个格子只绘制右、下两边，相邻日期的边界不会叠粗。
          Row().width('100%').height('100%').border({ width: {
            right: new Date(this.cell.day).getDay() === 0 ? 0 : 0.5, bottom: 0.5
          }, color: Colors.hairline }).opacity(this.detail).hitTestBehavior(HitTestMode.None).accessibilityLevel('no');
        }
      }.width('100%').height('100%').clip(true);
    }.width('100%').height(this.rowHeight).padding(0).borderRadius(0).backgroundColor(Color.Transparent)
    .accessibilityText(this.accessibleLabel()).onClick(() => this.onPick(this.cell.day));
  }
}

// 编辑和浏览都用同一组日期行。选中周随着裁切窗口展开，始终保留原来的日期格。
@Component
export struct TimelineCalendarRows {
  @Prop @Watch('refreshRows') month: number;
  @Prop @Watch('refreshAnchor') anchorDay: number;
  @Prop day: number;
  @Prop today: number = Date.now();
  @Prop expanded: boolean = false;
  @Prop progress: number = 0;
  @Prop rowHeight: number = ROW_HEIGHT;
  @Prop detailedCalendar: boolean = false;
  @Prop prepareDetail: boolean = false;
  @Prop showScheduleRings: boolean = true;
  @Prop detail: number = 0;
  @Prop fullRowHeight: number = ROW_HEIGHT;
  @Prop @Watch('refreshRows') blocks: TimelineBlock[] = [];
  @Prop @Watch('refreshRows') tags: TimelineTag[] = [];
  onPick: (day: number) => void = () => {};
  @State private weeks: HomeCalendarWeek[] = [];
  @State private landingWeeks: HomeCalendarWeek[] = [];
  @State private anchorIndex: number = 0;

  aboutToAppear(): void {
    this.refreshRows();
  }

  private simpleWeeks(start: number, days: number): HomeCalendarWeek[] {
    return calendarRingWeeks(timelineRingDays(start, days, this.blocks, this.tags))
      .map((week: TimelineRingWeek): HomeCalendarWeek => {
        return { key: week.key, days: week.days.map((ring: TimelineRingDay): HomeCalendarDay => {
          return { day: ring.day, ring: ring, entries: [], annotation: '', strips: [] };
        }) };
      });
  }

  private refreshRows(): void {
    this.weeks = this.detailedCalendar ? homeCalendarWeeks(this.month, this.blocks, this.tags) :
      this.simpleWeeks(mondayOfWeek(this.month), monthWeekCount(this.month) * 7);
    this.refreshAnchor();
  }

  private refreshAnchor(): void {
    const monday = mondayOfWeek(this.anchorDay);
    this.anchorIndex = this.weeks.findIndex((week: HomeCalendarWeek) => mondayOfWeek(week.days[0].day) === monday);
    // 浏览到其他月份但尚未选日时，上滑仍需落回原来选中的周。
    this.landingWeeks = this.anchorIndex < 0 ? this.simpleWeeks(monday, 7) : [];
  }

  @Builder
  private DayRow(days: HomeCalendarDay[]) {
    Row() {
      ForEach(days, (cell: HomeCalendarDay) => {
        TimelineMonthDay({ cell: cell, day: this.day, today: this.today, detail: this.detail, prepareDetail: this.prepareDetail,
          showScheduleRings: this.showScheduleRings,
          rowHeight: this.rowHeight, fullRowHeight: this.fullRowHeight, muted: this.expanded && monthStart(cell.day) !== this.month,
          onPick: (day: number) => this.onPick(day) }).layoutWeight(1);
      }, (cell: HomeCalendarDay) => cell.day.toString());
    }.width('100%').height(this.rowHeight);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.weeks, (week: HomeCalendarWeek, index: number) => {
        Column() {
          this.DayRow(week.days);
        }.width('100%').height(this.rowHeight)
        .position({ x: 0, y: (index - Math.max(0, this.anchorIndex) * (1 - this.progress)) * this.rowHeight })
        .opacity(this.anchorIndex < 0 && index === 0 ? this.progress : 1)
        .enabled(index === this.anchorIndex || (this.expanded && this.progress === 1))
        .accessibilityLevel((this.expanded && this.progress === 1) || index === this.anchorIndex ? 'auto' : 'no-hide-descendants');
      }, (week: HomeCalendarWeek, index: number) => index + '-' + week.key);
      ForEach(this.landingWeeks, (week: HomeCalendarWeek) => {
        Column() {
          this.DayRow(week.days);
        }.width('100%').height(this.rowHeight).opacity(1 - this.progress)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no-hide-descendants');
      }, (week: HomeCalendarWeek) => week.key);
    }.width('100%').height(this.rowHeight * (1 + (monthWeekCount(this.month) - 1) * this.progress)).clip(true);
  }
}

@Component
export struct TimelineDatePicker {
  @Prop @Watch('dayChanged') day: number;
  @Prop @Watch('expandedChanged') expanded: boolean = false;
  @Prop caption: string;
  @Prop today: number = Date.now();
  @Prop blocks: TimelineBlock[] = [];
  @Prop tags: TimelineTag[] = [];
  onToggle: () => void = () => {};
  onPick: (day: number) => void = () => {};
  @State private browsedMonth: number = 0;
  @State private reveal: number = 0;

  aboutToAppear(): void {
    this.reveal = this.expanded ? 1 : 0;
  }

  private month(): number {
    return this.expanded && this.browsedMonth !== 0 ? this.browsedMonth : monthStart(this.day);
  }

  private settle(expanded: boolean): void {
    this.getUIContext().animateTo({ duration: SETTLE_MS, curve: Curve.EaseOut }, () => {
      this.reveal = expanded ? 1 : 0;
    });
  }

  private expandedChanged(): void {
    if (!this.expanded) this.browsedMonth = 0;
    this.settle(this.expanded);
  }

  private dayChanged(): void {
    this.browsedMonth = 0;
  }

  private drag(offset: number): void {
    if (!this.expanded) {
      this.reveal = Math.min(1, Math.max(0, offset / ((monthWeekCount(this.month()) - 1) * ROW_HEIGHT)));
    }
  }

  private release(event: GestureEvent): void {
    const offset = event.offsetY;
    if (this.expanded) {
      if (Math.abs(offset) >= PAN_THRESHOLD) this.browsedMonth = monthStart(this.month(), offset < 0 ? 1 : -1);
    } else if (offset >= PAN_THRESHOLD) {
      this.onToggle();
    } else {
      this.settle(false);
    }
  }

  @Builder
  private Header() {
    Row() {
      Button({ type: ButtonType.Normal }) {
        Row({ space: Space.xs }) {
          Text(new Date(this.month()).getFullYear() + '年' + (new Date(this.month()).getMonth() + 1) + '月')
            .fontSize(TypeSize.title).fontWeight(TypeWeight.semibold).fontColor(Colors.ink).fontFeature(TABULAR_NUMS);
          Text(this.expanded ? '▴' : '▾').fontSize(TypeSize.meta).fontColor(Colors.inkMuted);
        }
      }
      .height(40).padding(0).backgroundColor(Color.Transparent).borderRadius(Radius.card)
      .accessibilityText(this.expanded ? '收起月历' : '展开选日月历')
      .onClick(() => this.onToggle());
      Blank();
      Text(this.caption).fontSize(TypeSize.bodySmall).fontColor(Colors.inkSoft);
      if (this.expanded) {
        Button('‹', { type: ButtonType.Normal }).width(40).height(40).padding(0)
          .fontSize(20).fontColor(Colors.ink).borderRadius(Radius.card)
          .backgroundColor(Color.Transparent).accessibilityText('上个月')
          .onClick(() => { this.browsedMonth = monthStart(this.month(), -1); });
        Button('›', { type: ButtonType.Normal }).width(40).height(40).padding(0)
          .fontSize(20).fontColor(Colors.ink).borderRadius(Radius.card)
          .backgroundColor(Color.Transparent).accessibilityText('下个月')
          .onClick(() => { this.browsedMonth = monthStart(this.month(), 1); });
      }
    }.height(40).width('100%').padding({ left: Space.sm, right: Space.sm });
  }

  build() {
    Column() {
      this.Header();
      Row() {
        ForEach(TIMELINE_WEEKDAYS, (name: string) => {
          Text(name).layoutWeight(1).textAlign(TextAlign.Center).fontSize(TypeSize.meta).fontColor(Colors.inkMuted);
        }, (name: string) => name);
      }.width('100%').height(20);
      TimelineCalendarRows({ month: this.month(), anchorDay: this.day, day: this.day, today: this.today,
        expanded: this.expanded, progress: this.reveal, blocks: this.blocks, tags: this.tags,
        onPick: (day: number) => {
          if (this.expanded) this.onPick(day);
          else this.onToggle();
        }
      });
    }
    .width('100%').padding({ left: Space.xs, right: Space.xs, top: Space.lg, bottom: Space.xs })
    .backgroundColor(Colors.bg)
    .border({ width: { bottom: 1 }, color: Colors.hairline })
    .priorityGesture(PanGesture({ direction: PanDirection.Vertical, distance: 8 })
      .onActionUpdate((event: GestureEvent) => this.drag(event.offsetY))
      .onActionEnd((event: GestureEvent) => this.release(event))
      .onActionCancel(() => this.settle(this.expanded)));
  }
}
