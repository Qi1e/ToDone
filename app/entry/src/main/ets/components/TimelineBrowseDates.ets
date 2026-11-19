import { AnimatorResult } from '@kit.ArkUI';
import { pad2 } from '../common/DateFormat';
import { Colors, Space } from '../common/Theme';
import { TimelineBlock, TimelineTag } from '../contracts/TimelineService';
import { DEFAULT_RING_COLOR } from '../domain/TimelineDayRing';
import { localDayStart, timelineBlocksForDay, timelineDayHeading } from '../domain/TimelineLayout';
import { TimelineBrowseCalendar } from './TimelineBrowseCalendar';
import { monthStart, monthWeekCount } from './TimelineDatePicker';
import { BROWSE_TITLE_HEIGHT, BROWSE_WEEKDAYS_HEIGHT, PREVIEW_HEADER_HEIGHT, PREVIEW_ROW_HEIGHT, BrowsePanelSizes,
  browseHeight, browseLevelProgress, browseOpensFullCalendar, browsePanelSizes, browseReleaseTarget } from './TimelineBrowseMotion';

function clock(stamp: number): string {
  const time = new Date(stamp);
  return pad2(time.getHours()) + ':' + pad2(time.getMinutes());
}

@Component
export struct TimelineBrowseDates {
  @Prop @Watch('refreshPreview') day: number;
  @Link month: number;
  @Link @Watch('settle') level: number;
  @Prop readError: string = '';
  @Prop showScheduleRings: boolean = true;
  onRetry: () => void = () => {};
  @Prop today: number;
  @Prop @Watch('refreshPreview') blocks: TimelineBlock[] = [];
  @Prop tags: TimelineTag[] = [];
  @Prop @Watch('resize') availableHeight: number = 0;
  onSelectDay: (day: number) => void = () => {};
  onSelectBlock: (block: TimelineBlock) => void = () => {};

  @State private entries: TimelineBlock[] = [];
  @State private sizes: BrowsePanelSizes = browsePanelSizes(0);
  @State private progress: number = 0;
  private calendarScroll: Scroller = new Scroller();
  private previewScroll: Scroller = new Scroller();
  private calendarHeight: number = 0;
  private dragStart: number = 0;
  private calendarOffsetPerProgress: number = 0;
  private dragging: boolean = false;
  private dragLevel: number = 0;
  private scrollUpAvailable: boolean = false;
  private scrollDownAvailable: boolean = false;
  private animator?: AnimatorResult;

  aboutToAppear(): void {
    this.progress = this.level;
    this.resize();
    this.refreshPreview();
  }

  aboutToDisappear(): void {
    this.stopAnimation();
  }

  private resize(): void {
    this.sizes = browsePanelSizes(this.availableHeight);
  }

  private refreshPreview(): void {
    this.entries = timelineBlocksForDay(this.day, this.blocks);
    if ((this.previewScroll.currentOffset()?.yOffset ?? 0) > 0) {
      this.previewScroll.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    }
  }

  private detail(): number {
    return Math.max(0, this.progress - 1);
  }

  private fullRowHeight(): number {
    const rowsSpace = this.availableHeight - BROWSE_TITLE_HEIGHT - BROWSE_WEEKDAYS_HEIGHT;
    return Math.max(80, rowsSpace / monthWeekCount(this.month));
  }

  private rowHeight(): number {
    return this.sizes.rowHeight + (this.fullRowHeight() - this.sizes.rowHeight) * this.detail();
  }

  private stopAnimation(): void {
    const anim = this.animator;
    this.animator = undefined;
    anim?.cancel();
  }

  private rememberScroll(): void {
    const offset = this.calendarScroll.currentOffset()?.yOffset ?? 0;
    this.calendarOffsetPerProgress = this.progress > 0 ? offset / Math.min(1, this.progress) : 0;
  }

  private moveTo(value: number): void {
    this.progress = value;
    if (value <= 1 && this.calendarOffsetPerProgress > 0) {
      this.calendarScroll.scrollTo({ xOffset: 0, yOffset: value * this.calendarOffsetPerProgress, animation: false });
    }
  }

  private finishAt(target: number): void {
    this.progress = target;
    if (target === 0) {
      this.month = monthStart(this.day);
      this.calendarScroll.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    }
  }

  private requestLevel(target: number): void {
    if (target === this.level) this.settle();
    else this.level = target;
  }

  private settle(): void {
    this.dragging = false;
    this.stopAnimation();
    const target = this.level;
    this.rememberScroll();
    if (this.progress === target) {
      this.finishAt(target);
      return;
    }
    const anim = this.getUIContext().createAnimator({
      duration: Math.round(110 + 130 * Math.abs(target - this.progress)),
      easing: 'ease-out', delay: 0, fill: 'forwards', direction: 'normal', iterations: 1,
      begin: this.progress, end: target
    });
    this.animator = anim;
    anim.onFrame = (value: number) => {
      if (this.animator === anim) this.moveTo(value);
    };
    anim.onFinish = () => {
      if (this.animator !== anim) return;
      this.animator = undefined;
      this.finishAt(target);
    };
    anim.play();
  }

  private scrollUnderFinger(y: number): Scroller | undefined {
    const header = BROWSE_TITLE_HEIGHT + BROWSE_WEEKDAYS_HEIGHT;
    if (y >= header && y < this.calendarHeight &&
      header + monthWeekCount(this.month) * this.rowHeight() > this.calendarHeight + 1) return this.calendarScroll;
    const listTop = this.calendarHeight + PREVIEW_HEADER_HEIGHT;
    if (this.progress === 1 && y >= listTop && listTop + this.entries.length * PREVIEW_ROW_HEIGHT > this.sizes.openHeight + 1) return this.previewScroll;
    return undefined;
  }

  private startDrag(event: GestureEvent): void {
    const y = event.fingerList[0] ? event.fingerList[0].localY - event.offsetY : 0;
    const scroller = this.progress === 1 || this.progress === 2 ? this.scrollUnderFinger(y) : undefined;
    this.scrollDownAvailable = (scroller?.currentOffset()?.yOffset ?? 0) > 1;
    this.scrollUpAvailable = scroller !== undefined && !scroller.isAtEnd();
    this.stopAnimation();
    this.rememberScroll();
    this.dragStart = this.progress;
    this.dragLevel = this.level;
    this.dragging = true;
    this.updateDrag(event);
  }

  private updateDrag(event: GestureEvent): void {
    if (!this.dragging) return;
    // 列表可沿起手方向滚动时整次手势留给列表；在边界拉动才切换层级。
    if ((event.offsetY > 0 && this.scrollDownAvailable) || (event.offsetY < 0 && this.scrollUpAvailable)) {
      this.dragging = false;
      return;
    }
    if (event.offsetY !== 0) {
      this.scrollDownAvailable = false;
      this.scrollUpAvailable = false;
    }
    this.moveTo(browseLevelProgress(this.dragStart, this.dragLevel, event.offsetY, this.sizes, this.availableHeight));
  }

  private endDrag(event: GestureEvent): void {
    this.updateDrag(event);
    if (!this.dragging) return;
    this.dragging = false;
    if (this.dragLevel === 2) {
      const close = browseOpensFullCalendar(true, -event.offsetY, -event.velocityY);
      this.requestLevel(close || this.progress <= 1 ? 1 : 2);
    } else if (this.progress > 1) {
      const open = browseOpensFullCalendar(this.dragLevel === 1, event.offsetY, event.velocityY);
      this.requestLevel(open || this.progress >= 1.5 ? 2 : 1);
    } else {
      const open = browseReleaseTarget(this.progress, event.offsetY, event.velocityY, this.sizes.openHeight - this.sizes.closedHeight);
      this.requestLevel(open ? 1 : 0);
    }
  }

  private cancelDrag(): void {
    if (this.dragging) this.settle();
  }

  private timeRange(block: TimelineBlock): string {
    const start = localDayStart(this.day);
    const end = localDayStart(start, 1);
    return clock(Math.max(start, block.startAt)) + '–' + (block.endAt >= end ? '24:00' : clock(block.endAt));
  }

  private blockColor(block: TimelineBlock): string {
    const tag = this.tags.find((item: TimelineTag) => item.id === block.tagId);
    return tag?.color ?? DEFAULT_RING_COLOR;
  }

  @Builder
  private Preview() {
    Column() {
      Row() {
        Text(timelineDayHeading(this.day, this.today) + ' · ' + this.entries.length + '项')
          .layoutWeight(1).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Colors.text)
        Button('回今天').height(PREVIEW_HEADER_HEIGHT).padding({ left: Space.small, right: Space.small })
          .backgroundColor(Color.Transparent).fontColor(Colors.primary).fontSize(14)
          .onClick(() => {
            this.onSelectDay(this.today);
            this.calendarScroll.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
          })
      }.width('100%').height(PREVIEW_HEADER_HEIGHT)
      if (this.readError.length > 0) {
        Button('日程读取失败，重试').height(PREVIEW_ROW_HEIGHT).fontColor(Colors.primary)
          .backgroundColor(Color.Transparent).onClick(() => this.onRetry())
      } else if (this.entries.length === 0) {
        Text('这天暂无安排').width('100%').height(PREVIEW_ROW_HEIGHT)
          .fontSize(14).fontColor(Colors.subText)
      } else {
        List({ scroller: this.previewScroll }) {
          ForEach(this.entries, (block: TimelineBlock) => {
            ListItem() {
              Row({ space: Space.small }) {
                Row().width(7).height(7).borderRadius(4).backgroundColor(this.blockColor(block))
                Text(this.timeRange(block)).fontSize(13).fontColor(Colors.subText)
                Text(block.title).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontSize(15).fontColor(Colors.text)
              }.width('100%').height(PREVIEW_ROW_HEIGHT).accessibilityGroup(true)
              .onClick(() => this.onSelectBlock(block))
            }
          }, (block: TimelineBlock) => this.day + JSON.stringify(block))
        }.width('100%').layoutWeight(1).enableScrollInteraction(this.progress === 1).edgeEffect(EdgeEffect.None)
      }
    }.width('100%').layoutWeight(1).clip(true).opacity(1 - Math.abs(this.progress - 1))
    .padding({ left: Space.large, right: Space.large })
    .accessibilityLevel(this.progress === 1 ? 'auto' : 'no-hide-descendants')
  }

  build() {
    Column() {
      Column() {
        TimelineBrowseCalendar({
          day: this.day, today: this.today, blocks: this.blocks, tags: this.tags, rowsScroller: this.calendarScroll,
          showScheduleRings: this.showScheduleRings,
          progress: Math.min(1, this.progress), detail: this.detail(), expanded: this.level > 0 || this.progress >= 1,
          month: this.month, rowHeight: this.rowHeight(), fullRowHeight: this.fullRowHeight(),
          maxRowsHeight: this.sizes.rowHeight + (this.sizes.calendarLimit - this.sizes.closedHeight) * Math.min(1, this.progress) +
            (this.availableHeight - this.sizes.calendarLimit) * this.detail(),
          onSelectDay: (day: number) => this.onSelectDay(day), onBrowseMonth: (month: number) => { this.month = month; },
          onOpenFullCalendar: () => this.requestLevel(2),
          onToday: () => { this.onSelectDay(this.today); this.calendarScroll.scrollTo({ xOffset: 0, yOffset: 0, animation: false }); },
          onToggle: () => this.requestLevel(this.level === 1 ? 0 : 1)
        })
      }.width('100%')
      .onAreaChange((_old: Area, area: Area) => { this.calendarHeight = Number(area.height); })
      this.Preview()
    }.width('100%').height(browseHeight(this.progress, this.sizes, this.availableHeight)).clip(true).backgroundColor(Colors.surface)
    .parallelGesture(PanGesture({ direction: PanDirection.Vertical, distance: 8 })
      .onActionStart((event: GestureEvent) => this.startDrag(event))
      .onActionUpdate((event: GestureEvent) => this.updateDrag(event))
      .onActionEnd((event: GestureEvent) => this.endDrag(event))
      .onActionCancel(() => this.cancelDrag()))
  }
}
