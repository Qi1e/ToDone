import { TimelineBlock, TimelineTag } from '../contracts/TimelineService';
import { gridMinute, layoutTimelineDay, localDayStart, timelineDayHeading, TimelineDayLayout, TimelineSegment } from '../domain/TimelineLayout';
import { Colors } from '../common/Theme';
import { DEFAULT_RING_COLOR } from '../domain/TimelineDayRing';
import { pad2 } from '../common/DateFormat';

const HOUR_HEIGHT = 72;
const RULER_WIDTH = 44;
const MIN_TOUCH_HEIGHT = 44;
const TITLE_MIN_HEIGHT = 12;
const TIME_MIN_HEIGHT = 36;
const HOURS: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
  12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23];

function clockText(stamp: number): string {
  const date = new Date(stamp);
  return pad2(date.getHours()) + ':' + pad2(date.getMinutes());
}

// 分档阈值和明度一起留在绘制层，分钟并集由领域层计算。
function columnTint(minutes: number): string {
  if (minutes >= 360) {
    return '#F8EBDC';
  }
  if (minutes >= 180) {
    return '#FBF3E7';
  }
  return minutes > 0 ? '#F0F7EF' : '#F7FAF7';
}

function segmentHeight(segment: TimelineSegment): number {
  return (segment.endMinute - segment.startMinute) * HOUR_HEIGHT / 60;
}

interface NoteHitArea {
  y: number;
  height: number;
}

// 短便签向空档借点击空间。两张便签间最多各借一半，不遮挡相邻日程。
function noteHitArea(segment: TimelineSegment, layout: TimelineDayLayout): NoteHitArea {
  const height = segmentHeight(segment);
  if (height >= MIN_TOUCH_HEIGHT) return { y: 0, height: height };
  let above = segment.startMinute;
  let below = 1440 - segment.endMinute;
  for (const other of layout.segments) {
    if (other === segment) continue;
    const sharesWidth = segment.lane * other.laneCount < (other.lane + 1) * segment.laneCount &&
      other.lane * segment.laneCount < (segment.lane + 1) * other.laneCount;
    if (!sharesWidth) continue;
    if (other.endMinute <= segment.startMinute) {
      above = Math.min(above, (segment.startMinute - other.endMinute) / 2);
    } else if (other.startMinute >= segment.endMinute) {
      below = Math.min(below, (other.startMinute - segment.endMinute) / 2);
    }
  }
  const extra = MIN_TOUCH_HEIGHT - height;
  const roomAbove = above * HOUR_HEIGHT / 60;
  const roomBelow = below * HOUR_HEIGHT / 60;
  const top = Math.min(roomAbove, Math.max(extra / 2, extra - roomBelow));
  return { y: -top, height: height + top + Math.min(roomBelow, extra - top) };
}

@Component
export struct TimelineGrid {
  @Prop @Watch('changeDay') day: number = Date.now();
  @Prop @Watch('refreshLayouts') blocks: TimelineBlock[] = [];
  @Prop @Watch('focusVisibleTime') focusAt: number = 0;
  @Prop selectedId: string = '';
  @Prop bottomInset: number = 0;
  @Prop selectedStartAt: number = 0;
  @Prop tags: TimelineTag[] = [];
  @Prop today: number = localDayStart(Date.now());
  onSelect: (block: TimelineBlock) => void = () => {};
  @State private layouts: TimelineDayLayout[] = [];
  private scroller: Scroller = new Scroller();
  private scrollReady: boolean = false;

  aboutToAppear(): void {
    this.refreshLayouts();
  }

  private refreshLayouts(): void {
    this.layouts = [layoutTimelineDay(this.day, this.blocks),
      layoutTimelineDay(localDayStart(this.day, 1), this.blocks)];
  }

  private changeDay(): void {
    this.refreshLayouts();
    this.focusVisibleTime();
  }

  private targetOffset(): number {
    if (this.layouts.length < 2) {
      return HOUR_HEIGHT * 8;
    }
    let minute = 8 * 60;
    if (this.focusAt > 0 && this.focusAt >= this.layouts[0].day && this.focusAt < this.layouts[1].nextDay) {
      minute = gridMinute(this.focusAt);
    } else {
      for (const layout of this.layouts) {
        if (layout.segments.length > 0) {
          minute = layout.segments[0].startMinute;
          break;
        }
      }
    }
    return Math.max(0, minute - 15) * HOUR_HEIGHT / 60;
  }

  private focusVisibleTime(): void {
    if (this.scrollReady) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: this.targetOffset(), animation: false });
    }
  }

  @Builder
  private dayHeader(index: number) {
    Text(timelineDayHeading(this.layouts[index].day, this.today))
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(Colors.text)
      .maxLines(1)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(40)
      .backgroundColor(columnTint(this.layouts[index].busyMinutes));
  }

  @Builder
  private ruler() {
    Column() {
      ForEach(HOURS, (hour: number) => {
        Text(pad2(hour) + ':00')
          .fontSize(11)
          .fontColor(Colors.subText)
          .textAlign(TextAlign.End)
          .align(Alignment.TopEnd)
          .padding({ right: 5 })
          .width(RULER_WIDTH)
          .height(HOUR_HEIGHT);
      }, (hour: number) => hour.toString());
    }
    .width(RULER_WIDTH);
  }

  private noteColor(tagId?: string): string {
    const tag = this.tags.find((item: TimelineTag) => item.id === tagId);
    return tag ? tag.color : DEFAULT_RING_COLOR;
  }

  private selected(block: TimelineBlock): boolean {
    return block.id === this.selectedId && (block.occurrenceOriginalStart ?? block.startAt) === this.selectedStartAt;
  }

  @Builder
  private note(segment: TimelineSegment, day: number, height: number, hit: NoteHitArea, color: string) {
    Column() {
      if (height >= TITLE_MIN_HEIGHT) {
        Text(segment.block.title)
          .fontSize(height >= 18 ? 13 : 10)
          .lineHeight(height >= 18 ? 15 : 11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
          .width('100%');
      }
      if (height >= TIME_MIN_HEIGHT) {
        Text(clockText(segment.block.startAt) + '–' + clockText(segment.block.endAt))
          .fontSize(11)
          .lineHeight(14)
          .fontColor(Colors.subText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
          .width('100%');
      }
    }
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: segment.laneCount > 2 ? 3 : 7, right: 3, top: height >= 44 ? 5 : 0 })
    .width((100 / segment.laneCount) + '%')
    .height(height)
    .backgroundColor((day === this.today ? '#43' : '#28') + color.substring(1))
    .borderWidth({ top: height < 18 ? Math.min(height, 1) : 3, left: this.selected(segment.block) ? 1.5 : 0,
      right: this.selected(segment.block) ? 1.5 : (segment.laneCount > 1 ? 0.5 : 0),
      bottom: this.selected(segment.block) ? 1.5 : 0 })
    .borderColor(this.selected(segment.block) || day === this.today ? color : '#C9' + color.substring(1))
    .borderRadius(Math.min(height / 2, 6))
    .clip(true)
    .position({ x: (100 * segment.lane / segment.laneCount) + '%', y: segment.startMinute * HOUR_HEIGHT / 60 })
    .responseRegion({ x: 0, y: hit.y, width: '100%', height: hit.height })
    .accessibilityGroup(true)
    .accessibilityText(segment.block.title + '，' + clockText(segment.block.startAt) + '至' + clockText(segment.block.endAt))
    .onClick(() => this.onSelect(segment.block));
  }

  @Builder
  private dayColumn(index: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        ForEach(HOURS, (hour: number) => {
          Row()
            .width('100%')
            .height(HOUR_HEIGHT)
            .border({ width: { top: 0.5 }, color: Colors.border });
        }, (hour: number) => hour.toString());
      }
      .width('100%');
      ForEach(this.layouts[index].segments, (segment: TimelineSegment) => {
        this.note(segment, this.layouts[index].day, segmentHeight(segment), noteHitArea(segment, this.layouts[index]),
          this.noteColor(segment.block.tagId));
      }, (segment: TimelineSegment) => this.layouts[index].day + ':' + JSON.stringify(segment));
    }
    .layoutWeight(1)
    .height(HOUR_HEIGHT * HOURS.length)
    .border({ width: { left: 0.5 }, color: Colors.border })
    .backgroundColor(columnTint(this.layouts[index].busyMinutes))
    .clip(true);
  }

  build() {
    Column() {
      if (this.layouts.length === 2) {
        Row() {
          Row().width(RULER_WIDTH);
          this.dayHeader(0);
          this.dayHeader(1);
        }
        .width('100%');
        Scroll(this.scroller) {
          Row() {
            this.ruler();
            this.dayColumn(0);
            this.dayColumn(1);
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding({ bottom: this.bottomInset });
        }
        .layoutWeight(1)
        .width('100%')
        .initialOffset({ yOffset: this.targetOffset() })
        .onAreaChange(() => { this.scrollReady = true; })
        .scrollBar(BarState.Auto);
      }
    }
    .width('100%')
    .height('100%');
  }
}
