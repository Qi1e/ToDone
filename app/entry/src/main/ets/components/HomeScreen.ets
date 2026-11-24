import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { MatterServices } from '../application/MatterServices';
import { cleanMatterAttachmentFiles } from '../application/TimelineAttachmentFiles';
import { TimelineReminders } from '../application/TimelineReminders';
import { formatDate, pad2 } from '../common/DateFormat';
import { Colors, Radius, Space, TABULAR_NUMS, TypeSize, TypeWeight } from '../common/Theme';
import { HomeDock, HomeGlyph, HomeIcon, HomeTab, DOCK_CLEARANCE, DOCK_MARGIN } from './HomeNavigation';
import { MatterCardDeck } from './MatterCardDeck';
import { TimelineAttachmentList } from './TimelineAttachments';
import { TimelineBrowseDates } from './TimelineBrowseDates';
import { monthStart } from './TimelineDatePicker';
import { TimelineGrid } from './TimelineGrid';
import { TimelineLinkedNote } from './TimelineLinkedNote';
import {
  TimelineBlock,
  TimelineDeleteScope,
  TimelineRepeat,
  timelineReminderLabel,
  timelineRepeatLabel,
  TimelineTag
} from '../contracts/TimelineService';
import { matterErrorMessage } from '../domain/MatterSnapshot';
import { localDayStart, timelineBlocksForDay } from '../domain/TimelineLayout';
import { MatterStore } from '../store/MatterStore';

interface HomeCalendarRoute {
  day?: number;
  blockId?: string;
  originalStart?: number;
}

const HOME_HEADER_HEIGHT: number = 56;
const WEEKDAYS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

@Component
export struct HomeScreen {
  initialTab: HomeTab = HomeTab.Cards;
  @Prop @Watch('foregroundChanged') foreground: boolean = true;
  registerBack: (handler: () => boolean) => void = () => {};
  @State private tab: HomeTab = HomeTab.Cards;
  @State private searchOpen: boolean = false;
  @State private dateFilterActive: boolean = false;
  @State private matterRevision: number = 0;
  @State private greeting: string = '你好';
  private abilityContext?: common.UIAbilityContext;
  @State private reminderStatus: string = '';
  private reminderRequest: number = 0;
  private pageActive: boolean = false;
  private calendarRoute?: HomeCalendarRoute;
  @State day: number = localDayStart(Date.now());
  @State today: number = localDayStart(Date.now());
  @State tags: TimelineTag[] = [];
  @State contentHeight: number = 0;
  private deckAwayFromFront: boolean = false;
  @State private deckHomeRequest: number = 0;
  @State private calendarLevel: number = 0;
  @State private browseMonth: number = monthStart(Date.now());
  private midnightTimer: number = -1;
  @State blocks: TimelineBlock[] = [];
  @State showSheet: boolean = false;
  @State saving: boolean = false;
  @State confirmDelete: boolean = false;
  @State pendingScope: TimelineDeleteScope = TimelineDeleteScope.One;
  @State errorMessage: string = '';
  @State focusAt: number = 0;
  @State current: TimelineBlock = { id: '', title: '', startAt: 0, endAt: 0, note: '' };
  @State private matterLoading: boolean = true;
  @State private matterReadError: string = '';
  private unsubscribeMatters?: () => void;

  aboutToAppear(): void {
    this.pageActive = true;
    this.tab = this.initialTab;
    this.registerBack(() => this.handleBack());
    this.unsubscribeMatters = MatterStore.getInstance().subscribe(() => {
      this.matterRevision++;
      this.reloadScheduleFromStore();
    });
    this.loadMatters();
    try {
      const route = this.initialTab === HomeTab.Timeline
        ? router.getParams() as HomeCalendarRoute | undefined
        : undefined;
      if (route && typeof route.day === 'number' && Number.isFinite(new Date(route.day).getTime())) {
        this.setDayOnly(route.day);
        this.calendarRoute = route;
      }
    } catch (error) {
      // 单页预览可以没有路由栈，沿用默认日期。
    }
    if (this.foreground) this.refreshToday();
  }

  aboutToDisappear(): void {
    this.unsubscribeMatters?.();
    this.pageActive = false;
    this.registerBack(() => false);
    this.stopMidnightTimer();
  }

  private foregroundChanged(): void {
    if (!this.pageActive) return;
    if (this.foreground) {
      this.loadMatters();
      this.refreshToday();
    } else {
      this.stopMidnightTimer();
    }
  }

  private async loadMatters(): Promise<void> {
    this.matterLoading = true;
    try {
      if (!MatterServices.isPreview()) {
        const context = getContext(this) as common.UIAbilityContext;
        this.abilityContext = context;
        await MatterServices.initialize(context);
      }
      this.matterReadError = '';
      this.reloadScheduleFromStore();
      this.consumeFocusScheduleDay();
      this.matterRevision++;
      MatterServices.requestCardRefresh();
      if (!MatterServices.isPreview() && this.abilityContext && !this.showSheet) {
        cleanMatterAttachmentFiles(this.abilityContext, MatterStore.getInstance().allReferencedAttachments());
        this.syncReminders();
      }
      this.applyPendingCalendarRoute();
    } catch (error) {
      this.matterReadError = matterErrorMessage(error as Error);
    } finally {
      this.matterLoading = false;
    }
  }

  private consumeFocusScheduleDay(): void {
    const focusDay = AppStorage.get<number>('todone_focus_schedule_day');
    if (typeof focusDay === 'number' && Number.isFinite(focusDay) && focusDay > 0) {
      AppStorage.setOrCreate('todone_focus_schedule_day', 0);
      this.setDayOnly(focusDay);
      this.dateFilterActive = true;
      this.tab = HomeTab.Cards;
      setTimeout(() => {
        if (this.pageActive) {
          this.getUIContext().getPromptAction().showToast({
            message: '已排入当日日程，点「× 返回全部」回到常驻清单',
            duration: 2200,
            bottom: DOCK_CLEARANCE
          });
        }
      }, 120);
    }
  }

  private applyPendingCalendarRoute(): void {
    const route = this.calendarRoute;
    this.calendarRoute = undefined;
    if (route && route.blockId && route.originalStart !== undefined) {
      const selected = timelineBlocksForDay(this.day, this.blocks).find((item: TimelineBlock) =>
        item.id === route.blockId && (item.occurrenceOriginalStart ?? item.startAt) === route.originalStart);
      if (selected) {
        this.focusAt = Math.max(this.day, selected.startAt);
        this.selectBlock(selected);
      }
    }
  }

  private reloadScheduleFromStore(): void {
    const store = MatterStore.getInstance();
    this.blocks = store.timelineBlocks();
    this.tags = store.listTags();
  }

  private handleBack(): boolean {
    if (this.showSheet) return false;
    if (this.tab === HomeTab.Settings) {
      this.tab = HomeTab.Cards;
    } else if (this.calendarLevel > 0) {
      this.calendarLevel--;
    } else if (this.tab === HomeTab.Cards && this.searchOpen) {
      this.searchOpen = false;
    } else if (this.tab === HomeTab.Cards && this.dateFilterActive) {
      this.dateFilterActive = false;
    } else if (this.tab === HomeTab.Cards && this.deckAwayFromFront) {
      this.deckHomeRequest++;
    } else if (this.tab === HomeTab.Timeline && this.initialTab === HomeTab.Cards) {
      this.tab = HomeTab.Cards;
    } else {
      return false;
    }
    return true;
  }

  private stopMidnightTimer(): void {
    clearTimeout(this.midnightTimer);
    this.midnightTimer = -1;
  }

  private refreshToday(): void {
    this.stopMidnightTimer();
    const now = Date.now();
    const today = localDayStart(now);
    if (today !== this.today && this.day === this.today) this.setDayOnly(today);
    this.today = today;
    const hour = new Date(now).getHours();
    this.greeting = hour < 11 ? '早上好' : hour < 14 ? '中午好' : hour < 18 ? '下午好' : '晚上好';
    if (this.tab === HomeTab.Timeline) this.syncReminders();
    this.midnightTimer = setTimeout(() => this.refreshToday(), localDayStart(now, 1) - now);
  }

  private async syncReminders(askPermission: boolean = false): Promise<void> {
    if (!this.abilityContext || this.matterReadError) return;
    const request = ++this.reminderRequest;
    let status: string;
    try {
      status = await TimelineReminders.sync(
        this.abilityContext,
        MatterStore.getInstance().reminderBlocks(),
        askPermission
      );
    } catch (error) {
      status = '事项已保留，系统提醒未能同步。';
    }
    if (request === this.reminderRequest && this.pageActive) this.reminderStatus = status;
  }

  private setDayOnly(value: number): void {
    this.focusAt = 0;
    this.day = localDayStart(value);
    this.browseMonth = monthStart(value);
  }

  private handleCalendarPickDay(value: number): void {
    const picked = localDayStart(value);
    if (this.tab === HomeTab.Cards) {
      // 在主页点击已处于筛选态的同一天，取消日期筛选回到全部常驻
      if (this.dateFilterActive && picked === this.day && this.calendarLevel === 0) {
        this.dateFilterActive = false;
        return;
      }
      this.setDayOnly(picked);
      this.dateFilterActive = true;
      if (this.calendarLevel > 0) this.calendarLevel = 0;
      return;
    }
    this.setDayOnly(picked);
  }

  private openUnifiedCreate(): void {
    if (MatterServices.isPreview()) return;
    if (this.tab === HomeTab.Timeline) {
      router.pushUrl({
        url: 'pages/CreateMatter',
        params: { fromTimeline: true, presetDay: this.day }
      });
    } else {
      router.pushUrl({
        url: 'pages/CreateMatter',
        params: this.dateFilterActive ? { presetDay: this.day } : {}
      });
    }
  }

  private selectBlock(block: TimelineBlock): void {
    this.current = block;
    this.confirmDelete = false;
    this.errorMessage = '';
    this.showSheet = true;
  }

  private isSeries(): boolean {
    return this.current.repeat !== undefined && this.current.repeat !== TimelineRepeat.None;
  }

  private editCurrentInUnifiedPage(clock: string = ''): void {
    const id = this.current.id;
    const occ = this.isSeries() ? (this.current.occurrenceOriginalStart ?? this.current.startAt) : undefined;
    this.showSheet = false;
    router.pushUrl({
      url: 'pages/CreateMatter',
      params: { matterId: id, occurrenceStart: occ, focusClock: clock }
    });
  }

  private openCurrentMatterDetail(): void {
    const id = this.current.id;
    const occ = this.isSeries() ? (this.current.occurrenceOriginalStart ?? this.current.startAt) : undefined;
    this.showSheet = false;
    router.pushUrl({
      url: 'pages/MatterDetail',
      params: { matterId: id, occurrenceStart: occ }
    });
  }

  private startDelete(): void {
    this.confirmDelete = true;
    this.pendingScope = TimelineDeleteScope.One;
    this.errorMessage = '';
  }

  private async deleteBlock(): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    this.errorMessage = '';
    try {
      const scope = this.isSeries() ? this.pendingScope : TimelineDeleteScope.All;
      const occ = this.current.occurrenceOriginalStart ?? this.current.startAt;
      await MatterStore.getInstance().deleteScheduleOccurrence(this.current.id, scope, occ);
      if (this.abilityContext) {
        cleanMatterAttachmentFiles(this.abilityContext, MatterStore.getInstance().allReferencedAttachments());
      }
      this.syncReminders();
      MatterServices.requestCardRefresh();
      if (!this.pageActive) return;
      this.reloadScheduleFromStore();
      this.confirmDelete = false;
      this.showSheet = false;
    } catch (error) {
      if (this.pageActive) this.errorMessage = '删除失败，请重试。';
    } finally {
      if (this.pageActive) this.saving = false;
    }
  }

  private isScopeDeleteSheet(): boolean {
    return this.confirmDelete && this.isSeries();
  }

  @Builder
  private BlockSheet() {
    if (this.isScopeDeleteSheet()) {
      this.ScopeDeleteSheet()
    } else {
      this.BlockDetails()
    }
  }

  private dateLabel(stamp: number): string {
    const date = new Date(stamp);
    const year = date.getFullYear() === new Date().getFullYear() ? '' : date.getFullYear() + '年';
    return year + (date.getMonth() + 1) + '月' + date.getDate() + '日';
  }

  private clockLabel(stamp: number): string {
    const date = new Date(stamp);
    return pad2(date.getHours()) + ':' + pad2(date.getMinutes());
  }

  @Builder
  private DetailTime(label: string, stamp: number, endpoint: string) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: Space.xs }) {
        Text(label).fontSize(TypeSize.meta).fontWeight(TypeWeight.regular).fontColor(Colors.inkMuted)
        Text(this.clockLabel(stamp)).fontSize(TypeSize.figure).fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink).fontFeature(TABULAR_NUMS)
        if (localDayStart(this.current.startAt) !== localDayStart(this.current.endAt)) {
          Text(this.dateLabel(stamp)).fontSize(TypeSize.meta).fontColor(Colors.inkSoft).fontFeature(TABULAR_NUMS)
        }
      }.alignItems(HorizontalAlign.Start).width('100%')
    }
    .layoutWeight(1).constraintSize({ minHeight: localDayStart(this.current.startAt) === localDayStart(this.current.endAt) ? 68 : 88 })
    .padding({ top: Space.xs, bottom: Space.xs }).borderRadius(Radius.card)
    .backgroundColor(Color.Transparent)
    .accessibilityText('调整' + label + '时间，' + this.dateLabel(stamp) + ' ' + this.clockLabel(stamp))
    .onClick(() => this.editCurrentInUnifiedPage(endpoint))
  }

  @Builder
  private TagLabel(tag: TimelineTag) {
    Row({ space: Space.sm }) {
      Row().width(8).height(8).borderRadius(4).backgroundColor(tag.color)
      Text(tag.name).fontSize(TypeSize.bodySmall).fontColor(Colors.inkSoft)
    }
  }

  @Builder
  private ScopeOption(scope: TimelineDeleteScope, label: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: Space.sm }) {
        Text(label).fontSize(TypeSize.body).fontWeight(this.pendingScope === scope ? TypeWeight.semibold : TypeWeight.regular)
          .fontColor(this.pendingScope === scope ? Colors.ink : Colors.inkSoft).layoutWeight(1)
        Stack({ alignContent: Alignment.Center }) {
          if (this.pendingScope === scope) {
            Row().width(10).height(10).borderRadius(5).backgroundColor(Colors.ink)
          }
        }.width(20).height(20).borderRadius(10)
        .border({ width: 1, color: this.pendingScope === scope ? Colors.ink : Colors.line })
      }.width('100%')
    }.width('100%').constraintSize({ minHeight: 44 })
    .padding({ left: Space.sm, right: Space.sm, top: Space.xs, bottom: Space.xs })
    .backgroundColor(this.pendingScope === scope ? Colors.wash : Color.Transparent)
    .borderRadius(Radius.card)
    .onClick(() => { this.pendingScope = scope; this.errorMessage = ''; })
  }

  @Builder
  private ScopeDeleteSheet() {
    Scroll() {
      Column() {
        Text('删除重复事项日程')
          .width('100%').fontSize(TypeSize.heading).fontWeight(TypeWeight.semibold).fontColor(Colors.ink)
        Text(this.current.title + ' · ' + this.dateLabel(this.current.startAt) + ' ' + this.clockLabel(this.current.startAt))
          .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: Space.xs, bottom: Space.md }).fontSize(TypeSize.bodySmall)
          .fontColor(Colors.inkSoft).fontFeature(TABULAR_NUMS)
        this.ScopeOption(TimelineDeleteScope.One, '仅删除这一次')
        this.ScopeOption(TimelineDeleteScope.Following, '删除这次及以后')
        this.ScopeOption(TimelineDeleteScope.All, '删除整个事项系列')
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage).width('100%').fontSize(TypeSize.meta)
            .fontWeight(TypeWeight.semibold).fontColor(Colors.red).margin({ top: Space.sm })
        }
        Row() {
          Button('取消').type(ButtonType.Normal).constraintSize({ minHeight: 44 })
            .backgroundColor(Color.Transparent).fontSize(TypeSize.body)
            .fontWeight(TypeWeight.regular).fontColor(Colors.inkSoft).borderRadius(Radius.card)
            .padding({ left: Space.md, right: Space.md })
            .onClick(() => { this.confirmDelete = false; this.errorMessage = ''; })
          Blank()
          Button(this.saving ? '删除中' : '确认删除')
            .type(ButtonType.Normal).constraintSize({ minHeight: 40 })
            .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold)
            .backgroundColor(Colors.red).fontColor(Colors.onRed).borderRadius(Radius.card)
            .padding({ left: Space.lg, right: Space.lg })
            .onClick(() => { this.deleteBlock(); })
        }.width('100%').constraintSize({ minHeight: 44 }).margin({ top: Space.md })
      }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: Space.page, right: Space.page, top: Space.section, bottom: Space.lg })
    }.width('100%').scrollBar(BarState.Auto).backgroundColor(Colors.card).enabled(!this.saving)
  }

  @Builder
  private BlockDetails() {
    Column() {
      Row({ space: Space.xs }) {
        Text(this.dateLabel(this.current.startAt) + ' · 周' +
          WEEKDAYS[(new Date(this.current.startAt).getDay() + 6) % 7])
          .fontSize(TypeSize.bodySmall).fontColor(Colors.inkSoft).fontFeature(TABULAR_NUMS).layoutWeight(1)
        Button('详情').type(ButtonType.Normal).constraintSize({ minHeight: 40 })
          .padding({ left: Space.sm, right: Space.sm })
          .fontSize(TypeSize.body).fontWeight(TypeWeight.regular)
          .fontColor(Colors.inkSoft).backgroundColor(Color.Transparent).borderRadius(Radius.card)
          .onClick(() => this.openCurrentMatterDetail())
        Button('编辑事项').type(ButtonType.Normal).constraintSize({ minHeight: 40 })
          .padding({ left: Space.sm, right: Space.sm })
          .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink).backgroundColor(Color.Transparent).borderRadius(Radius.card)
          .onClick(() => this.editCurrentInUnifiedPage(''))
      }.width('100%')
      Scroll() {
        Column({ space: Space.md }) {
          Text(this.current.title).width('100%').fontSize(TypeSize.heading)
            .fontWeight(TypeWeight.semibold).fontColor(Colors.ink)
          if (this.isSeries()) {
            Text(timelineRepeatLabel(this.current.repeat ?? TimelineRepeat.None) + '重复')
              .width('100%').fontSize(TypeSize.bodySmall).fontColor(Colors.inkSoft)
          }
          ForEach(this.tags.filter((tag: TimelineTag) => tag.id === this.current.tagId), (tag: TimelineTag) => {
            this.TagLabel(tag)
          }, (tag: TimelineTag) => tag.id)
          Column() {
            Row({ space: Space.lg }) {
              this.DetailTime('开始', this.current.startAt, 'start')
              Text('→').fontSize(16).fontColor(Colors.inkMuted)
              this.DetailTime('结束', this.current.endAt, 'end')
            }.width('100%')
            Text(this.durationDescription()).fontSize(TypeSize.meta).fontColor(Colors.inkMuted).fontFeature(TABULAR_NUMS)
          }.width('100%').alignItems(HorizontalAlign.Start)
          if (this.current.reminderMinutes !== undefined) {
            Text('提醒 · ' + timelineReminderLabel(this.current.reminderMinutes))
              .width('100%').fontSize(TypeSize.bodySmall).fontColor(Colors.inkSoft).fontFeature(TABULAR_NUMS)
          }
          if (this.current.note.trim().length > 0 || (this.current.attachments?.length ?? 0) > 0) {
            Divider().color(Colors.hairline)
            Text('备注').fontSize(TypeSize.meta).fontColor(Colors.inkMuted)
            if (this.current.note.trim().length > 0) {
              TimelineLinkedNote({ value: this.current.note })
            }
            if ((this.current.attachments?.length ?? 0) > 0) {
              TimelineAttachmentList({ items: this.current.attachments ?? [] })
            }
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: Space.md })
      }.layoutWeight(1).width('100%').align(Alignment.TopStart)
      if (this.errorMessage.length > 0) {
        Text(this.errorMessage).width('100%').fontColor(Colors.red)
          .fontSize(TypeSize.meta).fontWeight(TypeWeight.semibold)
      }
      Divider().color(Colors.hairline)
      Row() {
        if (this.confirmDelete) {
          Text('删除这个事项？')
            .fontSize(TypeSize.body).fontColor(Colors.ink).layoutWeight(1)
          Button('保留').type(ButtonType.Normal).constraintSize({ minHeight: 44 })
            .fontSize(TypeSize.body).fontWeight(TypeWeight.regular)
            .fontColor(Colors.inkSoft).backgroundColor(Color.Transparent).borderRadius(Radius.card)
            .padding({ left: Space.sm, right: Space.sm })
            .onClick(() => { this.confirmDelete = false; this.errorMessage = ''; })
          Button(this.saving ? '删除中' : '确认删除').type(ButtonType.Normal).constraintSize({ minHeight: 44 })
            .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold)
            .fontColor(Colors.red).backgroundColor(Color.Transparent).borderRadius(Radius.card)
            .padding({ left: Space.sm, right: Space.sm })
            .onClick(() => { this.deleteBlock(); })
        } else {
          Button('删除').type(ButtonType.Normal).constraintSize({ minHeight: 44 })
            .padding({ left: 0, right: Space.md })
            .backgroundColor(Color.Transparent).fontColor(Colors.red)
            .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold).borderRadius(Radius.card)
            .onClick(() => this.startDelete())
          Blank()
          Button('收起').type(ButtonType.Normal).constraintSize({ minHeight: 44 })
            .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink).backgroundColor(Color.Transparent).borderRadius(Radius.card)
            .padding({ left: Space.sm, right: 0 })
            .onClick(() => { this.showSheet = false; })
        }
      }.width('100%').padding({ top: Space.xs })
    }
    .enabled(!this.saving).alignItems(HorizontalAlign.Start).width('100%').height('100%')
    .padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.sm })
    .backgroundColor(Colors.card)
  }

  private durationDescription(): string {
    const minutes = Math.round((this.current.endAt - this.current.startAt) / 60000);
    const hours = Math.floor(minutes / 60);
    return '共 ' + (hours > 0 ? hours + ' 小时' : '') +
      (minutes % 60 > 0 ? (hours > 0 ? ' ' : '') + (minutes % 60) + ' 分钟' : '');
  }

  private switchTab(tab: HomeTab): void {
    if (tab === HomeTab.Review || tab === this.tab || this.showSheet) return;
    this.tab = tab;
    if (tab === HomeTab.Timeline) {
      if (this.abilityContext && !this.matterReadError) {
        cleanMatterAttachmentFiles(this.abilityContext, MatterStore.getInstance().allReferencedAttachments());
      }
      this.syncReminders();
    }
  }

  private openCalendarBlock(block: TimelineBlock): void {
    this.switchTab(HomeTab.Timeline);
    this.focusAt = Math.max(this.day, block.startAt);
    this.selectBlock(block);
  }

  @Builder
  private HeaderButton(glyph: HomeGlyph, label: string, action: () => void, enabled: boolean = true, primary: boolean = false) {
    Button({ type: ButtonType.Normal }) {
      HomeIcon({ glyph: glyph, ink: primary ? Colors.onRed : Colors.ink, iconSize: 20 })
    }.width(40).height(40).padding(0)
    .backgroundColor(primary ? Colors.red : Color.Transparent)
    .borderRadius(Radius.card)
    .opacity(enabled ? 1 : 0.4)
    .accessibilityText(label).enabled(enabled).onClick(() => action())
  }

  @Builder
  private Header() {
    Row({ space: Space.xs }) {
      Text(this.tab === HomeTab.Settings ? '设置' : this.greeting)
        .layoutWeight(1).fontSize(TypeSize.display).fontWeight(TypeWeight.semibold).fontColor(Colors.ink)
      if (this.tab !== HomeTab.Settings) {
        this.HeaderButton(HomeGlyph.Hint, '操作提示', () => {
          this.getUIContext().getPromptAction().showToast({
            message: this.tab === HomeTab.Cards
              ? '点日期筛选当日日程，点卡片打开事项，上下推卡片翻找。'
              : '下拉日期展开月历，点便签查看或编辑事项。'
          });
        })
        this.HeaderButton(HomeGlyph.Search, '搜索事项', () => {
          this.searchOpen = this.tab === HomeTab.Timeline || !this.searchOpen;
          this.switchTab(HomeTab.Cards);
        })
        this.HeaderButton(HomeGlyph.Add, '新建事项', () => {
          this.openUnifiedCreate();
        }, !MatterServices.isPreview() && !this.matterReadError && !this.saving, true)
      }
    }.width('100%').height(HOME_HEADER_HEIGHT).padding({ left: Space.page, right: Space.page }).backgroundColor(Colors.bg)
  }

  @Builder
  private TimelineBody() {
    if (this.reminderStatus.length > 0) {
      Row({ space: Space.sm }) {
        Text(this.reminderStatus).fontSize(TypeSize.bodySmall).fontColor(Colors.inkSoft).layoutWeight(1)
        Button('同步提醒').type(ButtonType.Normal).constraintSize({ minHeight: 40 })
          .padding({ left: Space.sm, right: Space.sm })
          .backgroundColor(Color.Transparent).fontSize(TypeSize.bodySmall)
          .fontWeight(TypeWeight.semibold).fontColor(Colors.ink).borderRadius(Radius.card)
          .onClick(() => { this.syncReminders(true); })
      }.width('100%').padding({ left: Space.page, right: Space.page })
    }
    if (this.matterReadError) {
      Column({ space: Space.sm }) {
        Text(this.matterReadError).fontSize(TypeSize.bodySmall)
          .fontWeight(TypeWeight.semibold).fontColor(Colors.red)
        Button('重新读取').type(ButtonType.Normal).constraintSize({ minHeight: 40 })
          .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink).backgroundColor(Colors.wash).borderRadius(Radius.card)
          .padding({ left: Space.lg, right: Space.lg })
          .onClick(() => { this.loadMatters(); })
      }.width('100%').alignItems(HorizontalAlign.Start).padding(Space.page)
    } else {
      Column() {
        TimelineGrid({
          day: this.day,
          today: this.today,
          blocks: this.blocks,
          tags: this.tags,
          focusAt: this.focusAt,
          bottomInset: DOCK_CLEARANCE,
          selectedId: this.showSheet ? this.current.id : '',
          selectedStartAt: this.current.occurrenceOriginalStart ?? this.current.startAt,
          onSelect: (block: TimelineBlock) => this.selectBlock(block)
        })
      }.layoutWeight(1).width('100%').clip(true)
      .accessibilityLevel(this.calendarLevel === 2 ? 'no-hide-descendants' : 'auto')
      .parallelGesture(PanGesture({ direction: PanDirection.Horizontal, distance: 18 })
        .onActionEnd((event: GestureEvent) => {
          if (Math.abs(event.offsetX) >= 36 && Math.abs(event.offsetX) > Math.abs(event.offsetY) * 1.5) {
            this.setDayOnly(localDayStart(this.day, event.offsetX < 0 ? 1 : -1));
          }
        }))
    }
  }

  build() {
    Column() {
      this.Header()
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          TimelineBrowseDates({
            day: this.day,
            today: this.today,
            month: $browseMonth,
            level: $calendarLevel,
            availableHeight: this.contentHeight,
            blocks: this.blocks,
            tags: this.tags,
            showScheduleRings: this.tab === HomeTab.Timeline,
            showScheduleDots: this.tab === HomeTab.Cards,
            highlightSelection: this.tab === HomeTab.Timeline || this.dateFilterActive || this.calendarLevel > 0,
            readError: this.matterReadError,
            onRetry: () => { this.loadMatters(); },
            onSelectDay: (day: number) => this.handleCalendarPickDay(day),
            onSelectBlock: (block: TimelineBlock) => this.openCalendarBlock(block)
          }).visibility(this.tab === HomeTab.Settings ? Visibility.None : Visibility.Visible)
          Stack() {
            MatterCardDeck({
              searchOpen: this.searchOpen,
              filterActive: this.dateFilterActive,
              selectedDay: this.day,
              today: this.today,
              revision: this.matterRevision,
              homeRequest: this.deckHomeRequest,
              pageHeight: this.contentHeight + HOME_HEADER_HEIGHT,
              onBrowseChange: (awayFromFront: boolean) => { this.deckAwayFromFront = awayFromFront; },
              onClearDateFilter: () => { this.dateFilterActive = false; },
              onFilterToday: () => {
                this.setDayOnly(this.today);
                this.dateFilterActive = true;
              }
            })
              .visibility(this.tab === HomeTab.Cards && !this.matterReadError && !this.matterLoading
                ? Visibility.Visible : Visibility.None)
            if (this.tab === HomeTab.Cards && (this.matterReadError || this.matterLoading)) {
              Column({ space: Space.md }) {
                Text(this.matterLoading ? '正在读取…' : this.matterReadError)
                  .fontSize(TypeSize.bodySmall)
                  .fontColor(this.matterLoading ? Colors.inkMuted : Colors.red)
                if (this.matterReadError && !this.matterLoading) {
                  Button('重新读取').type(ButtonType.Normal).constraintSize({ minHeight: 40 })
                    .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold)
                    .fontColor(Colors.ink).backgroundColor(Colors.wash).borderRadius(Radius.card)
                    .padding({ left: Space.lg, right: Space.lg })
                    .onClick(() => this.loadMatters())
                }
              }.width('100%').alignItems(HorizontalAlign.Start).padding(Space.page)
            }
            if (this.tab === HomeTab.Timeline) {
              Column() { this.TimelineBody() }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
            } else if (this.tab === HomeTab.Settings) {
              Column() {
                Button('桌面服务卡片').type(ButtonType.Normal).constraintSize({ minHeight: 44 })
                  .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold).fontColor(Colors.ink)
                  .backgroundColor(Colors.card).borderRadius(Radius.card)
                  .border({ width: 1, color: Colors.hairline })
                  .padding({ left: Space.lg, right: Space.lg })
                  .opacity(MatterServices.isPreview() ? 0.4 : 1)
                  .enabled(!MatterServices.isPreview()).onClick(() => router.pushUrl({ url: 'pages/WidgetPreview' }))
              }.width('100%').height('100%').alignItems(HorizontalAlign.Start).padding(Space.page)
            }
          }.width('100%').layoutWeight(1).clip(true)
          .accessibilityLevel(this.calendarLevel === 2 && this.tab !== HomeTab.Settings ? 'no-hide-descendants' : 'auto')
        }.width('100%').height('100%')
        if (this.calendarLevel < 2 || this.tab === HomeTab.Settings) {
          HomeDock({
            tab: this.tab,
            onSelect: (tab: HomeTab) => {
              if (tab === HomeTab.Cards && tab === this.tab && !this.showSheet) {
                if (this.dateFilterActive) this.dateFilterActive = false;
                this.deckHomeRequest++;
              } else {
                this.switchTab(tab);
              }
            }
          }).margin({ bottom: DOCK_MARGIN })
        }
      }.width('100%').layoutWeight(1).clip(true)
    }.height('100%').width('100%').backgroundColor(Colors.bg)
    .clip(true)
    .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
      this.contentHeight = Math.max(0, Number(size.height) - HOME_HEADER_HEIGHT);
    })
    .bindSheet($$this.showSheet, this.BlockSheet(), {
      height: this.isScopeDeleteSheet() ? SheetSize.FIT_CONTENT : SheetSize.MEDIUM,
      showClose: false,
      dragBar: !this.isScopeDeleteSheet(),
      backgroundColor: Colors.card,
      maskColor: '#59191714',
      onWillDismiss: (action: DismissSheetAction) => {
        if (!this.saving) {
          if (this.isScopeDeleteSheet()) {
            this.confirmDelete = false;
            this.errorMessage = '';
          } else {
            action.dismiss();
          }
        }
      }
    })
  }
}
