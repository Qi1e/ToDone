import { common } from '@kit.AbilityKit';
import { EditorDraftStorage } from '../store/EditorDraftStorage';
import { MatterService } from '../contracts/MatterService';
import { router } from '@kit.ArkUI';
import { MatterServices } from '../application/MatterServices';
import { MatterDateEditor } from '../components/MatterDateEditor';
import { ModuleIcon } from '../components/ModuleIcon';
import { dateModeLabel, dateSummary, daysUntil, formatDate } from '../common/DateFormat';
import { Colors, Radius, Space, TABULAR_NUMS, TypeSize, TypeWeight } from '../common/Theme';
import { EditorDraft, EditorItem, invalidEditorField } from '../domain/MatterEditor';
import { createId, MODULE_OPTIONS, moduleLabel } from '../model/Defaults';
import { DateMode, Matter, ModuleOption, ModuleType } from '../model/Types';
import { matterErrorMessage } from '../domain/MatterSnapshot';

interface EditorRoute {
  matterId?: string;
  ownerMatterId?: string;
}

@Entry
@Component
struct CreateMatter {
  private service: MatterService = MatterServices.getService();
  private scroller: Scroller = new Scroller();
  private storage?: EditorDraftStorage;
  private draftKey: string = '';
  private ownerId: string = '';
  private ready: boolean = false;
  private timer: number = -1;
  private original: string = '';
  @State compactWidth: boolean = false;
  @State resumed: boolean = false;
  @State draft: EditorDraft = new EditorDraft();
  @State @Watch('dateChanged') date: Date = new Date();
  @State @Watch('dateChanged') mode: DateMode = 'deadline';
  @State @Watch('dateChanged') hasTime: boolean = false;
  @State expanded: string = '';
  @State invalid: string = '';
  @State feedback: string = '';
  @State busy: boolean = false;
  @State unavailable: boolean = false;
  @State picking: boolean = false;
  @State candidates: Matter[] = [];
  @State editingItemId: string = '';
  @State titleFocused: boolean = false;

  aboutToAppear(): void {
    this.initialize();
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
    const route = router.getParams() as EditorRoute | undefined;
    const id = route?.matterId ?? '';
    this.ownerId = route?.ownerMatterId ?? '';
    this.draftKey = id ? 'edit_' + id : this.ownerId ? 'owner_' + this.ownerId : 'new';
    const initial = this.service.loadEditor(id);
    if (!initial) {
      this.unavailable = true;
      this.feedback = '原事项已删除';
      return;
    }
    this.original = JSON.stringify(initial);
    this.draft = initial;
    try {
      if (!MatterServices.isPreview()) {
        this.storage = new EditorDraftStorage(context, this.draftKey);
        const saved = this.storage.read();
        if (saved) {
          this.draft = JSON.parse(saved) as EditorDraft;
          this.resumed = true;
        }
      }
    } catch (error) { this.feedback = '无法读取草稿'; }
    this.date = new Date(this.draft.timestamp);
    this.mode = this.draft.mode;
    this.hasTime = this.draft.hasTime;
    this.ready = true;
  }

  private dateChanged(): void {
    if (!this.ready) return;
    this.draft.timestamp = this.date.getTime();
    this.draft.mode = this.mode;
    this.draft.hasTime = this.hasTime;
    this.changed();
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
    if (this.busy) return true;
    if (this.unavailable || this.original === JSON.stringify(this.draft)) return false;
    AlertDialog.show({
      message: '退出编辑？',
      buttons: [
        { value: '关闭', action: () => {} },
        { value: '保留草稿', action: () => { this.leave(false); } },
        { value: '放弃', action: () => { this.leave(true); } }
      ]
    });
    return true;
  }

  private restartDraft(): void {
    this.draft = JSON.parse(this.original) as EditorDraft;
    this.date = new Date(this.draft.timestamp);
    this.mode = this.draft.mode;
    this.hasTime = this.draft.hasTime;
    this.expanded = '';
    this.invalid = '';
    this.feedback = '';
    this.editingItemId = '';
    this.resumed = false;
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

  private async save(): Promise<void> {
    if (this.busy) return;
    this.invalid = invalidEditorField(this.draft);
    if (this.invalid) {
      if (this.invalid === 'title') {
        this.feedback = '请填写事项名称';
        this.scrollToTitle();
      } else {
        if (this.invalid === ModuleType.Deadline) this.feedback = '正数日的起始日期不能晚于今天';
        if (this.invalid === ModuleType.Note) this.feedback = '请填写备注内容';
        if (this.invalid === ModuleType.Counter) this.feedback = '初始数值须非负，每次增加须大于零';
        if (this.invalid === ModuleType.Checklist) this.feedback = '请填写或移除空列表项';
        this.expanded = this.invalid;
        this.scrollToModule(this.invalid as ModuleType);
      }
      return;
    }
    this.busy = true;
    try {
      if (!this.draft.token) this.draft.token = createId('save');
      if (!await this.writeDraft()) {
        this.draft.token = '';
        return;
      }
      const result = await this.service.saveEditor(this.draft, this.ownerId);
      if (!result.success) {
        if (!result.matterId) {
          this.draft.token = '';
          await this.writeDraft();
        }
        this.feedback = result.message;
        return;
      }
      MatterServices.requestCardRefresh();
      await this.leave(true);
    } catch (error) { this.feedback = '保存未完成，请重试'; }
    finally { this.busy = false; }
  }

  private moduleTitle(type: ModuleType): string {
    let name = '';
    if (type === ModuleType.Deadline) name = this.draft.dateName;
    if (type === ModuleType.Counter) name = this.draft.counterName;
    if (type === ModuleType.EventRecord) name = this.draft.recordName;
    const label = type === ModuleType.Deadline ? dateModeLabel(this.mode) : moduleLabel(type);
    return name ? label + ' · ' + name : label;
  }

  private hasResult(type: ModuleType): boolean {
    if (type === ModuleType.Deadline) {
      return !(this.mode === 'elapsed' && daysUntil(this.draft.timestamp) > 0);
    }
    if (type === ModuleType.Counter) {
      const initial = Number(this.draft.initial);
      const step = Number(this.draft.step);
      return this.draft.initial.trim().length > 0 && Number.isFinite(initial) && initial >= 0 &&
        this.draft.step.trim().length > 0 && Number.isFinite(step) && step > 0;
    }
    if (type === ModuleType.Checklist) return this.draft.items.length > 0;
    if (type === ModuleType.EventRecord) return this.draft.recordName.trim().length > 0;
    if (type === ModuleType.Note) return this.draft.note.trim().length > 0;
    return false;
  }

  private summary(type: ModuleType): string {
    if (!this.hasResult(type)) return '';
    if (type === ModuleType.Deadline) {
      const result = dateSummary({ timestamp: this.draft.timestamp, mode: this.mode, hasTime: this.hasTime });
      return this.mode === 'deadline' ? result : formatDate(this.draft.timestamp) + ' · ' + result;
    }
    if (type === ModuleType.Counter) {
      return `${this.draft.initial || '0'} · 每次增加 ${this.draft.step || '1'}`;
    }
    if (type === ModuleType.Checklist) {
      return `共 ${this.draft.items.length} 项 · ` + this.draft.items.slice(0, 3).map((item: EditorItem) =>
        (item.targetId ? '事项：' : '文字：') + item.title).join('、');
    }
    if (type === ModuleType.EventRecord) return '点击「记录一次」，留下发生的时间';
    return this.draft.note;
  }

  private resultText(type: ModuleType): string {
    if (type === ModuleType.Deadline) return this.summary(type);
    if (type === ModuleType.Counter) {
      return `当前为 ${this.draft.initial || '0'}，每次点击增加 ${this.draft.step || '0'}`;
    }
    if (type === ModuleType.Checklist) {
      return `列表包含 ${this.draft.items.length} 项，移除关联不会删除原事项`;
    }
    if (type === ModuleType.EventRecord) return '保留每次发生的时间，方便以后回看';
    return this.draft.note ? '这段文字将保存在事项中' : '填写的文字会随事项一起保存';
  }

  private availableOptions(): ModuleOption[] {
    const order: ModuleType[] = [ModuleType.Deadline, ModuleType.Counter, ModuleType.Checklist,
      ModuleType.EventRecord, ModuleType.Note];
    const result: ModuleOption[] = [];
    for (const type of order) {
      if (this.draft.types.includes(type)) continue;
      const option = MODULE_OPTIONS.find((item: ModuleOption) => item.type === type);
      if (option) result.push(option);
    }
    return result;
  }

  private optionHelp(type: ModuleType): string {
    if (type === ModuleType.Deadline) return '倒数、累计天数或截止';
    if (type === ModuleType.Counter) return '累计次数或数量';
    if (type === ModuleType.Checklist) return '整理内容或关联事项';
    if (type === ModuleType.EventRecord) return '记下每次发生的时间';
    return '补充文字说明';
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

  build() {
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
        .enabled(!this.busy && !this.draft.token)
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
          .enabled(!this.busy)
          .opacity(this.busy ? 0.4 : 1)
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
    Column({ space: Space.md }) {
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

      Text('说明（可选）')
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkSoft);
      TextInput({ placeholder: '补充背景或提示', text: this.draft.description })
        .width('100%')
        .constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.body)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.ink)
        .placeholderColor(Colors.inkMuted)
        .caretColor(Colors.red)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.card)
        .padding({ left: Space.md, right: Space.md })
        .onChange((value: string) => { this.draft.description = value; this.changed(); });
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
          ModuleIcon({ moduleType: type, ink: Colors.ink, iconSize: 20 });
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
        Toggle({ type: ToggleType.Switch, isOn: true })
          .width(44)
          .height(26)
          .selectedColor(Colors.ink)
          .onChange((on: boolean) => {
            if (!on) this.disable(type);
          });
      }
      .width('100%')
      .constraintSize({ minHeight: 76 })
      .padding({ top: Space.md, bottom: Space.md })
      .onClick(() => this.toggleExpand(type));

      if (this.expanded === type) {
        Column({ space: Space.md }) {
          this.config(type);
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: Space.lg, bottom: Space.lg })
        .border({ width: { top: 1 }, color: Colors.hairline });

        if (this.hasResult(type)) {
          Column({ space: Space.xs }) {
            Text('设置结果')
              .fontSize(TypeSize.meta)
              .fontWeight(TypeWeight.regular)
              .fontColor(Colors.inkMuted);
            Text(this.resultText(type))
              .fontSize(TypeSize.body)
              .fontWeight(TypeWeight.regular)
              .fontColor(Colors.ink)
              .fontFeature(TABULAR_NUMS);
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(Space.md)
          .backgroundColor(Colors.wash)
          .borderRadius(Radius.card);
        }

        Row() {
          Text('修改自动保留')
            .fontSize(TypeSize.meta)
            .fontWeight(TypeWeight.regular)
            .fontColor(Colors.inkMuted);
          Blank();
          Button('收起设置 ⌃')
            .type(ButtonType.Normal)
            .constraintSize({ minHeight: 40 })
            .fontSize(TypeSize.bodySmall)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink)
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .padding({ left: Space.sm, right: 0 })
            .onClick(() => { this.expanded = ''; });
        }
        .width('100%')
        .padding({ top: Space.sm, bottom: Space.xs })
        .margin({ top: Space.md })
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
              Text(this.optionHelp(option.type))
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
      .onAreaChange((oldArea: Area, area: Area) => {
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
        .enabled(!this.busy)
        .opacity(this.busy ? 0.4 : 1)
        .onClick(() => { this.save(); });
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
      MatterDateEditor({ date: $date, mode: $mode, hasTime: $hasTime });

      Text('日期名称（可选）')
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkSoft);
      TextInput({ text: this.draft.dateName })
        .width('100%')
        .constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.body)
        .fontColor(Colors.ink)
        .placeholderColor(Colors.inkMuted)
        .caretColor(Colors.red)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.card)
        .padding({ left: Space.md, right: Space.md })
        .maxLength(30)
        .onChange((value: string) => { this.draft.dateName = value; this.changed(); });

      Text('地点（可选）')
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkSoft);
      TextInput({ text: this.draft.location })
        .width('100%')
        .constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.body)
        .fontColor(Colors.ink)
        .placeholderColor(Colors.inkMuted)
        .caretColor(Colors.red)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.card)
        .padding({ left: Space.md, right: Space.md })
        .onChange((value: string) => { this.draft.location = value; this.changed(); });
    } else if (type === ModuleType.Counter) {
      Text('计数名称（可选）')
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkSoft);
      TextInput({ text: this.draft.counterName })
        .width('100%')
        .constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.body)
        .fontColor(Colors.ink)
        .placeholderColor(Colors.inkMuted)
        .caretColor(Colors.red)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.card)
        .padding({ left: Space.md, right: Space.md })
        .maxLength(30)
        .onChange((value: string) => { this.draft.counterName = value; this.changed(); });

      Text('初始数值')
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkSoft);
      TextInput({ text: this.draft.initial })
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
        .onChange((value: string) => { this.draft.initial = value; this.changed(); });

      Text('每次增加')
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkSoft);
      TextInput({ text: this.draft.step })
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
        .onChange((value: string) => { this.draft.step = value; this.changed(); });
    } else if (type === ModuleType.Note) {
      Text('备注内容')
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkSoft);
      TextArea({ text: this.draft.note })
        .width('100%')
        .height(120)
        .fontSize(TypeSize.body)
        .fontColor(Colors.ink)
        .placeholderColor(Colors.inkMuted)
        .caretColor(Colors.red)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.card)
        .padding(Space.md)
        .onChange((value: string) => { this.draft.note = value; this.changed(); });
    } else if (type === ModuleType.EventRecord) {
      Text('记录名称（可选）')
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkSoft);
      TextInput({ text: this.draft.recordName })
        .width('100%')
        .constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.body)
        .fontColor(Colors.ink)
        .placeholderColor(Colors.inkMuted)
        .caretColor(Colors.red)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.card)
        .padding({ left: Space.md, right: Space.md })
        .maxLength(30)
        .onChange((value: string) => { this.draft.recordName = value; this.changed(); });
    } else if (type === ModuleType.Checklist) {
      this.listEditor();
    }
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
