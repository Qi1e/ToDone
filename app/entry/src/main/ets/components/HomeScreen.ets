import { hilog } from '@kit.PerformanceAnalysisKit';
import { timelineReadCode } from '../domain/TimelineReadError';
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { TimelineReminders } from '../application/TimelineReminders';
import { TimelineAttachmentSession, cleanTimelineAttachmentFiles } from '../application/TimelineAttachmentFiles';
import { TimelineAttachmentList } from './TimelineAttachments';
import { TimelineLinkedNote } from './TimelineLinkedNote';
import { TimelineServices } from '../application/TimelineServices';
import { TimelineBlock, TimelineDeleteScope, TimelineEditScope, TimelineRepeat, TimelineService, TimelineTag, timelineRepeatLabel, timelineReminderLabel } from '../contracts/TimelineService';
import { formatDate, pad2 } from '../common/DateFormat';
import { Colors, Radius, Space, TABULAR_NUMS, TypeSize, TypeWeight } from '../common/Theme';
import { TimelineEditor } from './TimelineEditor';
import { TimelineBrowseDates } from './TimelineBrowseDates';
import { monthStart } from './TimelineDatePicker';
import { TimelineGrid } from './TimelineGrid';
import { createId } from '../model/Defaults';
import { localDayStart, timelineBlocksForDay } from '../domain/TimelineLayout';
import { firstVisibleTimelineOccurrence } from '../domain/TimelineRecurrence';

import { MatterServices } from '../application/MatterServices';
import { MatterStore } from '../store/MatterStore';
import { matterErrorMessage } from '../domain/MatterSnapshot';
import { MatterCardDeck } from './MatterCardDeck';
import { HomeDock, HomeGlyph, HomeIcon, HomeTab, DOCK_CLEARANCE, DOCK_MARGIN } from './HomeNavigation';

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
  @State private matterRevision: number = 0;
  @State private greeting: string = '你好';
  private service?: TimelineService;
  private abilityContext?: common.UIAbilityContext;
  private attachmentSession: TimelineAttachmentSession = new TimelineAttachmentSession();
  @State private importing: boolean = false;
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
  @State loadError: string = '';
  @State showSheet: boolean = false;
  @State showEditor: boolean = false;
  @State newTagPage: boolean = false;
  @State creating: boolean = false;
  @State initialClock: string = '';
  @State saving: boolean = false;
  @State confirmDelete: boolean = false;
  @State confirmEdit: boolean = false;
  private editDraft?: TimelineBlock;
  @State pendingScope: TimelineDeleteScope = TimelineDeleteScope.One;
  @State errorMessage: string = '';
  @State focusAt: number = 0;
  @State current: TimelineBlock = { id: '', title: '', startAt: 0, endAt: 0, note: '' };

  aboutToAppear(): void {
    this.pageActive = true;
    this.tab = this.initialTab;
    this.registerBack(() => this.handleBack());
    this.unsubscribeMatters = MatterStore.getInstance().subscribe(() => { this.matterRevision++; });
    this.loadMatters();
    try {
      const route = this.initialTab === HomeTab.Timeline ? router.getParams() as HomeCalendarRoute | undefined : undefined;
      if (route && typeof route.day === 'number' && Number.isFinite(new Date(route.day).getTime())) {
        this.selectDay(route.day);
        this.calendarRoute = route;
      }
    } catch (error) {
      // 单页预览可以没有路由栈，沿用默认日期。
    }
    this.load();
    if (this.foreground) this.refreshToday();
  }

  aboutToDisappear(): void {
    this.unsubscribeMatters?.();
    this.pageActive = false;
    this.registerBack(() => false);
    if (!this.saving && this.tab === HomeTab.Timeline) this.finishAttachments();
    this.stopMidnightTimer();
  }

  private foregroundChanged(): void {
    if (!this.pageActive) return;
    if (this.foreground) {
      this.loadMatters();
      this.load();
      this.refreshToday();
    } else {
      this.stopMidnightTimer();
    }
  }

  @State private matterLoading: boolean = true;
  @State private matterReadError: string = '';
  private unsubscribeMatters?: () => void;

  private async loadMatters(): Promise<void> {
    this.matterLoading = true;
    try {
      await MatterServices.initialize(getContext(this) as common.UIAbilityContext);
      this.matterReadError = '';
      this.matterRevision++;
      MatterServices.requestCardRefresh();
    } catch (error) {
      this.matterReadError = matterErrorMessage(error as Error);
    } finally {
      this.matterLoading = false;
    }
  }

  private handleBack(): boolean {
    if (this.showSheet) return false;
    if (this.tab === HomeTab.Settings) {
      this.tab = HomeTab.Cards;
    } else if (this.calendarLevel > 0) {
      this.calendarLevel--;
    } else if (this.tab === HomeTab.Cards && this.searchOpen) {
      this.searchOpen = false;
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
    if (today !== this.today && this.day === this.today) this.selectDay(today);
    this.today = today;
    const hour = new Date(now).getHours();
    this.greeting = hour < 11 ? '早上好' : hour < 14 ? '中午好' : hour < 18 ? '下午好' : '晚上好';
    if (this.tab === HomeTab.Timeline) this.syncReminders();
    this.midnightTimer = setTimeout(() => this.refreshToday(), localDayStart(now, 1) - now);
  }

  private load(): void {
    if (MatterServices.isPreview()) return;
    let stage = 'CONTEXT';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (!context) throw new Error('UIAbility context unavailable');
      this.abilityContext = context;
      stage = 'INIT';
      this.service = TimelineServices.get(context);
      stage = 'LIST';
      this.reloadSchedule();
      this.loadError = '';
    } catch (error) {
      this.loadError = timelineReadCode(error as Error, stage);
      hilog.error(0x0000, 'ToDone', 'Timeline load failed: %{public}s', this.loadError);
      return;
    }
    if (this.tab === HomeTab.Timeline && !this.showSheet && this.abilityContext) cleanTimelineAttachmentFiles(this.abilityContext, this.blocks);
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

  private finishAttachments(): void {
    this.importing = false;
    if (!this.abilityContext || !this.service || this.loadError) return;
    try {
      this.attachmentSession.finish(this.abilityContext, this.service.list());
    } catch (error) {
      console.warn('日程暂时无法读取，附件留待重开时间线时清理');
    }
  }

  private async syncReminders(askPermission: boolean = false): Promise<void> {
    if (!this.abilityContext || !this.service || this.loadError) return;
    const request = ++this.reminderRequest;
    let status: string;
    try {
      status = await TimelineReminders.sync(this.abilityContext, this.service.list(), askPermission);
    } catch (error) {
      status = '日程已保留，系统提醒未能同步。';
    }
    if (request === this.reminderRequest && this.pageActive) this.reminderStatus = status;
  }

  private reloadSchedule(): void {
    if (!this.service) return;
    this.blocks = this.service.list();
    this.tags = this.service.listTags();
  }

  private async saveTag(tag: TimelineTag): Promise<void> {
    if (this.saving || !this.service) throw new Error('暂时无法保存标签，请重试');
    this.saving = true;
    try {
      await this.service.saveTag(tag);
      if (this.pageActive) this.tags = this.service.listTags();
    } finally {
      if (this.pageActive) this.saving = false;
      else this.finishAttachments();
    }
  }

  private selectDay(value: number): void {
    this.focusAt = 0;
    this.day = localDayStart(value);
    this.browseMonth = monthStart(value);
  }

  private createBlock(): void {
    if (this.loadError || this.saving) return;
    this.attachmentSession = new TimelineAttachmentSession();
    this.editDraft = undefined;
    this.confirmEdit = false;
    const start = new Date(this.day);
    start.setHours(formatDate(this.day) === formatDate(Date.now()) ?
      Math.min(new Date().getHours() + 1, 23) : 9, 0, 0, 0);
    let id = createId('time');
    while (this.blocks.some((block: TimelineBlock) => block.id === id)) {
      id = createId('time');
    }
    this.current = { id: id, title: '', startAt: start.getTime(), endAt: start.getTime() + 3600000, note: '' };
    this.initialClock = '';
    this.newTagPage = false;
    this.creating = true;
    this.showEditor = true;
    this.errorMessage = '';
    this.confirmDelete = false;
    this.showSheet = true;
  }

  private selectBlock(block: TimelineBlock): void {
    this.editDraft = undefined;
    this.confirmEdit = false;
    this.current = block;
    this.creating = false;
    this.showEditor = false;
    this.confirmDelete = false;
    this.errorMessage = '';
    this.showSheet = true;
  }

  private isSeries(): boolean {
    return this.current.repeat !== undefined && this.current.repeat !== TimelineRepeat.None;
  }

  private editBlock(clock: string): void {
    this.attachmentSession = new TimelineAttachmentSession();
    this.editDraft = undefined;
    this.confirmEdit = false;
    this.initialClock = clock;
    this.newTagPage = false;
    this.errorMessage = '';
    this.confirmDelete = false;
    this.showEditor = true;
  }

  private requestSave(value: TimelineBlock): void {
    if (!this.creating && this.isSeries()) {
      this.editDraft = value;
      this.initialClock = '';
      this.confirmEdit = true;
      this.pendingScope = this.newRepeatPattern() ? TimelineDeleteScope.Following : TimelineDeleteScope.One;
      this.errorMessage = '';
      return;
    }
    this.saveBlock(value);
  }

  private newRepeatPattern(): boolean {
    const repeat = this.editDraft?.repeat ?? TimelineRepeat.None;
    return repeat !== this.current.repeat;
  }

  private editStopsRepeat(): boolean {
    return (this.editDraft?.repeat ?? TimelineRepeat.None) === TimelineRepeat.None;
  }

  private cancelScope(): void {
    if (this.saving) return;
    this.confirmEdit = false;
    this.confirmDelete = false;
    this.errorMessage = '';
  }

  private applyScope(): void {
    if (this.confirmEdit && this.editDraft) {
      let scope = TimelineEditScope.One;
      if (this.pendingScope === TimelineDeleteScope.Following) scope = TimelineEditScope.Following;
      if (this.pendingScope === TimelineDeleteScope.All) scope = TimelineEditScope.All;
      this.saveBlock(this.editDraft, scope);
    } else if (this.confirmDelete) {
      this.deleteBlock();
    }
  }

  private async saveBlock(value: TimelineBlock, scope?: TimelineEditScope): Promise<void> {
    if (this.saving || !this.service) return;
    this.saving = true;
    this.errorMessage = '';
    try {
      let focus: TimelineBlock | undefined;
      if (scope !== undefined) {
        focus = await this.service.saveOccurrence(value, scope, this.current.occurrenceOriginalStart ?? this.current.startAt);
      } else {
        await this.service.save(value, !this.creating);
        const stored = this.service.list().find((block: TimelineBlock) => block.id === value.id);
        if (stored) focus = firstVisibleTimelineOccurrence(stored);
      }
      const enableNotifications = value.reminderMinutes !== undefined &&
        (this.creating || value.reminderMinutes !== this.current.reminderMinutes);
      this.syncReminders(enableNotifications);
      this.finishAttachments();
      if (!this.pageActive) return;
      this.reloadSchedule();
      if (focus) {
        this.selectDay(focus.startAt);
        this.focusAt = focus.startAt;
      }
      this.showSheet = false;
      this.confirmEdit = false;
      this.editDraft = undefined;
    } catch (error) {
      if (this.pageActive) this.errorMessage = '保存失败，草稿已保留，可再次保存。';
    } finally {
      if (this.pageActive) this.saving = false;
      else this.finishAttachments();
    }
  }

  private startDelete(): void {
    this.confirmDelete = true;
    this.pendingScope = TimelineDeleteScope.One;
    this.errorMessage = '';
  }

  private async deleteBlock(): Promise<void> {
    if (this.saving || !this.service) return;
    this.saving = true;
    this.errorMessage = '';
    try {
      const scope = this.isSeries() ? this.pendingScope : TimelineDeleteScope.All;
      await this.service.remove(this.current.id, scope, this.current.occurrenceOriginalStart ?? this.current.startAt);
      this.syncReminders();
      this.finishAttachments();
      if (!this.pageActive) return;
      this.reloadSchedule();
      this.showSheet = false;
    } catch (error) {
      if (this.pageActive) this.errorMessage = '删除失败，请重试。';
    } finally {
      if (this.pageActive) this.saving = false;
    }
  }

  @Builder
  private BlockSheet() {
    if (this.isScopeSheet()) {
      this.ScopeSheet()
    } else if (this.showEditor) {
      TimelineEditor({
        attachmentSession: this.attachmentSession, onAttachmentBusy: (busy: boolean) => { this.importing = busy; },
        initial: this.editDraft ?? this.current, editing: !this.creating, seriesEdit: !this.creating && this.isSeries(),
        initialClock: this.initialClock, newTagPage: $newTagPage,
        tags: this.tags, blocks: this.blocks, onSaveTag: (tag: TimelineTag) => this.saveTag(tag),
        saving: this.saving, errorMessage: this.errorMessage,
        onSave: (value: TimelineBlock) => this.requestSave(value),
        onCancel: () => {
          this.finishAttachments();
          this.editDraft = undefined;
          if (this.creating) this.showSheet = false;
          else this.showEditor = false;
          this.errorMessage = '';
        }
      })
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
    .onClick(() => this.editBlock(endpoint))
  }

  @Builder
  private TagLabel(tag: TimelineTag) {
    Row({ space: Space.sm }) {
      Row().width(8).height(8).borderRadius(4).backgroundColor(tag.color)
      Text(tag.name).fontSize(TypeSize.bodySmall).fontColor(Colors.inkSoft)
    }
  }

  private isScopeSheet(): boolean {
    return this.confirmEdit || (this.confirmDelete && this.isSeries());
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
    .accessibilityText(label + (this.pendingScope === scope ? '，已选中' : ''))
    .onClick(() => { this.pendingScope = scope; this.errorMessage = ''; })
  }

  @Builder
  private ScopeSheet() {
    Scroll() {
      Column() {
        Text(this.confirmEdit ? '修改重复日程' : '删除重复日程')
          .width('100%').fontSize(TypeSize.heading).fontWeight(TypeWeight.semibold).fontColor(Colors.ink)
        Text(this.current.title + ' · ' + this.dateLabel(this.current.startAt) + ' ' + this.clockLabel(this.current.startAt))
          .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: Space.xs, bottom: Space.md }).fontSize(TypeSize.bodySmall)
          .fontColor(Colors.inkSoft).fontFeature(TABULAR_NUMS)
        if (!this.confirmEdit || !this.newRepeatPattern()) {
          this.ScopeOption(TimelineDeleteScope.One, this.confirmEdit ? '仅修改这一次' : '仅删除这一次')
        }
        this.ScopeOption(TimelineDeleteScope.Following, this.confirmEdit ?
          (this.editStopsRepeat() ? '保留这一次，停止以后的重复' : '修改这次及以后') : '删除这次及以后')
        this.ScopeOption(TimelineDeleteScope.All, this.confirmEdit ?
          (this.editStopsRepeat() ? '整个系列改为仅保留这一次' : '修改整个系列') : '删除整个系列')
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage).width('100%').fontSize(TypeSize.meta)
            .fontWeight(TypeWeight.semibold).fontColor(Colors.red).margin({ top: Space.sm })
        }
        Row() {
          Button('取消').type(ButtonType.Normal).constraintSize({ minHeight: 44 })
            .backgroundColor(Color.Transparent).fontSize(TypeSize.body)
            .fontWeight(TypeWeight.regular).fontColor(Colors.inkSoft).borderRadius(Radius.card)
            .padding({ left: Space.md, right: Space.md })
            .onClick(() => this.cancelScope())
          Blank()
          Button(this.confirmEdit ? (this.saving ? '保存中' : '保存修改') : (this.saving ? '删除中' : '确认删除'))
            .type(ButtonType.Normal).constraintSize({ minHeight: 40 })
            .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold)
            .backgroundColor(Colors.red).fontColor(Colors.onRed).borderRadius(Radius.card)
            .padding({ left: Space.lg, right: Space.lg })
            .onClick(() => this.applyScope())
        }.width('100%').constraintSize({ minHeight: 44 }).margin({ top: Space.md })
      }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: Space.page, right: Space.page, top: Space.section, bottom: Space.lg })
    }.width('100%').scrollBar(BarState.Auto).backgroundColor(Colors.card).enabled(!this.saving)
  }

  @Builder
  private BlockDetails() {
    Column() {
      Row() {
        Text(this.dateLabel(this.current.startAt) + ' · 周' +
          WEEKDAYS[(new Date(this.current.startAt).getDay() + 6) % 7])
          .fontSize(TypeSize.bodySmall).fontColor(Colors.inkSoft).fontFeature(TABULAR_NUMS).layoutWeight(1)
        Button('编辑日程').type(ButtonType.Normal).constraintSize({ minHeight: 44 })
          .padding({ left: Space.sm, right: Space.sm })
          .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink).backgroundColor(Color.Transparent).borderRadius(Radius.card)
          .onClick(() => this.editBlock(''))
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
          Text('删除这段日程？')
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
          Button('删除日程').type(ButtonType.Normal).constraintSize({ minHeight: 44 })
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
      if (!this.service || this.loadError) this.load();
      else if (this.abilityContext) cleanTimelineAttachmentFiles(this.abilityContext, this.blocks);
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
          this.getUIContext().getPromptAction().showToast({ message: this.tab === HomeTab.Cards ?
            '点卡片标题打开事项，上下推卡片翻找。点底栏卡片图标回到开头。' : '下拉日期展开月历，点便签查看日程。' });
        })
        this.HeaderButton(HomeGlyph.Search, '搜索事项', () => {
          this.searchOpen = this.tab === HomeTab.Timeline || !this.searchOpen;
          this.switchTab(HomeTab.Cards);
        })
        this.HeaderButton(HomeGlyph.Add, this.tab === HomeTab.Timeline ? '添加日程' : '新建事项', () => {
          if (this.tab === HomeTab.Timeline) this.createBlock();
          else router.pushUrl({ url: 'pages/CreateMatter' });
        }, !MatterServices.isPreview() && (this.tab !== HomeTab.Timeline || (!this.loadError && !this.saving)), true)
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
    if (this.loadError) {
      Column({ space: Space.sm }) {
        Text('日程读取失败（' + this.loadError + '）').fontSize(TypeSize.bodySmall)
          .fontWeight(TypeWeight.semibold).fontColor(Colors.red)
        Button('重新读取').type(ButtonType.Normal).constraintSize({ minHeight: 40 })
          .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink).backgroundColor(Colors.wash).borderRadius(Radius.card)
          .padding({ left: Space.lg, right: Space.lg })
          .onClick(() => { this.load(); if (!this.loadError) this.syncReminders(); })
      }.width('100%').alignItems(HorizontalAlign.Start).padding(Space.page)
    } else {
      Column() {
        TimelineGrid({ day: this.day, today: this.today, blocks: this.blocks, tags: this.tags, focusAt: this.focusAt,
          bottomInset: DOCK_CLEARANCE,
          selectedId: this.showSheet && !this.creating ? this.current.id : '',
          selectedStartAt: this.current.occurrenceOriginalStart ?? this.current.startAt,
          onSelect: (block: TimelineBlock) => this.selectBlock(block) })
      }.layoutWeight(1).width('100%').clip(true)
      .accessibilityLevel(this.calendarLevel === 2 ? 'no-hide-descendants' : 'auto')
      .parallelGesture(PanGesture({ direction: PanDirection.Horizontal, distance: 18 })
        .onActionEnd((event: GestureEvent) => {
          if (Math.abs(event.offsetX) >= 36 && Math.abs(event.offsetX) > Math.abs(event.offsetY) * 1.5) {
            this.selectDay(localDayStart(this.day, event.offsetX < 0 ? 1 : -1));
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
            day: this.day, today: this.today, month: $browseMonth, level: $calendarLevel,
            availableHeight: this.contentHeight, blocks: this.blocks, tags: this.tags,
            showScheduleRings: this.tab === HomeTab.Timeline, readError: this.loadError,
            onRetry: () => { this.load(); if (this.tab === HomeTab.Timeline) this.syncReminders(); },
            onSelectDay: (day: number) => this.selectDay(day),
            onSelectBlock: (block: TimelineBlock) => this.openCalendarBlock(block)
          }).visibility(this.tab === HomeTab.Settings ? Visibility.None : Visibility.Visible)
          Stack() {
            MatterCardDeck({ searchOpen: this.searchOpen, revision: this.matterRevision, homeRequest: this.deckHomeRequest,
              pageHeight: this.contentHeight + HOME_HEADER_HEIGHT,
              onBrowseChange: (awayFromFront: boolean) => { this.deckAwayFromFront = awayFromFront; } })
              .visibility(this.tab === HomeTab.Cards && !this.matterReadError && !this.matterLoading ?
                Visibility.Visible : Visibility.None)
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
          HomeDock({ tab: this.tab, onSelect: (tab: HomeTab) => {
            if (tab === HomeTab.Cards && tab === this.tab && !this.showSheet) this.deckHomeRequest++;
            else this.switchTab(tab);
          } }).margin({ bottom: DOCK_MARGIN })
        }
      }.width('100%').layoutWeight(1).clip(true)
    }.height('100%').width('100%').backgroundColor(Colors.bg)
    .clip(true)
    .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
      this.contentHeight = Math.max(0, Number(size.height) - HOME_HEADER_HEIGHT);
    })
    .bindSheet($$this.showSheet, this.BlockSheet(), {
      height: this.isScopeSheet() ? SheetSize.FIT_CONTENT : (this.showEditor ? SheetSize.LARGE : SheetSize.MEDIUM),
      showClose: false, dragBar: !this.isScopeSheet(),
      backgroundColor: Colors.card,
      maskColor: '#59191714',
      onWillDismiss: (action: DismissSheetAction) => {
        if (!this.saving && !this.importing) {
          if (this.isScopeSheet()) this.cancelScope();
          else if (this.showEditor && this.newTagPage) this.newTagPage = false;
          else {
            this.finishAttachments();
            action.dismiss();
          }
        }
      }
    })
  }
}
