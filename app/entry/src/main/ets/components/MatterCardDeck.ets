import { matterErrorMessage } from '../domain/MatterSnapshot';
import { unifiedDataChannel } from '@kit.ArkData';
import { AnimatorResult, LengthMetrics, router } from '@kit.ArkUI';
import { MatterServices } from '../application/MatterServices';
import { MatterService } from '../contracts/MatterService';
import { Colors, Radius, Space } from '../common/Theme';
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
  @Prop @Watch('resizeDeck') pageHeight: number = 0;
  @Prop @Watch('returnToFront') homeRequest: number = 0;
  onBrowseChange: (awayFromFront: boolean) => void = () => {};
  @State private cards: Matter[] = [];
  @State private searchText: string = '';
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

  private refresh(preserveIndex: boolean = false): void {
    this.matters = this.showArchived ? this.service.archivedMatters() : this.service.activeMatters();
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
    const filtered = keyword.length === 0 ? this.matters : this.matters.filter((matter: Matter) =>
      matter.title.includes(keyword) || (matter.description ?? '').includes(keyword) || this.store.getNote(matter.id).includes(keyword));
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
    router.pushUrl({ url: 'pages/MatterDetail', params: { matterId: matter.id } });
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

  build() {
    Column() {
      if (this.searchOpen) {
        this.SearchBar()
      }
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.cards.length === 0) {
          Text(this.searchText.trim() ? '没有匹配的事项' : this.showArchived ? '还没有归档事项' : '还没有事项')
            .width('100%').textAlign(TextAlign.Center).fontSize(17).fontColor(Colors.subText)
            .position({ x: 0, y: Math.max(0, (this.layout.viewport - DOCK_CLEARANCE) / 2 - 14) })
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
          Row().width('100%').height(22)
            .linearGradient({ direction: GradientDirection.Bottom, colors: [['#00F7F9FC', 0], [Colors.page, 0.92]] })
            .position({ x: 0, y: Math.max(0, this.layout.viewport - 22) }).zIndex(this.cards.length + 1)
            .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
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
      Row().width('100%').height('100%').backgroundColor(Colors.subText)
        .opacity(Math.min(0.30, Math.max(0, -this.layout.depthAt(index, this.at)) * 0.08))
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      Scroll() {
        this.MatterRow(matter, index)
      }.enableScrollInteraction(false).scrollBar(BarState.Off).edgeEffect(EdgeEffect.None)
      .width('100%').height('100%').align(Alignment.TopStart)
    }.width('94%').height(this.layout.faceHeight(index))
    .constraintSize({ minHeight: this.layout.faceHeight(index) })
    .backgroundColor(this.dragTargetMatterId === matter.id ? Colors.primarySoft : Colors.surface)
    .borderRadius(Radius.large).clip(true)
    .border({ width: this.dragTargetMatterId === matter.id ? 2 : 1,
      color: this.dragTargetMatterId === matter.id ? Colors.primary : Colors.border })
    .shadow({ radius: 5, color: '#150F1A27', offsetY: 2 })
    .scale({ x: this.layout.widthScaleAt(this.layout.depthAt(index, this.at)), y: 1 })
    .rotate({ x: 1, y: 0, z: 0, centerY: '0%',
      angle: -this.layout.tiltAt(this.layout.depthAt(index, this.at)) })
    .opacity(this.layout.opacityAt(this.layout.depthAt(index, this.at)))
    .hitTestBehavior(this.layout.opacityAt(this.layout.depthAt(index, this.at)) > 0 ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(this.layout.opacityAt(this.layout.depthAt(index, this.at)) > 0 ? 'auto' : 'no-hide-descendants')
    .position({ x: '3%', y: this.layout.sheetTop(index, this.at) - this.layout.paintTop(index, this.at) })
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
    Column({ space: Space.small }) {
      TextInput({ placeholder: '搜索事项', text: this.searchText })
        .height(42)
        .fontSize(15)
        .backgroundColor(Colors.surface)
        .borderRadius(Radius.normal)
        .onChange((value: string) => {
          this.searchText = value;
          this.filterMatters();
        });

      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(Space.small), cross: LengthMetrics.vp(Space.tiny) } }) {
        Button(this.showArchived ? '显示未归档' : '显示归档')
          .fontSize(14)
          .fontColor(Colors.primary)
          .backgroundColor(Colors.primarySoft)
          .borderRadius(Radius.normal)
          .onClick(() => {
            this.showArchived = !this.showArchived;
            this.refresh();
          });
        Button('补充示例').fontSize(14).fontColor(Colors.primary)
          .backgroundColor(Colors.primarySoft).borderRadius(Radius.normal)
          .enabled(!this.addingExamples && !MatterServices.isPreview()).onClick(() => this.addExamples())
        Button(this.pendingReset ? '确认重置' : '重置演示数据')
          .enabled(!MatterServices.isPreview())
          .fontSize(14)
          .fontColor(this.pendingReset ? Color.White : Colors.subText)
          .backgroundColor(this.pendingReset ? Colors.danger : Colors.surface)
          .borderRadius(Radius.normal)
          .border({
            width: 1,
            color: Colors.border
          })
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
    }.width('100%').padding({ left: Space.large, right: Space.large, top: Space.small })
  }

  @Builder
  private MatterRow(matter: Matter, index: number) {
    Column({ space: Space.small }) {
      Row() {
        Column()
          .width(6)
          .height(54)
          .backgroundColor(this.store.clusterColor(matter.clusterId))
          .borderRadius(3);

        Column({ space: 5 }) {
          Row() {
            Text(matter.title)
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor(Colors.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1);
            if (matter.clusterId) {
              Text('弱关联')
                .fontSize(12)
                .fontColor(Colors.primary)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(Colors.primarySoft)
                .borderRadius(Radius.small);
            }
          }

          Column({ space: 5 }) {
            Text(matter.description ?? '未填写说明')
              .fontSize(14).fontColor(Colors.subText).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(this.store.moduleSummary(matter))
              .fontSize(13).fontColor(Colors.subText).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }.width('100%').alignItems(HorizontalAlign.Start)
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: Space.normal })
        .layoutWeight(1);
      }
      .width('100%').accessibilityGroup(true).accessibilityText('打开' + matter.title)
      .onClick(() => this.openMatter(matter));

      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(Space.tiny), cross: LengthMetrics.vp(Space.tiny) } }) {
        ForEach(this.visibleModulesFor(matter).slice(0, 5), (module: ModuleInstance) => {
          Chip({ text: this.moduleText(module), selected: true });
        }, (module: ModuleInstance) => module.id);
      }.accessibilityLevel(index < this.at.index ? 'no-hide-descendants' : 'auto')

      Flex({ wrap: FlexWrap.Wrap }) {
        Button('打开')
          .fontSize(14)
          .height(40)
          .padding({ left: Space.normal, right: Space.normal })
          .fontColor(Color.White)
          .backgroundColor(Colors.primary)
          .borderRadius(Radius.normal)
          .margin({ right: Space.small, bottom: Space.tiny })
          .onClick(() => this.openMatter(matter));
        Button('上移')
          .fontSize(14)
          .height(40)
          .padding({ left: Space.normal, right: Space.normal })
          .fontColor(Colors.primary)
          .backgroundColor(Colors.primarySoft)
          .borderRadius(Radius.normal)
          .margin({ right: Space.small, bottom: Space.tiny })
          .onClick(() => this.moveMatter(matter.id, -1));
        Button('下移')
          .fontSize(14)
          .height(40)
          .padding({ left: Space.normal, right: Space.normal })
          .fontColor(Colors.primary)
          .backgroundColor(Colors.primarySoft)
          .borderRadius(Radius.normal)
          .margin({ right: Space.small, bottom: Space.tiny })
          .onClick(() => this.moveMatter(matter.id, 1));
        if (matter.clusterId) {
          Button('移出簇')
            .fontSize(14)
            .height(40)
            .padding({ left: Space.normal, right: Space.normal })
            .fontColor(Colors.warning)
            .backgroundColor('#FFF0E8')
            .borderRadius(Radius.normal)
            .margin({ right: Space.small, bottom: Space.tiny })
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
          .fontSize(14)
          .height(40)
          .padding({ left: Space.normal, right: Space.normal })
          .fontColor(Colors.subText)
          .backgroundColor(Colors.surfaceSoft)
          .borderRadius(Radius.normal)
          .margin({ right: Space.small, bottom: Space.tiny })
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
          .fontSize(14)
          .height(40)
          .padding({ left: Space.normal, right: Space.normal })
          .fontColor(this.pendingDeleteMatterId === matter.id ? Color.White : Colors.danger)
          .backgroundColor(this.pendingDeleteMatterId === matter.id ? Colors.danger : '#FFE7ED')
          .borderRadius(Radius.normal)
          .margin({ right: Space.small, bottom: Space.tiny })
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
      }.accessibilityLevel(index < this.at.index ? 'no-hide-descendants' : 'auto')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: Space.large, right: Space.normal, top: Space.normal, bottom: Space.small })
    .onSizeChange((_old: SizeOptions, size: SizeOptions) => this.measureCard(matter.id, Number(size.height)))
    .enabled(!MatterServices.isPreview());
  }

  private moduleText(module: ModuleInstance): string {
    if (module.moduleType === ModuleType.Deadline) return this.store.countdownText(module.matterId);
    const option = MODULE_OPTIONS.find((item: ModuleOption) => item.type === module.moduleType);
    return option ? option.label : '信息';
  }

  private visibleModulesFor(matter: Matter): ModuleInstance[] {
    return matter.enabledModules.filter((module: ModuleInstance) => {
      return module.moduleType !== ModuleType.Countdown && module.moduleType !== ModuleType.Progress;
    });
  }
}
