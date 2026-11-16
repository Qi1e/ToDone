import { Colors, Space } from '../common/Theme';
import { TimelineBlock, TimelineTag } from '../contracts/TimelineService';
import { localDayStart, weekPageOffset } from '../domain/TimelineLayout';
import { monthStart, monthWeekCount, TimelineCalendarRows, TIMELINE_WEEKDAYS } from './TimelineDatePicker';
import { BROWSE_TITLE_HEIGHT, BROWSE_WEEKDAYS_HEIGHT } from './TimelineBrowseMotion';


@Component
export struct TimelineBrowseCalendar {
  @Prop day: number;
  @Prop month: number;
  @Prop today: number;
  @Prop blocks: TimelineBlock[] = [];
  @Prop tags: TimelineTag[] = [];
  @Prop progress: number = 0;
  @Prop detail: number = 0;
  @Prop fullRowHeight: number = 80;
  @Prop expanded: boolean = false;
  @Prop rowHeight: number = 40;
  @Prop maxRowsHeight: number = 240;
  rowsScroller: Scroller = new Scroller();
  onSelectDay: (day: number) => void = () => {};
  onBrowseMonth: (month: number) => void = () => {};
  onOpenFullCalendar: () => void = () => {};
  onToday: () => void = () => {};
  onToggle: () => void = () => {};
  @State private page: number = 0;
  private controller: SwiperController = new SwiperController();

  private anchorFor(page: number): number {
    return this.expanded ? this.day : localDayStart(this.day, 7 * weekPageOffset(page, this.page));
  }

  private monthFor(page: number): number {
    if (page === this.page) return this.month;
    return this.expanded ? monthStart(this.month, weekPageOffset(page, this.page)) : monthStart(this.anchorFor(page));
  }

  private rowsHeight(): number {
    return this.rowHeight * (1 + (monthWeekCount(this.month) - 1) * this.progress);
  }

  private turn(page: number): void {
    const steps = weekPageOffset(page, this.page);
    if (steps === 0) return;
    this.page = page;
    if (this.expanded) {
      this.onBrowseMonth(monthStart(this.month, steps));
      this.rowsScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    } else {
      this.onSelectDay(localDayStart(this.day, steps * 7));
    }
  }

  @Builder
  private Page(page: number) {
    TimelineCalendarRows({ month: this.monthFor(page), anchorDay: this.anchorFor(page), day: this.day,
      today: this.today, blocks: this.blocks, tags: this.tags, expanded: this.expanded, progress: this.progress,
      detailedCalendar: true, prepareDetail: this.expanded && page === this.page,
      detail: page === this.page || this.detail === 1 ? this.detail : 0, fullRowHeight: this.fullRowHeight,
      rowHeight: this.rowHeight, onPick: (day: number) => this.onSelectDay(day) });
  }

  build() {
    Column() {
      Row() {
        Button() {
          Row({ space: Space.tiny }) {
            Text(new Date(this.month).getFullYear() + '年' + (new Date(this.month).getMonth() + 1) + '月')
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor(Colors.text);
            Text('▾').fontSize(12).fontColor(Colors.subText).rotate({ angle: 180 * this.progress });
          }
        }.height(BROWSE_TITLE_HEIGHT).padding(0).backgroundColor(Color.Transparent)
        .accessibilityText(this.detail > 0 ? '返回月历预览' : this.expanded ? '返回周视图' : '展开月历').onClick(() => this.onToggle());
        if (this.expanded) {
          Stack() {
            Button('全屏月历').height(BROWSE_TITLE_HEIGHT).width('100%').padding(0)
              .fontSize(14).fontColor(Colors.primary).backgroundColor(Color.Transparent)
              .opacity(Math.max(0, 1 - 2 * this.detail)).enabled(this.detail === 0)
              .accessibilityLevel(this.detail === 0 ? 'auto' : 'no-hide-descendants')
              .onClick(() => this.onOpenFullCalendar());
            Button('回今天').height(BROWSE_TITLE_HEIGHT).width('100%').padding(0)
              .fontSize(14).fontColor(Colors.primary).backgroundColor(Color.Transparent)
              .opacity(Math.max(0, 2 * this.detail - 1)).hitTestBehavior(this.detail === 1 ? HitTestMode.Default : HitTestMode.None)
              .accessibilityLevel(this.detail === 1 ? 'auto' : 'no-hide-descendants').onClick(() => this.onToday());
          }.width(76).height(BROWSE_TITLE_HEIGHT);
        }
        Blank();
        Row() {
          Button('‹').width(36).height(BROWSE_TITLE_HEIGHT).padding(0).fontSize(22).fontColor(Colors.text)
            .backgroundColor(Color.Transparent).accessibilityText('上个月').onClick(() => this.controller.showPrevious());
          Button('›').width(36).height(BROWSE_TITLE_HEIGHT).padding(0).fontSize(22).fontColor(Colors.text)
            .backgroundColor(Color.Transparent).accessibilityText('下个月').onClick(() => this.controller.showNext());
        }.opacity(this.progress).enabled(this.progress === 1 && this.expanded)
        .accessibilityLevel(this.expanded ? 'auto' : 'no-hide-descendants');
      }.width('100%').height(BROWSE_TITLE_HEIGHT).padding({ left: Space.small, right: Space.small });
      Row() {
        ForEach(TIMELINE_WEEKDAYS, (name: string) => {
          Text(name).layoutWeight(1).textAlign(TextAlign.Center).fontSize(12).fontColor(Colors.subText);
        }, (name: string) => name);
      }.width('100%').height(BROWSE_WEEKDAYS_HEIGHT);
      Scroll(this.rowsScroller) {
        Swiper(this.controller) {
          this.Page(0);
          this.Page(1);
          this.Page(2);
        }.width('100%').height(this.rowsHeight()).loop(true).indicator(false)
        .disableSwipe((this.progress > 0 && this.progress < 1) || (this.detail > 0 && this.detail < 1))
        .onChange((page: number) => this.turn(page));
      }.width('100%').height(Math.min(this.rowsHeight(), this.maxRowsHeight))
      .align(Alignment.Top).scrollBar(BarState.Off).edgeEffect(EdgeEffect.None)
      .enableScrollInteraction(this.progress === 1 && (this.detail === 0 || this.detail === 1));
    }.width('100%').padding({ left: 2 + 2 * this.progress, right: 2 + 2 * this.progress });
  }
}
