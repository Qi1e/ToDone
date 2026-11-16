import { hilog } from '@kit.PerformanceAnalysisKit';
import { timelineReadCode } from '../domain/TimelineReadError';
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { TimelineReminders } from '../application/TimelineReminders';
import { TimelineAttachmentSession, cleanTimelineAttachmentFiles } from '../application/TimelineAttachmentFiles';
import { TimelineAttachmentList } from '../components/TimelineAttachments';
import { TimelineLinkedNote } from '../components/TimelineLinkedNote';
import { TimelineServices } from '../application/TimelineServices';
import { TimelineBlock, TimelineDeleteScope, TimelineEditScope, TimelineRepeat, TimelineService, TimelineTag, timelineRepeatLabel, timelineReminderLabel } from '../contracts/TimelineService';
import { formatDate, pad2 } from '../common/DateFormat';
import { Colors, Radius, Space } from '../common/Theme';
import { TimelineEditor } from '../components/TimelineEditor';
import { TimelineBrowseDates } from '../components/TimelineBrowseDates';
import { monthStart } from '../components/TimelineDatePicker';
import { TimelineGrid } from '../components/TimelineGrid';
import { createId } from '../model/Defaults';
import { localDayStart, timelineBlocksForDay } from '../domain/TimelineLayout';
import { firstVisibleTimelineOccurrence } from '../domain/TimelineRecurrence';

interface HomeCalendarRoute {
  day?: number;
  blockId?: string;
  originalStart?: number;
}

const WEEKDAYS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

@Entry
@Component
struct Timeline {
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
    try {
      const route = router.getParams() as HomeCalendarRoute | undefined;
      if (route && typeof route.day === 'number' && Number.isFinite(new Date(route.day).getTime())) {
        this.selectDay(route.day);
        this.calendarRoute = route;
      }
    } catch (error) {
      // 单页预览可以没有路由栈，沿用默认日期。
    }
    this.load();
  }

  aboutToDisappear(): void {
    this.pageActive = false;
    if (!this.saving) this.finishAttachments();
    this.stopMidnightTimer();
  }

  onPageShow(): void {
    if (this.loadError) this.load();
    this.refreshToday();
  }

  onPageHide(): void {
    this.stopMidnightTimer();
  }

  onBackPress(): boolean {
    if (this.showSheet || this.calendarLevel !== 2) return false;
    this.calendarLevel = 1;
    return true;
  }

  private stopMidnightTimer(): void {
    clearTimeout(this.midnightTimer);
    this.midnightTimer = -1;
  }

  private refreshToday(): void {
    this.stopMidnightTimer();
    const now = Date.now();
    this.today = localDayStart(now);
    this.syncReminders();
    this.midnightTimer = setTimeout(() => this.refreshToday(), localDayStart(now, 1) - now);
  }

  private load(): void {
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
    if (!this.showSheet && this.abilityContext) cleanTimelineAttachmentFiles(this.abilityContext, this.blocks);
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
        this.day = localDayStart(focus.startAt);
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
      Column({ space: 2 }) {
        Text(label).fontSize(13).fontColor(Colors.subText)
        Text(this.clockLabel(stamp)).fontSize(26).fontWeight(FontWeight.Medium).fontColor('#214F93')
        if (localDayStart(this.current.startAt) !== localDayStart(this.current.endAt)) {
          Text(this.dateLabel(stamp)).fontSize(13).fontColor(Colors.subText)
        }
      }.alignItems(HorizontalAlign.Start).width('100%')
    }
    .layoutWeight(1).height(localDayStart(this.current.startAt) === localDayStart(this.current.endAt) ? 72 : 92)
    .padding({ top: 4, bottom: 4 }).borderRadius(Radius.small)
    .backgroundColor(Color.Transparent)
    .accessibilityText('调整' + label + '时间，' + this.dateLabel(stamp) + ' ' + this.clockLabel(stamp))
    .onClick(() => this.editBlock(endpoint))
  }

  @Builder
  private TagLabel(tag: TimelineTag) {
    Row({ space: Space.small }) {
      Row().width(9).height(9).borderRadius(5).backgroundColor(tag.color)
      Text(tag.name).fontSize(14).fontColor(Colors.subText)
    }
  }

  private isScopeSheet(): boolean {
    return this.confirmEdit || (this.confirmDelete && this.isSeries());
  }

  @Builder
  private ScopeOption(scope: TimelineDeleteScope, label: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: Space.small }) {
        Text(label).fontSize(16).fontColor(Colors.text).layoutWeight(1)
        Stack({ alignContent: Alignment.Center }) {
          if (this.pendingScope === scope) {
            Row().width(8).height(8).borderRadius(4).backgroundColor(Colors.primary)
          }
        }.width(18).height(18).borderRadius(9)
        .border({ width: 1.5, color: this.pendingScope === scope ? Colors.primary : Colors.subText })
      }.width('100%')
    }.width('100%').constraintSize({ minHeight: 44 })
    .padding({ left: 0, right: Space.tiny, top: Space.tiny, bottom: Space.tiny })
    .backgroundColor(Color.Transparent)
    .accessibilityText(label + (this.pendingScope === scope ? '，已选中' : ''))
    .onClick(() => { this.pendingScope = scope; this.errorMessage = ''; })
  }

  @Builder
  private ScopeSheet() {
    Scroll() {
      Column() {
        Text(this.confirmEdit ? '修改重复日程' : '删除重复日程')
          .width('100%').fontSize(20).fontWeight(FontWeight.Medium).fontColor(Colors.text)
        Text(this.current.title + ' · ' + this.dateLabel(this.current.startAt) + ' ' + this.clockLabel(this.current.startAt))
          .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: Space.tiny, bottom: Space.small }).fontSize(14).fontColor(Colors.subText)
        if (!this.confirmEdit || !this.newRepeatPattern()) {
          this.ScopeOption(TimelineDeleteScope.One, this.confirmEdit ? '仅修改这一次' : '仅删除这一次')
        }
        this.ScopeOption(TimelineDeleteScope.Following, this.confirmEdit ?
          (this.editStopsRepeat() ? '保留这一次，停止以后的重复' : '修改这次及以后') : '删除这次及以后')
        this.ScopeOption(TimelineDeleteScope.All, this.confirmEdit ?
          (this.editStopsRepeat() ? '整个系列改为仅保留这一次' : '修改整个系列') : '删除整个系列')
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage).width('100%').fontSize(14).fontColor(Colors.danger)
        }
        Row() {
          Button('取消').backgroundColor(Color.Transparent).fontColor(Colors.text)
            .onClick(() => this.cancelScope())
          Blank()
          Button(this.confirmEdit ? (this.saving ? '保存中' : '保存修改') : (this.saving ? '删除中' : '确认删除'))
            .backgroundColor(this.confirmEdit ? Colors.primary : Colors.danger).fontColor(Color.White)
            .onClick(() => this.applyScope())
        }.width('100%').constraintSize({ minHeight: 44 }).margin({ top: Space.small })
      }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: Space.section, right: Space.section, top: Space.section, bottom: Space.normal })
    }.width('100%').scrollBar(BarState.Auto).enabled(!this.saving)
  }

  @Builder
  private BlockDetails() {
    Column() {
      Row() {
        Text(this.dateLabel(this.current.startAt) + ' · 周' +
          WEEKDAYS[(new Date(this.current.startAt).getDay() + 6) % 7])
          .fontSize(14).fontColor(Colors.subText).layoutWeight(1)
        Button('编辑日程').height(44).padding({ left: Space.small, right: Space.small })
          .fontSize(15).fontColor(Colors.primary).backgroundColor(Color.Transparent)
          .onClick(() => this.editBlock(''))
      }.width('100%')
      Scroll() {
        Column({ space: Space.normal }) {
          Text(this.current.title).width('100%').fontSize(25)
            .fontWeight(FontWeight.Bold).fontColor(Colors.text)
          if (this.isSeries()) {
            Text(timelineRepeatLabel(this.current.repeat ?? TimelineRepeat.None) + '重复')
              .width('100%').fontSize(14).fontColor(Colors.subText)
          }
          ForEach(this.tags.filter((tag: TimelineTag) => tag.id === this.current.tagId), (tag: TimelineTag) => {
            this.TagLabel(tag)
          }, (tag: TimelineTag) => tag.id)
          Column() {
            Row({ space: Space.large }) {
              this.DetailTime('开始', this.current.startAt, 'start')
              Text('→').fontSize(18).fontColor(Colors.subText)
              this.DetailTime('结束', this.current.endAt, 'end')
            }.width('100%')
            Text(this.durationDescription()).fontSize(13).fontColor(Colors.subText)
          }.width('100%').alignItems(HorizontalAlign.Start)
          if (this.current.reminderMinutes !== undefined) {
            Text('提醒 · ' + timelineReminderLabel(this.current.reminderMinutes))
              .width('100%').fontSize(14).fontColor(Colors.subText)
          }
          if (this.current.note.trim().length > 0 || (this.current.attachments?.length ?? 0) > 0) {
            Divider().color(Colors.border)
            Text('备注').fontSize(13).fontColor(Colors.subText)
            if (this.current.note.trim().length > 0) {
              TimelineLinkedNote({ value: this.current.note })
            }
            if ((this.current.attachments?.length ?? 0) > 0) {
              TimelineAttachmentList({ items: this.current.attachments ?? [] })
            }
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: Space.normal })
      }.layoutWeight(1).width('100%').align(Alignment.TopStart)
      if (this.errorMessage.length > 0) {
        Text(this.errorMessage).width('100%').fontColor(Colors.danger).fontSize(14)
      }
      Divider().color(Colors.border)
      Row() {
        if (this.confirmDelete) {
          Text('删除这段日程？')
            .fontSize(14).fontColor(Colors.text).layoutWeight(1)
          Button('保留').fontColor(Colors.text).backgroundColor(Color.Transparent)
            .onClick(() => { this.confirmDelete = false; this.errorMessage = ''; })
          Button(this.saving ? '删除中' : '确认删除').fontColor(Color.White).backgroundColor(Colors.danger)
            .onClick(() => { this.deleteBlock(); })
        } else {
          Button('删除日程').height(44).padding({ left: 0, right: Space.normal })
            .backgroundColor(Color.Transparent).fontColor(Colors.danger).fontSize(14)
            .onClick(() => this.startDelete())
          Blank()
          Button('收起').height(44).fontSize(14).fontColor(Colors.text).backgroundColor(Color.Transparent)
            .onClick(() => { this.showSheet = false; })
        }
      }.width('100%').padding({ top: Space.tiny })
    }
    .enabled(!this.saving).alignItems(HorizontalAlign.Start).width('100%').height('100%')
    .padding({ left: Space.section, right: Space.section, top: Space.tiny, bottom: Space.small })
    .backgroundColor(Colors.surface)
  }

  private durationDescription(): string {
    const minutes = Math.round((this.current.endAt - this.current.startAt) / 60000);
    const hours = Math.floor(minutes / 60);
    return '共 ' + (hours > 0 ? hours + ' 小时' : '') +
      (minutes % 60 > 0 ? (hours > 0 ? ' ' : '') + (minutes % 60) + ' 分钟' : '');
  }

  build() {
    Column() {
      Row({ space: Space.small }) {
        Button('‹ 事项').fontColor(Colors.subText).backgroundColor(Color.Transparent)
          .onClick(() => router.back())
        Text('时间线').layoutWeight(1).fontSize(22).fontWeight(FontWeight.Bold).fontColor(Colors.text)
        Button({ type: ButtonType.Circle }) {
          Stack({ alignContent: Alignment.Center }) {
            Row().width(18).height(2).borderRadius(1).backgroundColor(Colors.primary)
            Row().width(2).height(18).borderRadius(1).backgroundColor(Colors.primary)
          }.width(24).height(24)
        }
        .width(44).height(44).padding(0).accessibilityText('添加日程')
        .enabled(!this.loadError && !this.saving).backgroundColor(Colors.surfaceSoft)
        .onClick(() => this.createBlock())
      }.width('100%').padding({ left: Space.small, right: Space.small, top: 2, bottom: 2 })
      if (this.reminderStatus.length > 0) {
        Row({ space: Space.small }) {
          Text(this.reminderStatus).fontSize(13).fontColor(Colors.subText).layoutWeight(1)
          Button('同步提醒').height(36).padding({ left: Space.small, right: Space.small })
            .backgroundColor(Color.Transparent).fontColor(Colors.primary).onClick(() => { this.syncReminders(true); })
        }.width('100%').padding({ left: Space.normal, right: Space.small })
      }
      Column() {
        TimelineBrowseDates({
          day: this.day, month: $browseMonth, today: this.today, blocks: this.blocks, tags: this.tags,
          availableHeight: this.contentHeight, level: $calendarLevel, readError: this.loadError,
          onRetry: () => { this.load(); if (!this.loadError) this.syncReminders(); },
          onSelectDay: (day: number) => this.selectDay(day),
          onSelectBlock: (block: TimelineBlock) => this.selectBlock(block)
        })
        if (this.loadError) {
          Text('日程读取失败（' + this.loadError + '）').fontColor(Colors.danger).margin(Space.large)
          Button('重新读取').onClick(() => { this.load(); if (!this.loadError) this.syncReminders(); })
        } else {
          Column() {
            TimelineGrid({ day: this.day, today: this.today, blocks: this.blocks, tags: this.tags, focusAt: this.focusAt,
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
      }.width('100%').layoutWeight(1).clip(true)
      .onAreaChange((_old: Area, area: Area) => { this.contentHeight = Number(area.height); })
    }
    .height('100%').width('100%').backgroundColor(Colors.surface)
    .bindSheet($$this.showSheet, this.BlockSheet(), {
      height: this.isScopeSheet() ? SheetSize.FIT_CONTENT : (this.showEditor ? SheetSize.LARGE : SheetSize.MEDIUM),
      showClose: false, dragBar: !this.isScopeSheet(),
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
