import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { MatterServices } from '../application/MatterServices';
import { TimelineAttachmentSession } from '../application/TimelineAttachmentFiles';
import { TimelineReminders } from '../application/TimelineReminders';
import {
  dateSummary,
  daysUntil,
  formatClock,
  formatDate,
  timeConfigTitle
} from '../common/DateFormat';
import { Colors, Radius, Space, TABULAR_NUMS, TypeSize, TypeWeight } from '../common/Theme';
import { MatterDateEditor } from '../components/MatterDateEditor';
import { ModuleIcon } from '../components/ModuleIcon';
import { TimelineAttachmentButton, TimelineAttachmentList } from '../components/TimelineAttachments';
import { TimelineLinkedNote } from '../components/TimelineLinkedNote';
import { TimelineTagForm } from '../components/TimelineTags';
import { MatterService } from '../contracts/MatterService';
import {
  TimelineAttachment,
  TimelineEditScope,
  TimelineRepeat,
  timelineRepeatLabel,
  timelineReminderLabel,
  TimelineTag
} from '../contracts/TimelineService';
import { EditorDraft, EditorItem, invalidEditorField } from '../domain/MatterEditor';
import { matterErrorMessage } from '../domain/MatterSnapshot';
import { localDayStart } from '../domain/TimelineLayout';
import { TimelineNotePart, timelineNoteParts } from '../domain/TimelineNoteLinks';
import { createId, MODULE_OPTIONS, moduleLabel } from '../model/Defaults';
import {
  ActiveCounterMode,
  DayCountMode,
  DeadlineConfig,
  Matter,
  ModuleOption,
  ModuleType,
  TimeSpanMode
} from '../model/Types';
import { EditorDraftStorage } from '../store/EditorDraftStorage';
import { MatterStore } from '../store/MatterStore';

export interface EditorRoute {
  matterId?: string;
  occurrenceStart?: number;
  ownerMatterId?: string;
  fromTimeline?: boolean;
  presetDay?: number;
  presetStartAt?: number;
  presetEndAt?: number;
  focusClock?: string;
}

function hydrateSavedDraft(raw: string): EditorDraft {
  const parsed = JSON.parse(raw) as Partial<EditorDraft>;
  const base = new EditorDraft();
  if (typeof parsed.id === 'string' && parsed.id) base.id = parsed.id;
  if (typeof parsed.token === 'string') base.token = parsed.token;
  if (typeof parsed.editing === 'boolean') base.editing = parsed.editing;
  if (typeof parsed.occurrenceStart === 'number') base.occurrenceStart = parsed.occurrenceStart;
  if (typeof parsed.isSeries === 'boolean') base.isSeries = parsed.isSeries;
  if (typeof parsed.originalRepeat === 'string') base.originalRepeat = parsed.originalRepeat as TimelineRepeat;
  if (typeof parsed.baseline === 'string') base.baseline = parsed.baseline;
  if (typeof parsed.title === 'string') base.title = parsed.title;
  if (Array.isArray(parsed.types)) {
    const clean: ModuleType[] = [];
    for (const item of parsed.types) {
      const mapped = item === ModuleType.EventRecord ? ModuleType.Counter : item;
      if (mapped === ModuleType.Countdown || mapped === ModuleType.Progress) continue;
      if (!clean.includes(mapped)) clean.push(mapped);
    }
    base.types = clean;
  }
  if (parsed.span === 'all_day' || parsed.span === 'range' || parsed.span === 'point') base.span = parsed.span;
  if (typeof parsed.timestamp === 'number' && Number.isFinite(parsed.timestamp)) base.timestamp = parsed.timestamp;
  if (typeof parsed.endAt === 'number' && Number.isFinite(parsed.endAt)) base.endAt = parsed.endAt;
  else base.endAt = base.timestamp + 3600000;
  if (parsed.dayCountMode === 'none' || parsed.dayCountMode === 'countdown' || parsed.dayCountMode === 'elapsed') {
    base.dayCountMode = parsed.dayCountMode;
  }
  if (typeof parsed.reminderMinutes === 'number') base.reminderMinutes = parsed.reminderMinutes;
  if (typeof parsed.repeat === 'string') base.repeat = parsed.repeat as TimelineRepeat;
  if (typeof parsed.tagId === 'string') base.tagId = parsed.tagId;
  if (parsed.counterMode === 'tally' || parsed.counterMode === 'amount' || parsed.counterMode === 'daily_once') {
    base.counterMode = parsed.counterMode;
  }
  if (typeof parsed.unit === 'string') base.unit = parsed.unit;
  if (typeof parsed.initial === 'string') base.initial = parsed.initial;
  if (typeof parsed.step === 'string') base.step = parsed.step;
  if (typeof parsed.step2 === 'string') base.step2 = parsed.step2;
  if (typeof parsed.note === 'string') base.note = parsed.note;
  if (Array.isArray(parsed.attachments)) base.attachments = parsed.attachments;
  if (Array.isArray(parsed.items)) base.items = parsed.items;
  if (typeof parsed.pending === 'string') base.pending = parsed.pending;
  return base;
}

@Entry
@Component
struct CreateMatter {
  private service: MatterService = MatterServices.getService();
  private scroller: Scroller = new Scroller();
  private storage?: EditorDraftStorage;
  private attachmentSession: TimelineAttachmentSession = new TimelineAttachmentSession();
  private draftKey: string = '';
  private ownerId: string = '';
  private fromTimeline: boolean = false;
  private focusClock: string = '';
  private ready: boolean = false;
  private timer: number = -1;
  private original: string = '';

  @State compactWidth: boolean = false;
  @State resumed: boolean = false;
  @State draft: EditorDraft = new EditorDraft();
  @State tags: TimelineTag[] = [];
  @State newTagOpen: boolean = false;
  @State importingAttachment: boolean = false;
  @State previewLinks: boolean = false;

  // 同步绑定给 MatterDateEditor 的时间状态（毫秒时间戳唯一数据源）
  @State @Watch('timeFieldChanged') startAt: number = Date.now();
  @State @Watch('timeFieldChanged') endAt: number = Date.now() + 3600000;
  @State @Watch('timeFieldChanged') span: TimeSpanMode = 'all_day';
  @State @Watch('timeFieldChanged') dayCountMode: DayCountMode = 'countdown';
  @State @Watch('timeFieldChanged') reminderMinutes: number = -1;
  @State @Watch('timeFieldChanged') repeat: TimelineRepeat = TimelineRepeat.None;

  @State expanded: string = '';
  @State invalid: string = '';
  @State feedback: string = '';
  @State busy: boolean = false;
  @State unavailable: boolean = false;
  @State picking: boolean = false;
  @State candidates: Matter[] = [];
  @State editingItemId: string = '';
  @State titleFocused: boolean = false;
  @State confirmExit: boolean = false;
  @State confirmScope: boolean = false;
  @State pendingScope: TimelineEditScope = TimelineEditScope.One;

  aboutToAppear(): void {
    this.initialize();
  }

  aboutToDisappear(): void {
    if (!MatterServices.isPreview()) {
      const context = getContext(this) as common.UIAbilityContext;
      this.attachmentSession.finishMatter(context, MatterStore.getInstance().allReferencedAttachments());
    }
  }

  private async initialize(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    this.busy = true;
    try {
      await MatterServices.initialize(context);
      this.unavailable = false;
    } catch (error) {
      this.unavailable = true;
      this.feedback = matterErrorMessage(error as Error);
      return;
    } finally {
      this.busy = false;
    }

    this.tags = this.service.listTags();
    const route = router.getParams() as EditorRoute | undefined;
    const id = route?.matterId ?? '';
    const occStart = route?.occurrenceStart;
    this.ownerId = route?.ownerMatterId ?? '';
    this.fromTimeline = route?.fromTimeline ?? false;
    this.focusClock = route?.focusClock ?? '';
    this.draftKey = id
      ? (occStart !== undefined ? `edit_${id}_${occStart}` : `edit_${id}`)
      : this.ownerId ? `owner_${this.ownerId}` : (this.fromTimeline ? 'new_timeline' : 'new');

    const initial = this.service.loadEditor(id, occStart);
    if (!initial) {
      this.unavailable = true;
      this.feedback = '原事项已删除';
      return;
    }

    // 新建时根据入口参数预填日期或时间段
    if (!id) {
      if (route?.presetStartAt !== undefined && route?.presetEndAt !== undefined) {
        initial.timestamp = route.presetStartAt;
        initial.endAt = route.presetEndAt;
      } else if (route?.presetDay !== undefined && Number.isFinite(route.presetDay)) {
        const dayDate = new Date(localDayStart(route.presetDay));
        const now = new Date();
        const isTodayDay = dayDate.getFullYear() === now.getFullYear() &&
          dayDate.getMonth() === now.getMonth() && dayDate.getDate() === now.getDate();
        dayDate.setHours(isTodayDay ? Math.min(22, now.getHours() + 1) : 9, 0, 0, 0);
        initial.timestamp = dayDate.getTime();
        initial.endAt = dayDate.getTime() + 3600000;
      }
      if (this.fromTimeline) {
        initial.types = [ModuleType.Deadline];
        initial.span = 'range';
        initial.dayCountMode = 'none';
        this.expanded = ModuleType.Deadline;
      }
    } else if (this.focusClock === 'start' || this.focusClock === 'end') {
      this.expanded = ModuleType.Deadline;
    }

    this.original = JSON.stringify(initial);
    this.draft = initial;
    try {
      if (!MatterServices.isPreview()) {
        this.storage = new EditorDraftStorage(context, this.draftKey);
        const saved = this.storage.read();
        if (saved) {
          this.draft = hydrateSavedDraft(saved);
          this.resumed = true;
        }
      }
    } catch (error) {
      this.feedback = '无法读取草稿';
    }

    this.attachmentSession.retain(this.draft.attachments);
    this.syncStateFromDraft();
    this.previewLinks = this.noteHasUrl(this.draft.note);
    this.ready = true;
  }

  private syncStateFromDraft(): void {
    this.startAt = this.draft.timestamp;
    this.endAt = this.draft.endAt;
    this.span = this.draft.span;
    this.dayCountMode = this.draft.dayCountMode;
    this.reminderMinutes = this.draft.reminderMinutes;
    this.repeat = this.draft.repeat;
  }

  private timeFieldChanged(): void {
    if (!this.ready) return;
    this.draft.timestamp = this.startAt;
    this.draft.endAt = this.endAt;
    this.draft.span = this.span;
    this.draft.dayCountMode = this.dayCountMode;
    this.draft.reminderMinutes = this.reminderMinutes;
    this.draft.repeat = this.repeat;
    this.changed();
  }

  private noteHasUrl(text: string): boolean {
    return timelineNoteParts(text).some((part: TimelineNotePart) => part.href !== undefined);
  }

  private changed(): void {
    this.invalid = '';
    this.feedback = '';
    clearTimeout(this.timer);
    this.timer = setTimeout(() => { this.writeDraft(); }, 180);
  }

  private async writeDraft(): Promise<boolean> {
    clearTimeout(this.timer);
    try {
      if (!this.storage && !MatterServices.isPreview()) throw new Error('storage');
      await this.storage?.write(JSON.stringify(this.draft));
      return true;
    } catch (error) {
      this.feedback = '草稿写入失败，请重试';
      return false;
    }
  }

  private async leave(discard: boolean): Promise<void> {
    clearTimeout(this.timer);
    if (discard) {
      try {
        await this.storage?.write('');
      } catch (error) {
        this.feedback = '清除草稿失败，请重试';
        return;
      }
    } else if (!await this.writeDraft()) return;
    this.ready = false;
    router.back();
  }

  onPageHide(): void {
    if (this.ready && this.original !== JSON.stringify(this.draft)) this.writeDraft();
  }

  onBackPress(): boolean {
    if (this.busy || this.importingAttachment) return true;
    if (this.newTagOpen) {
      this.newTagOpen = false;
      return true;
    }
    if (this.confirmScope) {
      this.confirmScope = false;
      return true;
    }
    if (this.confirmExit) {
      this.confirmExit = false;
      return true;
    }
    if (this.unavailable || this.original === JSON.stringify(this.draft)) return false;
    this.confirmExit = true;
    return true;
  }

  private restartDraft(): void {
    this.draft = hydrateSavedDraft(this.original);
    this.ready = false;
    this.syncStateFromDraft();
    this.ready = true;
    this.expanded = this.fromTimeline ? ModuleType.Deadline : '';
    this.invalid = '';
    this.feedback = '';
    this.editingItemId = '';
    this.resumed = false;
    this.previewLinks = this.noteHasUrl(this.draft.note);
    this.changed();
  }

  private toggleExpand(type: ModuleType): void {
    if (this.busy || this.draft.token) return;
    if (this.expanded === type) {
      this.expanded = '';
      return;
    }
    this.expanded = type;
    this.scrollToModule(type);
  }

  private activate(type: ModuleType): void {
    if (!this.draft.types.includes(type)) {
      this.draft.types = this.draft.types.concat(type);
      if (type === ModuleType.Tag && !this.draft.tagId && this.tags.length > 0) {
        this.draft.tagId = this.tags[0].id;
      }
      this.changed();
    }
    this.expanded = type;
    this.picking = false;
    this.scrollToModule(type);
  }

  private disable(type: ModuleType): void {
    this.draft.types = this.draft.types.filter((item: ModuleType) => item !== type);
    if (this.expanded === type) this.expanded = '';
    this.changed();
  }

  private moduleStartIndex(): number {
    return this.resumed ? 4 : 3;
  }

  private scrollToModule(type: ModuleType): void {
    const offset = this.draft.types.indexOf(type);
    if (offset < 0) return;
    const index = this.moduleStartIndex() + offset;
    setTimeout(() => { this.scroller.scrollToIndex(index, false, ScrollAlign.START); }, 0);
  }

  private scrollToTitle(): void {
    setTimeout(() => {
      this.scroller.scrollToIndex(this.resumed ? 2 : 1, false, ScrollAlign.START);
    }, 0);
  }

  private needsScopePrompt(): boolean {
    return this.draft.editing && this.draft.isSeries && this.draft.occurrenceStart !== undefined &&
      this.draft.types.includes(ModuleType.Deadline) && this.draft.span === 'range';
  }

  private changedRepeatFrequency(): boolean {
    return this.draft.repeat !== TimelineRepeat.None && this.draft.repeat !== this.draft.originalRepeat;
  }

  private stopsRepeat(): boolean {
    return this.draft.repeat === TimelineRepeat.None && this.draft.originalRepeat !== TimelineRepeat.None;
  }

  private requestSave(): void {
    if (this.busy || this.importingAttachment) return;
    this.invalid = invalidEditorField(this.draft);
    if (this.invalid) {
      if (this.invalid === 'title') {
        this.feedback = '请填写事项名称';
        this.scrollToTitle();
      } else {
        if (this.invalid === ModuleType.Deadline) {
          this.feedback = this.draft.span === 'range' && !(this.draft.endAt > this.draft.timestamp)
            ? '结束时间须晚于开始时间'
            : '正数日的起始日期不能晚于今天';
        }
        if (this.invalid === ModuleType.Tag) this.feedback = '请选择一个颜色标签';
        if (this.invalid === ModuleType.Note) this.feedback = '请填写备注文字或添加附件';
        if (this.invalid === ModuleType.Counter) this.feedback = '初始数值须非负，快捷步长须大于零';
        if (this.invalid === ModuleType.Checklist) this.feedback = '请填写或移除空列表项';
        this.expanded = this.invalid;
        this.scrollToModule(this.invalid as ModuleType);
      }
      return;
    }

    if (this.needsScopePrompt() && !this.draft.token) {
      this.pendingScope = this.changedRepeatFrequency() || this.stopsRepeat()
        ? TimelineEditScope.Following
        : TimelineEditScope.One;
      this.confirmScope = true;
      return;
    }
    this.executeSave();
  }

  private async executeSave(scope?: TimelineEditScope): Promise<void> {
    if (this.busy) return;
    if (scope !== undefined) {
      this.draft.editScope = scope;
    }
    this.busy = true;
    try {
      if (!this.draft.token) this.draft.token = createId('save');
      if (!await this.writeDraft()) {
        this.draft.token = '';
        return;
      }
      const wasEditing = this.draft.editing;
      const result = await this.service.saveEditor(this.draft, this.ownerId);
      if (!result.success) {
        if (!result.matterId) {
          this.draft.token = '';
          await this.writeDraft();
        }
        this.feedback = result.message;
        return;
      }

      if (!MatterServices.isPreview()) {
        const context = getContext(this) as common.UIAbilityContext;
        const store = MatterStore.getInstance();
        const askReminderPerm = this.draft.types.includes(ModuleType.Deadline) && this.draft.reminderMinutes >= 0;
        TimelineReminders.sync(context, store.reminderBlocks(), askReminderPerm).catch(() => {});
        const savedMatter = store.findMatter(result.matterId);
        if (!wasEditing && !this.fromTimeline && !this.ownerId && savedMatter && store.isLightSchedule(savedMatter)) {
          AppStorage.setOrCreate('todone_focus_schedule_day', localDayStart(this.draft.timestamp));
        }
      }
      MatterServices.requestCardRefresh();
      await this.leave(true);
    } catch (error) {
      this.feedback = '保存未完成，请重试';
    } finally {
      this.busy = false;
    }
  }

  private currentDeadlineConfig(): DeadlineConfig {
    return {
      timestamp: this.draft.timestamp,
      endAt: this.draft.span === 'range' ? this.draft.endAt : undefined,
      span: this.draft.span,
      dayCountMode: this.draft.dayCountMode,
      hasTime: this.draft.span === 'range' || this.draft.span === 'point',
      reminderMinutes: this.draft.reminderMinutes >= 0 ? this.draft.reminderMinutes : undefined,
      repeat: this.draft.repeat !== TimelineRepeat.None ? this.draft.repeat : undefined
    };
  }

  private moduleTitle(type: ModuleType): string {
    if (type === ModuleType.Deadline) {
      return timeConfigTitle(this.currentDeadlineConfig());
    }
    if (type === ModuleType.Counter) {
      if (this.draft.counterMode === 'tally') return '计次';
      if (this.draft.counterMode === 'daily_once') return '每日打卡';
      return '计量计数';
    }
    if (type === ModuleType.Tag) {
      const selected = this.tags.find((t: TimelineTag) => t.id === this.draft.tagId);
      return selected ? `标签 · ${selected.name}` : '标签';
    }
    return moduleLabel(type);
  }

  private hasResult(type: ModuleType): boolean {
    if (type === ModuleType.Deadline) {
      if (this.draft.span === 'range' && !(this.draft.endAt > this.draft.timestamp)) return false;
      if (this.draft.dayCountMode === 'elapsed' && daysUntil(this.draft.timestamp) > 0) return false;
      return true;
    }
    if (type === ModuleType.Tag) {
      return this.tags.some((t: TimelineTag) => t.id === this.draft.tagId);
    }
    if (type === ModuleType.Counter) {
      if (this.draft.counterMode === 'daily_once') return true;
      const initial = Number(this.draft.initial);
      const step = Number(this.draft.step);
      return this.draft.initial.trim().length > 0 && Number.isFinite(initial) && initial >= 0 &&
        this.draft.step.trim().length > 0 && Number.isFinite(step) && step > 0;
    }
    if (type === ModuleType.Checklist) return this.draft.items.length > 0;
    if (type === ModuleType.Note) return this.draft.note.trim().length > 0 || this.draft.attachments.length > 0;
    return false;
  }

  private summary(type: ModuleType): string {
    if (!this.hasResult(type)) return '';
    if (type === ModuleType.Deadline) {
      const base = dateSummary(this.currentDeadlineConfig());
      const rem = this.draft.reminderMinutes >= 0
        ? ` · ${timelineReminderLabel(this.draft.reminderMinutes)}`
        : '';
      return base + rem;
    }
    if (type === ModuleType.Tag) {
      const selected = this.tags.find((t: TimelineTag) => t.id === this.draft.tagId);
      return selected ? `颜色分类：${selected.name}` : '';
    }
    if (type === ModuleType.Counter) {
      if (this.draft.counterMode === 'daily_once') return '每日完成一次，统计连续与累计天数';
      if (this.draft.counterMode === 'tally') {
        const u = this.draft.unit.trim() || '次';
        return `初始 ${this.draft.initial || '0'} ${u} · 每次点击 +1 ${u}`;
      }
      const u = this.draft.unit.trim() ? ` ${this.draft.unit.trim()}` : '';
      const s2 = this.draft.step2.trim() ? ` / +${this.draft.step2.trim()}` : '';
      return `初始 ${this.draft.initial || '0'}${u} · 快捷 +${this.draft.step || '1'}${s2}`;
    }
    if (type === ModuleType.Checklist) {
      return `共 ${this.draft.items.length} 项 · ` + this.draft.items.slice(0, 3).map((item: EditorItem) =>
        (item.targetId ? '事项：' : '文字：') + item.title).join('、');
    }
    const parts: string[] = [];
    if (this.draft.note.trim()) parts.push(this.draft.note.trim().split('\n')[0]);
    if (this.draft.attachments.length > 0) parts.push(`附件 ${this.draft.attachments.length} 个`);
    return parts.join(' · ');
  }

  private availableOptions(): ModuleOption[] {
    const order: ModuleType[] = [
      ModuleType.Deadline,
      ModuleType.Tag,
      ModuleType.Counter,
      ModuleType.Checklist,
      ModuleType.Note
    ];
    const result: ModuleOption[] = [];
    for (const type of order) {
      if (this.draft.types.includes(type)) continue;
      const option = MODULE_OPTIONS.find((item: ModuleOption) => item.type === type);
      if (option) result.push(option);
    }
    return result;
  }

  private cardBorder(type: ModuleType): BorderOptions {
    if (this.invalid === type) {
      return {
        width: { left: 1, top: 1, right: 1, bottom: 2 },
        color: { left: Colors.hairline, top: Colors.hairline, right: Colors.hairline, bottom: Colors.red },
        radius: Radius.card
      };
    }
    return {
      width: 1,
      color: Colors.hairline,
      radius: Radius.card
    };
  }

  private selectCounterMode(mode: ActiveCounterMode): void {
    this.draft.counterMode = mode;
    if (mode === 'tally') {
      this.draft.step = '1';
      this.draft.step2 = '';
      if (!this.draft.unit.trim()) this.draft.unit = '次';
    } else if (mode === 'daily_once') {
      this.draft.initial = '0';
      this.draft.step = '1';
      this.draft.step2 = '';
    } else if (mode === 'amount') {
      if (this.draft.unit === '次') this.draft.unit = '';
      if (this.draft.step === '1' && !this.draft.step2) {
        this.draft.step = '10';
        this.draft.step2 = '50';
      }
    }
    this.changed();
  }

  private async handleSaveNewTag(tag: TimelineTag): Promise<void> {
    const saved = await this.service.saveTag(tag);
    this.tags = this.service.listTags();
    this.draft.tagId = saved.id;
    this.changed();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.newTagOpen) {
        TimelineTagForm({
          tags: this.tags,
          onSaveTag: (tag: TimelineTag) => this.handleSaveNewTag(tag),
          onCancel: () => { this.newTagOpen = false; },
          onDone: (id: string) => {
            this.draft.tagId = id;
            this.newTagOpen = false;
            this.changed();
          }
        });
      } else {
        Column() {
          if (this.unavailable) {
            this.Header();
            Text(this.feedback)
              .fontSize(TypeSize.bodySmall)
              .fontWeight(TypeWeight.regular)
              .fontColor(Colors.inkSoft)
              .margin({ top: Space.lg });
          } else {
            List({ scroller: this.scroller, space: Space.md }) {
              ListItem() {
                this.Header();
              }.margin({ bottom: Space.xs })

              if (this.resumed) {
                ListItem() {
                  this.DraftBanner();
                }
              }

              ListItem() {
                this.TitleCard();
              }

              ListItem() {
                this.SectionHeading();
              }

              ForEach(this.draft.types, (type: ModuleType) => {
                ListItem() {
                  this.ModuleCard(type);
                }
              }, (type: ModuleType) => type)

              if (this.availableOptions().length > 0) {
                ListItem() {
                  this.AvailableTray();
                }.margin({ top: Space.xs })
              }

              ListItem() {
                this.SubmitArea();
              }.margin({ top: Space.sm })
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .enabled(!this.busy && !this.importingAttachment && !this.draft.token)
          }
        }
        .width('100%')
        .height('100%')
        .padding({
          left: Space.page,
          right: Space.page,
          top: Space.lg,
          bottom: Space.lg
        })
        .backgroundColor(Colors.bg)
      }

      if (this.confirmExit) {
        this.ExitConfirmOverlay();
      }
      if (this.confirmScope) {
        this.ScopeConfirmOverlay();
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ScopeConfirmOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#59191714')
        .onClick(() => { this.confirmScope = false; });

      Column({ space: Space.md }) {
        Column({ space: Space.xs }) {
          Text('修改重复事项')
            .fontSize(TypeSize.title)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink)
            .width('100%');
          Text(`${this.draft.title.trim()} · ${formatDate(this.draft.timestamp)} ${formatClock(this.draft.timestamp)}`)
            .fontSize(TypeSize.bodySmall)
            .fontColor(Colors.inkSoft)
            .fontFeature(TABULAR_NUMS)
            .width('100%');
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start);

        Column({ space: Space.xs }) {
          if (!this.changedRepeatFrequency() && !this.stopsRepeat()) {
            this.ScopeOptionRow(TimelineEditScope.One, '仅修改这一次');
          }
          this.ScopeOptionRow(
            TimelineEditScope.Following,
            this.stopsRepeat() ? '保留这一次，停止以后的重复' : '修改这次及以后'
          );
          this.ScopeOptionRow(
            TimelineEditScope.All,
            this.stopsRepeat() ? '整个系列改为仅保留这一次' : '修改整个系列'
          );
        }
        .width('100%');

        Row({ space: Space.sm }) {
          Button('取消')
            .type(ButtonType.Normal)
            .layoutWeight(1)
            .constraintSize({ minHeight: 42 })
            .fontSize(TypeSize.body)
            .fontColor(Colors.inkSoft)
            .backgroundColor(Colors.wash)
            .borderRadius(Radius.card)
            .onClick(() => { this.confirmScope = false; });
          Button('确认保存')
            .type(ButtonType.Normal)
            .layoutWeight(1)
            .constraintSize({ minHeight: 42 })
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.onRed)
            .backgroundColor(Colors.red)
            .borderRadius(Radius.card)
            .onClick(() => {
              const chosen = this.pendingScope;
              this.confirmScope = false;
              this.executeSave(chosen);
            });
        }
        .width('100%');
      }
      .width('86%')
      .constraintSize({ maxWidth: 336 })
      .padding(Space.page)
      .backgroundColor(Colors.card)
      .borderRadius(Radius.card)
      .border({ width: 1, color: Colors.hairline });
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private ScopeOptionRow(scope: TimelineEditScope, label: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: Space.sm }) {
        Text(label)
          .fontSize(TypeSize.body)
          .fontWeight(this.pendingScope === scope ? TypeWeight.semibold : TypeWeight.regular)
          .fontColor(this.pendingScope === scope ? Colors.ink : Colors.inkSoft)
          .layoutWeight(1);
        if (this.pendingScope === scope) {
          Text('✓')
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink);
        }
      }
      .width('100%');
    }
    .width('100%')
    .constraintSize({ minHeight: 42 })
    .padding({ left: Space.md, right: Space.md })
    .backgroundColor(this.pendingScope === scope ? Colors.wash : Color.Transparent)
    .borderRadius(Radius.card)
    .onClick(() => { this.pendingScope = scope; });
  }

  @Builder
  private ExitConfirmOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#59191714')
        .onClick(() => {
          this.confirmExit = false;
        });

      Column({ space: Space.md }) {
        Column({ space: Space.xs }) {
          Text('退出编辑？')
            .fontSize(TypeSize.title)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink)
            .width('100%');
          Text('当前修改尚未保存，可保留草稿以便下次继续。')
            .fontSize(TypeSize.bodySmall)
            .fontWeight(TypeWeight.regular)
            .fontColor(Colors.inkSoft)
            .width('100%');
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start);

        Column({ space: Space.xs }) {
          Button('保留草稿')
            .type(ButtonType.Normal)
            .width('100%')
            .constraintSize({ minHeight: 44 })
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.bg)
            .backgroundColor(Colors.ink)
            .borderRadius(Radius.card)
            .onClick(() => {
              this.confirmExit = false;
              this.leave(false);
            });
          Button('放弃')
            .type(ButtonType.Normal)
            .width('100%')
            .constraintSize({ minHeight: 44 })
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.red)
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .onClick(() => {
              this.confirmExit = false;
              this.leave(true);
            });
          Divider().color(Colors.hairline);
          Button('继续编辑')
            .type(ButtonType.Normal)
            .width('100%')
            .constraintSize({ minHeight: 44 })
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.regular)
            .fontColor(Colors.inkSoft)
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .onClick(() => {
              this.confirmExit = false;
            });
        }
        .width('100%');
      }
      .width('84%')
      .constraintSize({ maxWidth: 320 })
      .padding(Space.page)
      .backgroundColor(Colors.card)
      .borderRadius(Radius.card)
      .border({ width: 1, color: Colors.hairline });
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private Header() {
    Column({ space: Space.sm }) {
      Row() {
        Button('返回')
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 40 })
          .fontSize(TypeSize.body)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink)
          .backgroundColor(Color.Transparent)
          .borderRadius(Radius.card)
          .padding({ left: 0, right: Space.md })
          .enabled(!this.busy && !this.importingAttachment)
          .opacity(this.busy || this.importingAttachment ? 0.4 : 1)
          .onClick(() => { if (!this.onBackPress()) router.back(); });
      }
      .width('100%');

      Text(this.draft.editing ? '编辑事项' : this.ownerId ? '创建并加入列表' : '新建事项')
        .fontSize(TypeSize.display)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.ink)
        .maxLines(2)
        .width('100%');
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private DraftBanner() {
    Row({ space: Space.sm }) {
      Text('已恢复未完成的草稿')
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkSoft)
        .layoutWeight(1);
      Button('重新开始')
        .type(ButtonType.Normal)
        .constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.ink)
        .backgroundColor(Color.Transparent)
        .borderRadius(Radius.card)
        .padding({ left: Space.sm, right: Space.sm })
        .onClick(() => this.restartDraft());
    }
    .width('100%')
    .padding({
      left: Space.md,
      right: Space.sm,
      top: Space.xs,
      bottom: Space.xs
    })
    .backgroundColor(Colors.card)
    .borderRadius(Radius.card)
    .border({ width: 1, color: Colors.hairline });
  }

  @Builder
  private TitleCard() {
    Column({ space: Space.sm }) {
      Text('事项名称')
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.inkSoft);
      Column() {
        TextInput({ placeholder: '写下这件事的名称', text: this.draft.title })
          .width('100%')
          .constraintSize({ minHeight: 50 })
          .fontSize(TypeSize.heading)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink)
          .placeholderColor(Colors.inkMuted)
          .caretColor(Colors.red)
          .backgroundColor(Color.Transparent)
          .padding({ left: Space.md, right: Space.md })
          .maxLength(80)
          .onFocus(() => { this.titleFocused = true; })
          .onBlur(() => { this.titleFocused = false; })
          .onChange((value: string) => { this.draft.title = value; this.changed(); });
        Column()
          .width('100%')
          .height(2)
          .backgroundColor(this.invalid === 'title'
            ? Colors.red
            : this.titleFocused ? Colors.ink : Color.Transparent);
      }
      .width('100%')
      .backgroundColor(Colors.wash)
      .borderRadius(Radius.card)
      .clip(true);
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Space.lg)
    .backgroundColor(Colors.card)
    .borderRadius(Radius.card)
    .border({ width: 1, color: Colors.hairline });
  }

  @Builder
  private SectionHeading() {
    Row() {
      Text('事项信息')
        .fontSize(TypeSize.title)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.ink);
      Blank();
      Text(this.draft.types.length > 0 ? `已启用 ${this.draft.types.length} 项` : '可选')
        .fontSize(TypeSize.meta)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkMuted)
        .fontFeature(TABULAR_NUMS);
    }
    .width('100%')
    .margin({ top: Space.xs });
  }

  @Builder
  private ModuleCard(type: ModuleType) {
    Column() {
      Row({ space: Space.md }) {
        Column() {
          if (type === ModuleType.Tag && this.tags.some((t: TimelineTag) => t.id === this.draft.tagId)) {
            Row()
              .width(14)
              .height(14)
              .borderRadius(7)
              .backgroundColor(this.tags.find((t: TimelineTag) => t.id === this.draft.tagId)?.color ?? Colors.ink);
          } else {
            ModuleIcon({ moduleType: type, ink: Colors.ink, iconSize: 20 });
          }
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.chip);

        Column({ space: Space.xs }) {
          Text(this.moduleTitle(type))
            .fontSize(TypeSize.title)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink);
          if (this.hasResult(type)) {
            Text(this.summary(type))
              .fontSize(TypeSize.bodySmall)
              .fontWeight(TypeWeight.regular)
              .fontColor(Colors.inkSoft)
              .fontFeature(TABULAR_NUMS)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          } else {
            Text('已启用 · 点击配置')
              .fontSize(TypeSize.meta)
              .fontWeight(TypeWeight.regular)
              .fontColor(Colors.inkMuted);
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);

        Text(this.expanded === type ? '⌃' : '⌄')
          .fontSize(18)
          .fontColor(Colors.inkMuted);
        Button({ type: ButtonType.Normal }) {
          Row() {
            Column()
              .width(16)
              .height(16)
              .borderRadius(2)
              .backgroundColor(Colors.card);
          }
          .width(40)
          .height(22)
          .padding({ left: 3, right: 3 })
          .justifyContent(FlexAlign.End)
          .alignItems(VerticalAlign.Center)
          .backgroundColor(Colors.ink)
          .borderRadius(Radius.chip);
        }
        .width(48)
        .height(44)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(Radius.card)
        .accessibilityText('关闭' + this.moduleTitle(type))
        .onClick(() => {
          this.disable(type);
        });
      }
      .width('100%')
      .constraintSize({ minHeight: 72 })
      .padding({ top: Space.sm, bottom: Space.sm })
      .onClick(() => this.toggleExpand(type));

      if (this.expanded === type) {
        Column({ space: Space.md }) {
          this.config(type);
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: Space.md, bottom: Space.md })
        .border({ width: { top: 1 }, color: Colors.hairline });

        Row() {
          Text('修改自动保留')
            .fontSize(TypeSize.meta)
            .fontWeight(TypeWeight.regular)
            .fontColor(Colors.inkMuted);
          Blank();
          Button('收起 ⌃')
            .type(ButtonType.Normal)
            .constraintSize({ minHeight: 36 })
            .fontSize(TypeSize.bodySmall)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink)
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .padding({ left: Space.sm, right: 0 })
            .onClick(() => { this.expanded = ''; });
        }
        .width('100%')
        .padding({ top: Space.xs, bottom: Space.xs })
        .border({ width: { top: 1 }, color: Colors.hairline });
      }
    }
    .width('100%')
    .padding({ left: Space.lg, right: Space.lg })
    .backgroundColor(Colors.card)
    .border(this.cardBorder(type));
  }

  @Builder
  private AvailableTray() {
    Column({ space: Space.sm }) {
      Row() {
        Text(this.draft.types.length > 0 ? '还可以启用' : '选择需要的信息')
          .fontSize(TypeSize.meta)
          .fontWeight(TypeWeight.regular)
          .fontColor(Colors.inkMuted);
        Blank();
        Text('可多选')
          .fontSize(TypeSize.meta)
          .fontWeight(TypeWeight.regular)
          .fontColor(Colors.inkMuted);
      }
      .width('100%')
      .padding({ left: Space.xs, right: Space.xs, bottom: Space.xs });

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(this.availableOptions(), (option: ModuleOption) => {
          Row({ space: Space.sm }) {
            ModuleIcon({ moduleType: option.type, ink: Colors.inkSoft, iconSize: 18 });
            Column({ space: 2 }) {
              Text(option.label)
                .fontSize(TypeSize.body)
                .fontWeight(TypeWeight.semibold)
                .fontColor(Colors.ink);
              Text(option.description)
                .fontSize(TypeSize.meta)
                .fontWeight(TypeWeight.regular)
                .fontColor(Colors.inkSoft)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);

            Text('+')
              .fontSize(16)
              .fontWeight(TypeWeight.semibold)
              .fontColor(Colors.inkMuted);
          }
          .width(this.compactWidth ? '100%' : '48%')
          .constraintSize({ minHeight: 60 })
          .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
          .margin({ bottom: Space.sm })
          .backgroundColor(Colors.card)
          .borderRadius(Radius.card)
          .border({ width: 1, color: Colors.hairline })
          .onClick(() => this.activate(option.type));
        }, (option: ModuleOption) => option.type);
      }
      .width('100%')
      .onAreaChange((_oldArea: Area, area: Area) => {
        const scale = (getContext(this) as common.UIAbilityContext).config.fontSizeScale ?? 1;
        this.compactWidth = Number(area.width) < 300 || scale >= 1.5;
      });
    }
    .width('100%')
    .padding({ top: Space.xs });
  }

  @Builder
  private SubmitArea() {
    Column({ space: Space.sm }) {
      Button(this.busy ? '正在保存' : this.draft.token ? '重试保存' :
        this.draft.editing ? '保存修改' : '创建事项')
        .type(ButtonType.Normal)
        .width('100%')
        .constraintSize({ minHeight: 44 })
        .fontSize(TypeSize.body)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.onRed)
        .backgroundColor(Colors.red)
        .borderRadius(Radius.card)
        .enabled(!this.busy && !this.importingAttachment)
        .opacity(this.busy || this.importingAttachment ? 0.4 : 1)
        .onClick(() => {
          if (this.draft.token) this.executeSave();
          else this.requestSave();
        });
      if (this.feedback) {
        Text(this.feedback)
          .fontSize(TypeSize.meta)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.red)
          .width('100%');
      }
    }
    .width('100%');
  }

  @Builder
  private config(type: ModuleType) {
    if (type === ModuleType.Deadline) {
      MatterDateEditor({
        startAt: $startAt,
        endAt: $endAt,
        span: $span,
        dayCountMode: $dayCountMode,
        reminderMinutes: $reminderMinutes,
        repeat: $repeat,
        initialFocusClock: this.focusClock
      });
    } else if (type === ModuleType.Tag) {
      this.TagModuleEditor();
    } else if (type === ModuleType.Counter) {
      this.CounterModuleEditor();
    } else if (type === ModuleType.Note) {
      this.NoteModuleEditor();
    } else if (type === ModuleType.Checklist) {
      this.listEditor();
    }
  }

  @Builder
  private TagModuleEditor() {
    Column({ space: Space.sm }) {
      Text('选择颜色分类（仅使用颜色与文字标记）')
        .fontSize(TypeSize.meta)
        .fontColor(Colors.inkMuted)
        .width('100%');

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.tags, (tag: TimelineTag) => {
          Button({ type: ButtonType.Normal }) {
            Row({ space: Space.xs }) {
              Row()
                .width(10)
                .height(10)
                .borderRadius(5)
                .backgroundColor(tag.color);
              Text(tag.name)
                .fontSize(TypeSize.bodySmall)
                .fontWeight(this.draft.tagId === tag.id ? TypeWeight.semibold : TypeWeight.regular)
                .fontColor(this.draft.tagId === tag.id ? Colors.ink : Colors.inkSoft);
              if (this.draft.tagId === tag.id) {
                Text('✓')
                  .fontSize(TypeSize.meta)
                  .fontWeight(TypeWeight.semibold)
                  .fontColor(Colors.ink);
              }
            }
            .alignItems(VerticalAlign.Center);
          }
          .constraintSize({ minHeight: 36 })
          .padding({ left: Space.md, right: Space.md })
          .margin({ right: Space.xs, bottom: Space.xs })
          .backgroundColor(this.draft.tagId === tag.id ? Colors.wash : Colors.bg)
          .borderRadius(Radius.chip)
          .border({
            width: 1,
            color: this.draft.tagId === tag.id ? tag.color : Colors.hairline
          })
          .onClick(() => {
            this.draft.tagId = tag.id;
            this.changed();
          });
        }, (tag: TimelineTag) => `${tag.id}_${this.draft.tagId === tag.id}`);

        Button('+ 新建标签')
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 36 })
          .fontSize(TypeSize.bodySmall)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink)
          .backgroundColor(Colors.wash)
          .borderRadius(Radius.chip)
          .padding({ left: Space.md, right: Space.md })
          .margin({ bottom: Space.xs })
          .onClick(() => { this.newTagOpen = true; });
      }
      .width('100%');
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private CounterModeTab(value: ActiveCounterMode, label: string) {
    Button(label, { type: ButtonType.Normal })
      .layoutWeight(1)
      .height(34)
      .padding(0)
      .fontSize(TypeSize.bodySmall)
      .fontWeight(this.draft.counterMode === value ? TypeWeight.semibold : TypeWeight.regular)
      .fontColor(this.draft.counterMode === value ? Colors.ink : Colors.inkSoft)
      .backgroundColor(this.draft.counterMode === value ? Colors.card : Color.Transparent)
      .borderRadius(Radius.chip)
      .border({ width: this.draft.counterMode === value ? 1 : 0, color: Colors.hairline })
      .onClick(() => this.selectCounterMode(value));
  }

  @Builder
  private CounterModuleEditor() {
    Column({ space: Space.sm }) {
      Row({ space: 4 }) {
        this.CounterModeTab('tally', '计次');
        this.CounterModeTab('amount', '计量');
        this.CounterModeTab('daily_once', '每日打卡');
      }
      .width('100%')
      .padding(3)
      .backgroundColor(Colors.wash)
      .borderRadius(Radius.card);

      if (this.draft.counterMode === 'daily_once') {
        Text('每天点按一次完成打卡，自动统计连续天数与累计天数，点错可随时取消。')
          .fontSize(TypeSize.bodySmall)
          .fontColor(Colors.inkSoft)
          .width('100%')
          .padding({ top: Space.xs, bottom: Space.xs });
      } else if (this.draft.counterMode === 'tally') {
        Text('每次点按自动 +1，留下发生时刻并支持补写当次短备注与撤回。')
          .fontSize(TypeSize.meta)
          .fontColor(Colors.inkMuted)
          .width('100%');

        Row({ space: Space.sm }) {
          Column({ space: 4 }) {
            Text('单位')
              .fontSize(TypeSize.meta)
              .fontColor(Colors.inkSoft);
            TextInput({ placeholder: '次', text: this.draft.unit })
              .width('100%')
              .constraintSize({ minHeight: 40 })
              .fontSize(TypeSize.body)
              .fontColor(Colors.ink)
              .placeholderColor(Colors.inkMuted)
              .caretColor(Colors.red)
              .backgroundColor(Colors.wash)
              .borderRadius(Radius.card)
              .padding({ left: Space.md, right: Space.md })
              .maxLength(8)
              .onChange((val: string) => { this.draft.unit = val; this.changed(); });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);

          Column({ space: 4 }) {
            Text('初始次数')
              .fontSize(TypeSize.meta)
              .fontColor(Colors.inkSoft);
            TextInput({ text: this.draft.initial })
              .width('100%')
              .constraintSize({ minHeight: 40 })
              .fontSize(TypeSize.body)
              .fontColor(Colors.ink)
              .caretColor(Colors.red)
              .type(InputType.NUMBER_DECIMAL)
              .backgroundColor(Colors.wash)
              .borderRadius(Radius.card)
              .padding({ left: Space.md, right: Space.md })
              .onChange((val: string) => { this.draft.initial = val; this.changed(); });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);
        }
        .width('100%');
      } else {
        Text('按快捷步长或输入任意数值累加，适合页数、单词量、里程等。')
          .fontSize(TypeSize.meta)
          .fontColor(Colors.inkMuted)
          .width('100%');

        Row({ space: Space.sm }) {
          Column({ space: 4 }) {
            Text('单位（可选）')
              .fontSize(TypeSize.meta)
              .fontColor(Colors.inkSoft);
            TextInput({ placeholder: '如 页、个、km', text: this.draft.unit })
              .width('100%')
              .constraintSize({ minHeight: 40 })
              .fontSize(TypeSize.body)
              .fontColor(Colors.ink)
              .placeholderColor(Colors.inkMuted)
              .caretColor(Colors.red)
              .backgroundColor(Colors.wash)
              .borderRadius(Radius.card)
              .padding({ left: Space.md, right: Space.md })
              .maxLength(8)
              .onChange((val: string) => { this.draft.unit = val; this.changed(); });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);

          Column({ space: 4 }) {
            Text('初始数值')
              .fontSize(TypeSize.meta)
              .fontColor(Colors.inkSoft);
            TextInput({ text: this.draft.initial })
              .width('100%')
              .constraintSize({ minHeight: 40 })
              .fontSize(TypeSize.body)
              .fontColor(Colors.ink)
              .caretColor(Colors.red)
              .type(InputType.NUMBER_DECIMAL)
              .backgroundColor(Colors.wash)
              .borderRadius(Radius.card)
              .padding({ left: Space.md, right: Space.md })
              .onChange((val: string) => { this.draft.initial = val; this.changed(); });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);
        }
        .width('100%');

        Row({ space: Space.sm }) {
          Column({ space: 4 }) {
            Text('快捷步长 1')
              .fontSize(TypeSize.meta)
              .fontColor(Colors.inkSoft);
            TextInput({ placeholder: '10', text: this.draft.step })
              .width('100%')
              .constraintSize({ minHeight: 40 })
              .fontSize(TypeSize.body)
              .fontColor(Colors.ink)
              .placeholderColor(Colors.inkMuted)
              .caretColor(Colors.red)
              .type(InputType.NUMBER_DECIMAL)
              .backgroundColor(Colors.wash)
              .borderRadius(Radius.card)
              .padding({ left: Space.md, right: Space.md })
              .onChange((val: string) => { this.draft.step = val; this.changed(); });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);

          Column({ space: 4 }) {
            Text('快捷步长 2（可选）')
              .fontSize(TypeSize.meta)
              .fontColor(Colors.inkSoft);
            TextInput({ placeholder: '50', text: this.draft.step2 })
              .width('100%')
              .constraintSize({ minHeight: 40 })
              .fontSize(TypeSize.body)
              .fontColor(Colors.ink)
              .placeholderColor(Colors.inkMuted)
              .caretColor(Colors.red)
              .type(InputType.NUMBER_DECIMAL)
              .backgroundColor(Colors.wash)
              .borderRadius(Radius.card)
              .padding({ left: Space.md, right: Space.md })
              .onChange((val: string) => { this.draft.step2 = val; this.changed(); });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);
        }
        .width('100%');
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private NoteModuleEditor() {
    Column({ space: Space.sm }) {
      Row() {
        Text('备注与图文附件')
          .fontSize(TypeSize.bodySmall)
          .fontColor(Colors.inkSoft)
          .layoutWeight(1);
        if (this.previewLinks && this.noteHasUrl(this.draft.note)) {
          Button('编辑文字')
            .type(ButtonType.Normal)
            .constraintSize({ minHeight: 36 })
            .fontSize(TypeSize.bodySmall)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink)
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .padding({ left: Space.xs, right: Space.xs })
            .onClick(() => { this.previewLinks = false; });
        }
        if (!MatterServices.isPreview()) {
          TimelineAttachmentButton({
            session: this.attachmentSession,
            onAdd: (item: TimelineAttachment) => {
              this.draft.attachments = this.draft.attachments.concat(item);
              this.changed();
            },
            onBusy: (busy: boolean) => { this.importingAttachment = busy; }
          });
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      if (this.previewLinks && this.noteHasUrl(this.draft.note)) {
        Column() {
          TimelineLinkedNote({
            value: this.draft.note,
            onEdit: () => { this.previewLinks = false; }
          });
        }
        .width('100%')
        .padding(Space.sm)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.card)
        .alignItems(HorizontalAlign.Start);
      } else {
        TextArea({ placeholder: '补充文字说明、粘贴链接，或点右上角添加照片与文件', text: this.draft.note })
          .width('100%')
          .constraintSize({ minHeight: 108 })
          .fontSize(TypeSize.body)
          .fontColor(Colors.ink)
          .placeholderColor(Colors.inkMuted)
          .caretColor(Colors.red)
          .backgroundColor(Colors.wash)
          .borderRadius(Radius.card)
          .padding(Space.md)
          .onBlur(() => {
            if (this.noteHasUrl(this.draft.note)) {
              this.previewLinks = true;
            }
          })
          .onChange((value: string) => {
            this.draft.note = value;
            this.changed();
          });
      }

      if (this.draft.attachments.length > 0) {
        TimelineAttachmentList({
          items: this.draft.attachments,
          editable: true,
          onRemove: (id: string) => {
            this.draft.attachments = this.draft.attachments.filter((item: TimelineAttachment) => item.id !== id);
            this.changed();
          }
        });
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private listEditor() {
    Row({ space: Space.sm }) {
      TextInput({ placeholder: '输入列表项', text: this.draft.pending })
        .constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.body)
        .fontColor(Colors.ink)
        .placeholderColor(Colors.inkMuted)
        .caretColor(Colors.red)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.card)
        .padding({ left: Space.md, right: Space.md })
        .layoutWeight(1)
        .onChange((value: string) => { this.draft.pending = value; this.changed(); });
      Button('添加')
        .type(ButtonType.Normal)
        .constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.body)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.ink)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.card)
        .padding({ left: Space.lg, right: Space.lg })
        .onClick(() => {
          if (this.draft.pending.trim()) {
            this.draft.items = this.draft.items.concat({ id: createId('check'), title: this.draft.pending.trim() });
            this.draft.pending = '';
            this.changed();
          }
        });
    }
    .width('100%');

    Button('↗ 关联已有事项')
      .type(ButtonType.Normal)
      .constraintSize({ minHeight: 44 })
      .fontSize(TypeSize.body)
      .fontWeight(TypeWeight.semibold)
      .fontColor(Colors.ink)
      .backgroundColor(Color.Transparent)
      .borderRadius(Radius.card)
      .padding({ left: 0, right: Space.md })
      .onClick(() => {
        this.picking = !this.picking;
        this.candidates = this.service.linkCandidates(this.draft, this.ownerId);
      });

    if (this.picking) {
      Column({ space: Space.sm }) {
        if (!this.candidates.length) {
          Text('暂无可关联事项')
            .fontSize(TypeSize.bodySmall)
            .fontColor(Colors.inkSoft);
        }
        ForEach(this.candidates, (matter: Matter) => {
          Button(matter.title)
            .type(ButtonType.Normal)
            .width('100%')
            .constraintSize({ minHeight: 40 })
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.regular)
            .fontColor(Colors.ink)
            .backgroundColor(Colors.card)
            .borderRadius(Radius.card)
            .onClick(() => {
              this.draft.items = this.draft.items.concat({ id: createId('link'), title: matter.title, targetId: matter.id });
              this.picking = false;
              this.changed();
            });
        }, (matter: Matter) => matter.id);
      }
      .width('100%')
      .padding(Space.sm)
      .backgroundColor(Colors.wash)
      .borderRadius(Radius.card);
    }

    ForEach(this.draft.items, (item: EditorItem) => {
      Row({ space: Space.sm }) {
        Column({ space: Space.xs }) {
          if (!item.targetId && this.editingItemId === item.id) {
            TextInput({ text: item.title })
              .width('100%')
              .constraintSize({ minHeight: 40 })
              .fontSize(TypeSize.body)
              .fontColor(Colors.ink)
              .caretColor(Colors.red)
              .backgroundColor(Colors.wash)
              .borderRadius(Radius.card)
              .padding({ left: Space.sm, right: Space.sm })
              .onChange((value: string) => {
                item.title = value;
                this.changed();
              });
          } else {
            Text(item.targetId ? (this.service.findMatter(item.targetId)?.title ?? item.title) : item.title)
              .fontSize(TypeSize.body)
              .fontWeight(TypeWeight.regular)
              .fontColor(Colors.ink)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(item.targetId ? '关联事项' : '文字项')
              .fontSize(TypeSize.meta)
              .fontWeight(TypeWeight.regular)
              .fontColor(Colors.inkMuted);
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);

        if (!item.targetId) {
          Button(this.editingItemId === item.id ? '完成' : '修改')
            .type(ButtonType.Normal)
            .constraintSize({ minHeight: 40 })
            .fontSize(TypeSize.bodySmall)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink)
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .padding({ left: Space.sm, right: Space.sm })
            .onClick(() => {
              this.editingItemId = this.editingItemId === item.id ? '' : item.id;
            });
        }
        Button('移除')
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 40 })
          .fontSize(TypeSize.bodySmall)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.red)
          .backgroundColor(Color.Transparent)
          .borderRadius(Radius.card)
          .padding({ left: Space.sm, right: Space.sm })
          .onClick(() => {
            this.draft.items = this.draft.items.filter((entry: EditorItem) => entry.id !== item.id);
            if (this.editingItemId === item.id) this.editingItemId = '';
            this.changed();
          });
      }
      .width('100%')
      .padding({ top: Space.sm, bottom: Space.sm })
      .border({ width: { bottom: 1 }, color: Colors.hairline });
    }, (item: EditorItem) => item.id);
  }
}
