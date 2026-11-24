import { matterErrorMessage } from '../domain/MatterSnapshot';
import { dayOccurrenceStartForMatter } from '../domain/MatterSchedule';
import { timelineDayHeading } from '../domain/TimelineLayout';
import { unifiedDataChannel } from '@kit.ArkData';
import { AnimatorResult, LengthMetrics, router } from '@kit.ArkUI';
import { MatterServices } from '../application/MatterServices';
import { MatterService } from '../contracts/MatterService';
import {
  Colors,
  Radius,
  Space,
  TABULAR_NUMS,
  TypeSize,
  TypeWeight,
  resolveClusterColor,
  resolveClusterTint
} from '../common/Theme';
import { MODULE_OPTIONS } from '../model/Defaults';
import { Matter, ModuleInstance, ModuleOption, ModuleType } from '../model/Types';
import { MatterStore } from '../store/MatterStore';
import { Chip } from './Chip';
import { CardStackLayout, DeckLocation, DECK_PAN_SLOP, deckDragDistance } from './CardStackLayout';
import { DOCK_CLEARANCE } from './HomeNavigation';

const MATTER_DRAG_TYPE: string = 'ApplicationDefined.ToDoneMatter';

@Component
export struct MatterCardDeck {
  @Prop @Watch('returnToDeck') revision: number = 0;
  @Prop @Watch('searchChanged') searchOpen: boolean = false;
  @Prop @Watch('filterArgsChanged') filterActive: boolean = false;
  @Prop @Watch('filterArgsChanged') selectedDay: number = 0;
  @Prop @Watch('filterArgsChanged') today: number = 0;
  @Prop @Watch('resizeDeck') pageHeight: number = 0;
  @Prop @Watch('returnToFront') homeRequest: number = 0;
  onBrowseChange: (awayFromFront: boolean) => void = () => {};
  onClearDateFilter: () => void = () => {};
  onFilterToday: () => void = () => {};
  @State private cards: Matter[] = [];
  @State private searchText: string = '';
  @State private searchFocused: boolean = false;
  @State private showArchived: boolean = false;
  @State private pendingDeleteMatterId: string = '';
  @State private pendingReset: boolean = false;
  @State private addingExamples: boolean = false;
  @State private dragSourceMatterId: string = '';
  @State private dragTargetMatterId: string = '';
  @State private at: DeckLocation = { index: 0, reading: 0, turn: 0, endLift: 0 };
  @State private layout: CardStackLayout = new CardStackLayout(0, DOCK_CLEARANCE, [], 0);
  private heights: Map<string, number> = new Map<string, number>();
  private deckHeight: number = 0;
  private deckOffset: number = 0;
  @State private savingMatter: boolean = false;
  private store: MatterStore = MatterStore.getInstance();
  private service: MatterService = MatterServices.getService();
  private matters: Matter[] = [];
  private anim?: AnimatorResult;
  private snapTarget: number = 0;
  private suppressTap: boolean = false;
  private caughtAnimation: boolean = false;
  private dragStart: number = 0;
  private lastDragDistance: number = 0;
  private panning: boolean = false;
  private generation: number = 0;

  aboutToAppear(): void {
    this.refresh();
  }

  aboutToDisappear(): void {
    this.stopAnimation();
  }

  private returnToDeck(): void {
    const existingIds = new Set<string>();
    this.matters.forEach((matter: Matter) => { existingIds.add(matter.id); });
    this.refresh();
    if (!this.searchOpen && !this.showArchived) {
      const created = this.cards.findIndex((matter: Matter) => !existingIds.has(matter.id));
      if (created >= 0) this.moveTo(this.layout.start(created));
    }
  }

  private filterArgsChanged(): void {
    this.refresh();
  }

  private refresh(preserveIndex: boolean = false): void {
    if (this.showArchived) {
      this.matters = this.service.archivedMatters();
    } else if (this.searchText.trim().length > 0) {
      this.matters = this.service.activeMatters();
    } else if (this.filterActive && this.selectedDay > 0) {
      this.matters = this.service.mattersForDay(this.selectedDay);
    } else {
      this.matters = this.service.residentActiveMatters();
    }
    this.filterMatters(preserveIndex);
  }

  private searchChanged(): void {
    if (this.searchOpen) return;
    this.searchText = '';
    this.showArchived = false;
    this.pendingReset = false;
    this.refresh();
  }

  private filterMatters(preserveIndex: boolean = false): void {
    const index = this.at.index;
    const id = this.cards[index]?.id;
    const keyword = this.searchText.trim();
    const basePool = keyword.length > 0
      ? (this.showArchived ? this.service.archivedMatters() : this.service.activeMatters())
      : this.matters;
    const filtered = keyword.length === 0 ? basePool : basePool.filter((matter: Matter) => {
      const tagName = this.store.matterTag(matter)?.name ?? '';
      return matter.title.includes(keyword) ||
        tagName.includes(keyword) ||
        this.store.getNote(matter.id).includes(keyword);
    });
    this.stopAnimation();
    this.panning = false;
    const fallback = Math.max(0, Math.min(index, filtered.length - 1));
    const retained = preserveIndex ? fallback : filtered.findIndex((matter: Matter) => matter.id === id);
    const previous = this.at;
    this.generation++;
    this.cards = filtered;
    this.rebuildLayout();
    this.moveTo(retained >= 0 ? this.layout.offsetAt(retained, previous.reading, previous.turn) : this.layout.start(fallback));
  }

  private rebuildLayout(): void {
    this.layout = new CardStackLayout(this.deckHeight, DOCK_CLEARANCE,
      this.cards.map((matter: Matter) => this.heights.get(matter.id) ?? 0), this.pageHeight);
  }

  private resizeDeck(): void {
    const previous = this.at;
    const oldOffset = this.deckOffset;
    const wasAtEnd = (oldOffset > 0 || previous.endLift > 0) && oldOffset === this.layout.limit;
    const landing = this.anim ? this.layout.locate(this.snapTarget) : undefined;
    const snappingToEnd = !!landing && this.snapTarget === this.layout.limit;
    this.stopAnimation();
    this.rebuildLayout();
    this.moveTo(wasAtEnd ? this.layout.limit + previous.endLift :
      this.layout.offsetAt(previous.index, previous.reading, previous.turn));
    if (this.panning) this.dragStart += this.deckOffset - oldOffset;
    else if (landing) this.snapTo(snappingToEnd ? this.layout.limit :
      this.layout.offsetAt(landing.index, landing.reading, landing.turn));
  }

  private measureCard(id: string, height: number): void {
    const measured = Math.ceil(height) + 2;
    if (height <= 0 || this.heights.get(id) === measured) return;
    this.heights.set(id, measured);
    this.resizeDeck();
  }

  private moveTo(value: number): void {
    const wasAway = this.deckOffset > 0;
    this.deckOffset = this.layout.clamp(value);
    this.at = this.layout.locate(value);
    if (wasAway !== (this.deckOffset > 0)) this.onBrowseChange(this.deckOffset > 0);
  }

  private returnToFront(): void {
    this.stopAnimation();
    this.panning = false;
    this.moveTo(0);
  }

  private stopAnimation(): void {
    const previous = this.anim;
    this.anim = undefined;
    previous?.cancel();
  }

  private snapTo(target: number): void {
    this.stopAnimation();
    target = this.layout.clamp(target);
    const from = this.deckOffset + this.at.endLift;
    const distance = Math.abs(target - from);
    if (distance < 0.5) {
      this.moveTo(target);
      return;
    }
    const returning = this.at.endLift > 0;
    const duration = returning ? 205 + this.at.endLift * 1.6 : 140 + Math.min(120, distance * 0.55);
    const anim = this.getUIContext().createAnimator({ duration: Math.round(duration),
      easing: returning ? 'cubic-bezier(0.25, 0.62, 0.28, 1)' : 'cubic-bezier(0.2, 0.74, 0.3, 1)',
      delay: 0, fill: 'forwards', direction: 'normal', iterations: 1, begin: from, end: target });
    this.snapTarget = target;
    this.anim = anim;
    anim.onFrame = (value: number) => { if (this.anim === anim) this.moveTo(value); };
    anim.onFinish = () => {
      if (this.anim === anim) {
        this.anim = undefined;
        this.moveTo(target);
      }
    };
    anim.play();
  }

  private deckTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.caughtAnimation = this.anim !== undefined;
      this.suppressTap = this.caughtAnimation;
      this.stopAnimation();
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.caughtAnimation && !this.panning) {
        this.caughtAnimation = false;
        this.snapTo(this.layout.release(this.deckOffset, this.deckOffset, 0));
      }
      // 吃掉当前触摸序列的点击后，键盘和无障碍操作仍可立即使用。
      if (this.suppressTap) {
        setTimeout(() => { if (!this.panning && !this.caughtAnimation) this.suppressTap = false; }, 0);
      }
    }
  }

  private startPan(event: GestureEvent): void {
    if (this.dragSourceMatterId || this.cards.length === 0) return;
    this.stopAnimation();
    this.dragStart = this.deckOffset;
    this.lastDragDistance = 0;
    this.panning = true;
    this.suppressTap = true;
    this.caughtAnimation = false;
    this.updatePan(event);
  }

  private updatePan(event: GestureEvent): void {
    if (!this.panning) return;
    const distance = deckDragDistance(event.offsetY);
    this.moveTo(this.layout.dragBy(this.deckOffset + this.at.endLift, this.lastDragDistance - distance));
    this.lastDragDistance = distance;
  }

  private endPan(velocity: number): void {
    if (!this.panning) return;
    this.panning = false;
    this.snapTo(this.layout.release(this.deckOffset, this.dragStart, -velocity));
  }

  private openMatter(matter: Matter): void {
    if (this.suppressTap || MatterServices.isPreview()) return;
    const occStart = this.filterActive
      ? dayOccurrenceStartForMatter(this.store.readState(), matter.id, this.selectedDay)
      : undefined;
    router.pushUrl({
      url: 'pages/MatterDetail',
      params: { matterId: matter.id, occurrenceStart: occStart }
    });
  }

  private editMatterDirect(matter: Matter): void {
    if (this.suppressTap || MatterServices.isPreview()) return;
    const occStart = this.filterActive
      ? dayOccurrenceStartForMatter(this.store.readState(), matter.id, this.selectedDay)
      : undefined;
    router.pushUrl({
      url: 'pages/CreateMatter',
      params: { matterId: matter.id, occurrenceStart: occStart }
    });
  }

  private async perform(write: () => Promise<void>): Promise<void> {
    if (this.savingMatter) return;
    this.savingMatter = true;
    try {
      await write();
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: matterErrorMessage(error as Error), duration: 3000 });
    } finally {
      this.savingMatter = false;
    }
  }

  private showNotice(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500, bottom: DOCK_CLEARANCE });
  }

  private refreshCards(action: string): void {
    this.showNotice(MatterServices.requestCardRefresh(action).message);
  }

  private moveMatter(id: string, delta: number): void {
    if (this.suppressTap || this.showArchived || MatterServices.isPreview()) return;
    const index = this.matters.findIndex((matter: Matter) => matter.id === id);
    if (index < 0 || index + delta < 0 || index + delta >= this.matters.length) return;
    this.perform(async (): Promise<void> => {
      await this.store.moveMatterByDelta(id, delta);
      this.pendingDeleteMatterId = '';
      this.refresh(true);
      this.refreshCards('已调整排序');
    });
  }

  private async addExamples(): Promise<void> {
    if (this.addingExamples || MatterServices.isPreview()) return;
    this.addingExamples = true;
    try {
      const added = await this.store.addDeckExamples();
      this.refresh(true);
      this.showNotice(added > 0 ? `已补充 ${added} 张示例卡片` : '示例卡片已齐全');
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: '示例保存未确认，请点「补充示例」重试' });
    } finally {
      this.addingExamples = false;
    }
  }

  private startMatterDrag(matterId: string, event: DragEvent): DragItemInfo {
    this.suppressTap = true;
    this.panning = false;
    this.stopAnimation();
    this.dragSourceMatterId = matterId;
    this.dragTargetMatterId = '';
    const record = new unifiedDataChannel.UnifiedRecord(MATTER_DRAG_TYPE, matterId);
    event.setData(new unifiedDataChannel.UnifiedData(record));
    return {};
  }

  private finishMatterDrop(targetId: string, event: DragEvent): void {
    try {
      const records = event.getData().getRecords();
      const record = records.length > 0 ? records[0] : undefined;
      const value = record ? record.getValue() : undefined;
      const sourceId = record && record.getType() === MATTER_DRAG_TYPE && typeof value === 'string' ? value : '';
      if (sourceId.length > 0 && sourceId !== targetId) {
        this.perform(async (): Promise<void> => {
          await this.store.createOrJoinCluster(sourceId, targetId);
          this.refresh();
          this.refreshCards('已建立关联');
        });
      }
    } catch (error) {
    }
    this.clearMatterDrag();
  }

  private clearMatterDrag(): void {
    this.dragSourceMatterId = '';
    this.dragTargetMatterId = '';
    this.snapTo(this.layout.release(this.deckOffset, this.deckOffset, 0));
  }

  private previewClusterRaw(target: Matter): string | undefined {
    if (target.clusterId) {
      return this.store.clusterColor(target.clusterId);
    }
    if (this.dragSourceMatterId.length > 0) {
      const source = this.store.findMatter(this.dragSourceMatterId);
      if (source?.clusterId) {
        return this.store.clusterColor(source.clusterId);
      }
    }
    return 'cluster.pine';
  }

  private cardBorder(matter: Matter): BorderOptions {
    if (this.dragSourceMatterId === matter.id) {
      return {
        width: 1,
        color: Colors.dash,
        style: BorderStyle.Dashed,
        radius: Radius.card
      };
    }
    const isTarget = this.dragTargetMatterId === matter.id;
    const barColor = isTarget
      ? (resolveClusterColor(this.previewClusterRaw(matter)) ?? $r('app.color.cluster_pine'))
      : (matter.clusterId ? resolveClusterColor(this.store.clusterColor(matter.clusterId)) : undefined);
    if (barColor) {
      return {
        width: { left: 3, top: 1, right: 1, bottom: 1 },
        color: { left: barColor, top: Colors.hairline, right: Colors.hairline, bottom: Colors.hairline },
        radius: Radius.card
      };
    }
    return {
      width: 1,
      color: Colors.hairline,
      radius: Radius.card
    };
  }

  @Builder
  private FilterStatusBar() {
    Row({ space: Space.xs }) {
      if (this.filterActive) {
        Text(`${timelineDayHeading(this.selectedDay, this.today)} · ${this.cards.length} 项`)
          .fontSize(TypeSize.meta)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink)
          .fontFeature(TABULAR_NUMS)
          .layoutWeight(1);
        Button('× 返回全部', { type: ButtonType.Normal })
          .height(28)
          .padding({ left: Space.sm, right: Space.sm })
          .fontSize(TypeSize.meta)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink)
          .backgroundColor(Colors.wash)
          .borderRadius(Radius.chip)
          .onClick(() => this.onClearDateFilter());
      } else {
        Text(`全部常驻 · ${this.cards.length}`)
          .fontSize(TypeSize.meta)
          .fontWeight(TypeWeight.regular)
          .fontColor(Colors.inkMuted)
          .fontFeature(TABULAR_NUMS)
          .layoutWeight(1);
        if (this.store.todayLightScheduleCount(this.today) > 0) {
          Button(`今日 ${this.store.todayLightScheduleCount(this.today)} 项日程 · 查看 ›`, { type: ButtonType.Normal })
            .height(28)
            .padding({ left: Space.sm, right: Space.sm })
            .fontSize(TypeSize.meta)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink)
            .backgroundColor(Colors.wash)
            .borderRadius(Radius.chip)
            .fontFeature(TABULAR_NUMS)
            .onClick(() => this.onFilterToday());
        } else {
          Button('点日期查看当日日程', { type: ButtonType.Normal })
            .height(28)
            .padding({ left: Space.xs, right: Space.xs })
            .fontSize(TypeSize.meta)
            .fontWeight(TypeWeight.regular)
            .fontColor(Colors.inkMuted)
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.chip)
            .onClick(() => this.onFilterToday());
        }
      }
    }
    .width('100%')
    .height(34)
    .padding({ left: Space.page, right: Space.page })
    .alignItems(VerticalAlign.Center);
  }

  build() {
    Column() {
      if (this.searchOpen) {
        this.SearchBar()
      } else if (!this.showArchived) {
        this.FilterStatusBar()
      }
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.cards.length === 0) {
          Column({ space: Space.sm }) {
            Text(this.searchText.trim()
              ? '没有匹配的事项'
              : this.showArchived
                ? '还没有归档事项'
                : this.filterActive
                  ? '这天暂无日程或截止事项'
                  : '还没有常驻事项')
              .textAlign(TextAlign.Center)
              .fontSize(TypeSize.bodySmall)
              .fontColor(Colors.inkSoft);
            if (this.filterActive && !this.searchText.trim()) {
              Button('返回全部事项', { type: ButtonType.Normal })
                .constraintSize({ minHeight: 36 })
                .padding({ left: Space.md, right: Space.md })
                .fontSize(TypeSize.bodySmall)
                .fontWeight(TypeWeight.semibold)
                .fontColor(Colors.ink)
                .backgroundColor(Colors.wash)
                .borderRadius(Radius.chip)
                .onClick(() => this.onClearDateFilter());
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .position({ x: 0, y: Math.max(0, (this.layout.viewport - DOCK_CLEARANCE) / 2 - 28) })
        } else {
          Stack({ alignContent: Alignment.TopStart }) {
            ForEach(this.layout.visibleSlots(this.at), (index: number) => {
              Stack({ alignContent: Alignment.TopStart }) {
                this.Card(this.cards[index], index)
              }.width('100%').height(this.layout.paintHeight(index, this.at)).clip(true)
              .position({ x: 0, y: this.layout.paintTop(index, this.at) }).zIndex(index)
              .hitTestBehavior(HitTestMode.Transparent)
              .accessibilityLevel(this.layout.paintHeight(index, this.at) > 0 ? 'auto' : 'no-hide-descendants')
            }, (index: number) => this.cards[index].id + ':' + index + ':' + this.generation)
          }.width('100%').height('100%').translate({ y: -this.at.endLift })
        }
      }.width('100%').layoutWeight(1).clip(true)
      .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
        const height = Number(size.height);
        if (height <= 0 || height === this.deckHeight) return;
        this.deckHeight = height;
        this.resizeDeck();
      })
      .onTouch((event: TouchEvent) => this.deckTouch(event))
      .priorityGesture(PanGesture({ direction: PanDirection.Vertical, distance: DECK_PAN_SLOP })
        .onActionStart((event: GestureEvent) => this.startPan(event))
        .onActionUpdate((event: GestureEvent) => this.updatePan(event))
        .onActionEnd((event: GestureEvent) => { this.updatePan(event); this.endPan(event.velocityY); })
        .onActionCancel(() => this.endPan(0)))
    }.width('100%').height('100%')
  }

  @Builder
  private Card(matter: Matter, index: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Row().width('100%').height('100%').backgroundColor(Colors.ink)
        .opacity(Math.min(0.16, Math.max(0, -this.layout.depthAt(index, this.at)) * 0.05))
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      Scroll() {
        this.MatterRow(matter, index)
      }.enableScrollInteraction(false).scrollBar(BarState.Off).edgeEffect(EdgeEffect.None)
      .width('100%').height('100%').align(Alignment.TopStart)
    }.width('92%').height(this.layout.faceHeight(index))
    .constraintSize({ minHeight: this.layout.faceHeight(index) })
    .backgroundColor(this.dragTargetMatterId === matter.id
      ? resolveClusterTint(this.previewClusterRaw(matter))
      : Colors.card)
    .borderRadius(Radius.card).clip(true)
    .border(this.cardBorder(matter))
    .scale({ x: this.layout.widthScaleAt(this.layout.depthAt(index, this.at)), y: 1 })
    .rotate({ x: 1, y: 0, z: 0, centerY: '0%',
      angle: -this.layout.tiltAt(this.layout.depthAt(index, this.at)) })
    .opacity(this.layout.opacityAt(this.layout.depthAt(index, this.at)))
    .hitTestBehavior(this.layout.opacityAt(this.layout.depthAt(index, this.at)) > 0 ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(this.layout.opacityAt(this.layout.depthAt(index, this.at)) > 0 ? 'auto' : 'no-hide-descendants')
    .position({ x: '4%', y: this.layout.sheetTop(index, this.at) - this.layout.paintTop(index, this.at) })
    .draggable(!MatterServices.isPreview())
    .onDragStart((event: DragEvent) => this.startMatterDrag(matter.id, event))
    .onDragEnter(() => {
      if (this.dragSourceMatterId !== matter.id) {
        this.dragTargetMatterId = matter.id;
      }
    })
    .onDragLeave(() => {
      if (this.dragTargetMatterId === matter.id) {
        this.dragTargetMatterId = '';
      }
    })
    .onDrop((event: DragEvent) => { if (!MatterServices.isPreview()) this.finishMatterDrop(matter.id, event); })
    .onDragEnd(() => this.clearMatterDrag());
  }

  @Builder
  private SearchBar() {
    Column({ space: Space.md }) {
      Column() {
        TextInput({ placeholder: '搜索事项', text: this.searchText })
          .width('100%')
          .constraintSize({ minHeight: 38 })
          .fontSize(TypeSize.body)
          .fontWeight(TypeWeight.regular)
          .fontColor(Colors.ink)
          .placeholderColor(Colors.inkMuted)
          .caretColor(Colors.red)
          .backgroundColor(Color.Transparent)
          .padding({ left: Space.md, right: Space.md })
          .onFocus(() => { this.searchFocused = true; })
          .onBlur(() => { this.searchFocused = false; })
          .onChange((value: string) => {
            this.searchText = value;
            this.filterMatters();
          });
        Column()
          .width('100%')
          .height(2)
          .backgroundColor(this.searchFocused ? Colors.ink : Color.Transparent);
      }
      .width('100%')
      .backgroundColor(Colors.wash)
      .borderRadius(Radius.card)
      .clip(true);

      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(Space.sm), cross: LengthMetrics.vp(Space.xs) } }) {
        Button(this.showArchived ? '显示未归档' : '显示归档')
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 40 })
          .fontSize(TypeSize.body)
          .fontWeight(this.showArchived ? TypeWeight.semibold : TypeWeight.regular)
          .fontColor(this.showArchived ? Colors.ink : Colors.inkSoft)
          .backgroundColor(this.showArchived ? Colors.wash : Color.Transparent)
          .borderRadius(Radius.chip)
          .padding({ left: Space.md, right: Space.md })
          .onClick(() => {
            this.showArchived = !this.showArchived;
            this.refresh();
          });
        Button('补充示例')
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 40 })
          .fontSize(TypeSize.body)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink)
          .backgroundColor(Colors.wash)
          .borderRadius(Radius.card)
          .padding({ left: Space.md, right: Space.md })
          .opacity(!this.addingExamples && !MatterServices.isPreview() ? 1 : 0.4)
          .enabled(!this.addingExamples && !MatterServices.isPreview()).onClick(() => this.addExamples())
        Button(this.pendingReset ? '确认重置' : '重置演示数据')
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 40 })
          .enabled(!MatterServices.isPreview())
          .opacity(MatterServices.isPreview() ? 0.4 : 1)
          .fontSize(TypeSize.body)
          .fontWeight(this.pendingReset ? TypeWeight.semibold : TypeWeight.regular)
          .fontColor(this.pendingReset ? Colors.red : Colors.inkSoft)
          .backgroundColor(Color.Transparent)
          .borderRadius(Radius.card)
          .padding({ left: Space.md, right: Space.md })
          .onClick(() => {
            this.perform(async (): Promise<void> => {
              if (!this.pendingReset) {
                this.pendingReset = true;
                this.showNotice('再次点击确认重置演示数据');
                return;
              }
              await this.store.resetDemoData();
              this.pendingReset = false;
              this.pendingDeleteMatterId = '';
              this.refresh();
              this.refreshCards('已重置演示数据');
            });
          });
      }
    }.width('100%').padding({ left: Space.page, right: Space.page, top: Space.sm, bottom: Space.sm })
  }

  @Builder
  private MatterRow(matter: Matter, index: number) {
    Column({ space: Space.sm }) {
      Column({ space: Space.xs }) {
        Row({ space: Space.sm }) {
          Text(matter.title)
            .fontSize(TypeSize.title)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          if (this.store.matterTag(matter)) {
            Row({ space: 4 }) {
              Column()
                .width(8)
                .height(8)
                .borderRadius(4)
                .backgroundColor(this.store.matterTag(matter)?.color ?? Colors.ink);
              Text(this.store.matterTag(matter)?.name ?? '')
                .fontSize(TypeSize.meta)
                .fontWeight(TypeWeight.regular)
                .fontColor(Colors.inkSoft);
            }
            .padding({ left: Space.xs, right: Space.xs, top: 2, bottom: 2 })
            .backgroundColor(Colors.wash)
            .borderRadius(Radius.chip)
            .alignItems(VerticalAlign.Center);
          }
          if (matter.clusterId) {
            Row({ space: Space.xs }) {
              Column()
                .width(8)
                .height(8)
                .borderRadius(4)
                .backgroundColor(resolveClusterColor(this.store.clusterColor(matter.clusterId)) ?? Colors.ink);
              Text('弱关联')
                .fontSize(TypeSize.meta)
                .fontWeight(TypeWeight.regular)
                .fontColor(Colors.inkMuted);
            }
            .alignItems(VerticalAlign.Center);
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);

        Column({ space: Space.xs }) {
          Text(this.store.cardPrimaryText(matter))
            .fontSize(TypeSize.bodySmall)
            .fontColor(Colors.inkSoft)
            .fontFeature(TABULAR_NUMS)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.dragTargetMatterId === matter.id ? '松手加入关联' : this.store.moduleSummary(matter))
            .fontSize(TypeSize.meta)
            .fontColor(this.dragTargetMatterId === matter.id ? Colors.inkSoft : Colors.inkMuted)
            .fontFeature(TABULAR_NUMS)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      .width('100%').alignItems(HorizontalAlign.Start)
      .accessibilityGroup(true).accessibilityText('打开' + matter.title)
      .onClick(() => this.openMatter(matter));

      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(Space.xs), cross: LengthMetrics.vp(Space.xs) } }) {
        ForEach(this.visibleModulesFor(matter).slice(0, 5), (module: ModuleInstance) => {
          Chip({ text: this.moduleText(module), selected: false });
        }, (module: ModuleInstance) => module.id);
      }.accessibilityLevel(index < this.at.index ? 'no-hide-descendants' : 'auto')

      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Button('打开')
          .type(ButtonType.Normal)
          .fontSize(TypeSize.body)
          .fontWeight(TypeWeight.semibold)
          .constraintSize({ minHeight: 40 })
          .padding({ left: Space.sm, right: Space.sm })
          .fontColor(Colors.ink)
          .backgroundColor(Color.Transparent)
          .borderRadius(Radius.card)
          .margin({ right: Space.xs })
          .onClick(() => this.openMatter(matter));
        Button('编辑')
          .type(ButtonType.Normal)
          .fontSize(TypeSize.body)
          .fontWeight(TypeWeight.regular)
          .constraintSize({ minHeight: 40 })
          .padding({ left: Space.sm, right: Space.sm })
          .fontColor(Colors.inkSoft)
          .backgroundColor(Color.Transparent)
          .borderRadius(Radius.card)
          .margin({ right: Space.xs })
          .onClick(() => this.editMatterDirect(matter));
        if (!this.filterActive) {
          Button('上移')
            .type(ButtonType.Normal)
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.regular)
            .constraintSize({ minHeight: 40 })
            .padding({ left: Space.sm, right: Space.sm })
            .fontColor(Colors.inkSoft)
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .margin({ right: Space.xs })
            .onClick(() => this.moveMatter(matter.id, -1));
          Button('下移')
            .type(ButtonType.Normal)
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.regular)
            .constraintSize({ minHeight: 40 })
            .padding({ left: Space.sm, right: Space.sm })
            .fontColor(Colors.inkSoft)
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .margin({ right: Space.xs })
            .onClick(() => this.moveMatter(matter.id, 1));
        }
        if (matter.clusterId) {
          Button('移出簇')
            .type(ButtonType.Normal)
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.regular)
            .constraintSize({ minHeight: 40 })
            .padding({ left: Space.sm, right: Space.sm })
            .fontColor(Colors.inkSoft)
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .margin({ right: Space.xs })
            .onClick(() => {
              this.perform(async (): Promise<void> => {
                if (this.suppressTap) return;
                await this.store.detachCluster(matter.id);
                this.pendingDeleteMatterId = '';
                this.refresh();
                this.refreshCards('已移出弱关联');
              });
            });
        }
        Button(matter.archived ? '恢复' : '归档')
          .type(ButtonType.Normal)
          .fontSize(TypeSize.body)
          .fontWeight(TypeWeight.regular)
          .constraintSize({ minHeight: 40 })
          .padding({ left: Space.sm, right: Space.sm })
          .fontColor(Colors.inkSoft)
          .backgroundColor(Color.Transparent)
          .borderRadius(Radius.card)
          .margin({ right: Space.xs })
          .onClick(() => {
            this.perform(async (): Promise<void> => {
              if (this.suppressTap) return;
              const wasArchived = matter.archived;
              await this.store.archiveMatter(matter.id, !matter.archived);
              this.pendingDeleteMatterId = '';
              this.refresh();
              this.refreshCards(wasArchived ? '已恢复事项' : '已归档事项');
            });
          });
        Button(this.pendingDeleteMatterId === matter.id ? '确认删除' : '删除')
          .type(ButtonType.Normal)
          .fontSize(TypeSize.body)
          .fontWeight(TypeWeight.semibold)
          .constraintSize({ minHeight: 40 })
          .padding({ left: Space.sm, right: Space.sm })
          .fontColor(Colors.red)
          .backgroundColor(Color.Transparent)
          .borderRadius(Radius.card)
          .onClick(() => {
            this.perform(async (): Promise<void> => {
              if (this.suppressTap) return;
              if (this.pendingDeleteMatterId !== matter.id) {
                this.pendingDeleteMatterId = matter.id;
                this.showNotice(`再次点击确认删除「${matter.title}」`);
                return;
              }
              await this.store.deleteMatter(matter.id);
              this.pendingDeleteMatterId = '';
              this.refresh();
              this.refreshCards('已删除事项');
            });
          });
      }
      .width('100%')
      .padding({ top: Space.xs })
      .border({ width: { top: 1 }, color: Colors.hairline })
      .accessibilityLevel(index < this.at.index ? 'no-hide-descendants' : 'auto')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: Space.lg, right: Space.lg, top: Space.lg, bottom: Space.sm })
    .onSizeChange((_old: SizeOptions, size: SizeOptions) => this.measureCard(matter.id, Number(size.height)))
    .enabled(!MatterServices.isPreview());
  }

  private moduleText(module: ModuleInstance): string {
    if (module.moduleType === ModuleType.Deadline) return this.store.countdownText(module.matterId);
    if (module.moduleType === ModuleType.Counter || module.moduleType === ModuleType.EventRecord) {
      return this.store.counterSummaryText(module.matterId);
    }
    if (module.moduleType === ModuleType.Tag) {
      const m = this.store.findMatter(module.matterId);
      return (m ? this.store.matterTag(m)?.name : undefined) ?? '标签';
    }
    if (module.moduleType === ModuleType.Checklist) {
      return `列表 ${this.store.listSummaryText(module.matterId)}`;
    }
    const option = MODULE_OPTIONS.find((item: ModuleOption) => item.type === module.moduleType);
    return option ? option.label : '信息';
  }

  private visibleModulesFor(matter: Matter): ModuleInstance[] {
    return matter.enabledModules.filter((module: ModuleInstance) => {
      return module.moduleType !== ModuleType.Countdown && module.moduleType !== ModuleType.Progress;
    });
  }
}
