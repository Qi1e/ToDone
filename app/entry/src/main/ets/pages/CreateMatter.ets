import { common } from '@kit.AbilityKit';
import { EditorDraftStorage } from '../store/EditorDraftStorage';
import { MatterService } from '../contracts/MatterService';
import { router } from '@kit.ArkUI';
import { MatterServices } from '../application/MatterServices';
import { MatterDateEditor } from '../components/MatterDateEditor';
import { dateModeLabel, dateSummary, daysUntil, formatDate } from '../common/DateFormat';
import { Colors, Radius, Space } from '../common/Theme';
import { EditorDraft, EditorItem, invalidEditorField } from '../domain/MatterEditor';
import { createId, MODULE_OPTIONS, moduleLabel } from '../model/Defaults';
import { DateMode, Matter, ModuleOption, ModuleType } from '../model/Types';

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

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    MatterServices.initialize(context);
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
      return { width: 1, color: Colors.danger, radius: Radius.normal };
    }
    return {
      width: { left: 3, top: 1, right: 1, bottom: 1 },
      color: { left: Colors.primary, top: Colors.border, right: Colors.border, bottom: Colors.border },
      radius: Radius.normal
    };
  }

  build() {
    Column() {
      if (this.unavailable) {
        this.Header();
        Text(this.feedback).fontSize(15).fontColor(Colors.subText).margin({ top: Space.large });
      } else {
        List({ scroller: this.scroller, space: Space.small }) {
          ListItem() {
            this.Header();
          }.margin({ bottom: Space.small })

          if (this.resumed) {
            ListItem() {
              this.DraftBanner();
            }.margin({ bottom: Space.small })
          }

          ListItem() {
            this.TitleCard();
          }.margin({ bottom: Space.small })

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
            }.margin({ top: Space.small })
          }

          ListItem() {
            this.SubmitArea();
          }.margin({ top: Space.small })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .enabled(!this.busy && !this.draft.token)
      }
    }
    .width('100%')
    .height('100%')
    .padding(Space.large)
    .backgroundColor(Colors.page)
  }

  @Builder
  private Header() {
    Row({ space: Space.normal }) {
      Button('返回')
        .type(ButtonType.Normal)
        .height(40)
        .fontSize(14)
        .fontColor(Colors.primary)
        .backgroundColor(Colors.primarySoft)
        .borderRadius(Radius.normal)
        .padding({ left: 14, right: 14 })
        .enabled(!this.busy)
        .onClick(() => { if (!this.onBackPress()) router.back(); });
      Text(this.draft.editing ? '编辑事项' : this.ownerId ? '创建并加入列表' : '新建事项')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text)
        .maxLines(1)
        .layoutWeight(1);
    }
    .width('100%');
  }

  @Builder
  private DraftBanner() {
    Row({ space: Space.small }) {
      Text('已恢复未完成的草稿')
        .fontSize(13)
        .fontColor(Colors.primary)
        .layoutWeight(1);
      Button('重新开始')
        .type(ButtonType.Normal)
        .fontSize(13)
        .fontColor(Colors.primary)
        .backgroundColor(Color.Transparent)
        .padding(0)
        .onClick(() => this.restartDraft());
    }
    .width('100%')
    .padding(Space.normal)
    .backgroundColor(Colors.primarySoft)
    .borderRadius(Radius.normal);
  }

  @Builder
  private TitleCard() {
    Column({ space: Space.normal }) {
      Text('事项名称')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text);
      TextInput({ text: this.draft.title })
        .height(46)
        .fontSize(17)
        .fontColor(Colors.text)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .padding({ left: Space.normal, right: Space.normal })
        .border({ width: this.invalid === 'title' ? 1 : 0, color: Colors.danger })
        .maxLength(80)
        .onChange((value: string) => { this.draft.title = value; this.changed(); });

      Text('说明（可选）')
        .fontSize(13)
        .fontColor(Colors.subText);
      TextInput({ text: this.draft.description })
        .height(40)
        .fontSize(14)
        .fontColor(Colors.text)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .padding({ left: Space.normal, right: Space.normal })
        .onChange((value: string) => { this.draft.description = value; this.changed(); });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Space.large)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.large)
    .border({ width: 1, color: Colors.border });
  }

  @Builder
  private SectionHeading() {
    Row() {
      Text('事项信息')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text);
      Blank();
      Text(this.draft.types.length > 0 ? `已启用 ${this.draft.types.length} 项` : '可选')
        .fontSize(12)
        .fontColor(Colors.subText);
    }
    .width('100%')
    .margin({ bottom: Space.tiny });
  }

  @Builder
  private ModuleCard(type: ModuleType) {
    Column() {
      Row({ space: Space.small }) {
        Column({ space: 3 }) {
          Text('已启用')
            .fontSize(11)
            .fontColor(Colors.primary);
          Text(this.moduleTitle(type))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.text);
          if (this.hasResult(type)) {
            Text(this.summary(type))
              .fontSize(13)
              .fontColor(Colors.subText)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);

        Text(this.expanded === type ? '⌃' : '⌄')
          .fontSize(18)
          .fontColor(Colors.subText);
        Toggle({ type: ToggleType.Switch, isOn: true })
          .width(44)
          .height(26)
          .selectedColor(Colors.primary)
          .onChange((on: boolean) => {
            if (!on) this.disable(type);
          });
      }
      .width('100%')
      .constraintSize({ minHeight: 92 })
      .onClick(() => this.toggleExpand(type));

      if (this.expanded === type) {
        Column({ space: Space.normal }) {
          this.config(type);
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: Space.large, bottom: Space.large });

        if (this.hasResult(type)) {
          Column({ space: Space.tiny }) {
            Text('设置结果')
              .fontSize(13)
              .fontColor(Colors.subText);
            Text(this.resultText(type))
              .fontSize(14)
              .fontColor(Colors.text);
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(Space.normal)
          .backgroundColor(Colors.surfaceSoft)
          .borderRadius(Radius.normal);
        }

        Row() {
          Text('修改自动保留')
            .fontSize(12)
            .fontColor(Colors.subText);
          Blank();
          Button('收起设置 ⌃')
            .type(ButtonType.Normal)
            .fontSize(13)
            .fontColor(Colors.primary)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .onClick(() => { this.expanded = ''; });
        }
        .width('100%')
        .padding({ top: Space.normal })
        .border({ width: { top: 1 }, color: Colors.border });
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14 })
    .backgroundColor(Colors.surface)
    .border(this.cardBorder(type))
    .shadow({ radius: 12, color: '#0F101828', offsetX: 0, offsetY: 3 });
  }

  @Builder
  private AvailableTray() {
    Column({ space: Space.small }) {
      Row() {
        Text(this.draft.types.length > 0 ? '还可以启用' : '选择需要的信息')
          .fontSize(12)
          .fontColor(Colors.subText);
        Blank();
        Text('可多选')
          .fontSize(12)
          .fontColor(Colors.subText);
      }
      .width('100%')
      .padding({ left: 3, right: 3, bottom: Space.small });

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(this.availableOptions(), (option: ModuleOption) => {
          Row({ space: Space.small }) {
            Column({ space: 3 }) {
              Text(option.label)
                .fontSize(14)
                .fontColor(Colors.subText);
              Text(this.optionHelp(option.type))
                .fontSize(12)
                .fontColor(Colors.subText)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);

            Text('⌄')
              .fontSize(14)
              .fontColor(Colors.subText);
          }
          .width(this.compactWidth ? '100%' : '48%')
          .constraintSize({ minHeight: 64 })
          .padding({ left: 6, right: 6, top: 9, bottom: 9 })
          .borderRadius(Radius.small)
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
    .padding(Space.normal)
    .backgroundColor(Colors.surfaceSoft)
    .borderRadius(Radius.normal);
  }

  @Builder
  private SubmitArea() {
    Column({ space: Space.small }) {
      Button(this.busy ? '正在保存' : this.draft.token ? '重试保存' :
        this.draft.editing ? '保存修改' : '创建事项')
        .type(ButtonType.Normal)
        .width('100%')
        .height(46)
        .fontSize(16)
        .fontColor(Color.White)
        .backgroundColor(Colors.primary)
        .borderRadius(Radius.normal)
        .enabled(!this.busy)
        .onClick(() => { this.save(); });
      if (this.feedback) {
        Text(this.feedback)
          .fontSize(13)
          .fontColor(Colors.danger)
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
        .fontSize(15)
        .fontColor(Colors.text);
      TextInput({ text: this.draft.dateName })
        .height(44)
        .fontSize(15)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .padding({ left: Space.normal, right: Space.normal })
        .maxLength(30)
        .onChange((value: string) => { this.draft.dateName = value; this.changed(); });

      Text('地点（可选）')
        .fontSize(15)
        .fontColor(Colors.text);
      TextInput({ text: this.draft.location })
        .height(44)
        .fontSize(15)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .padding({ left: Space.normal, right: Space.normal })
        .onChange((value: string) => { this.draft.location = value; this.changed(); });
    } else if (type === ModuleType.Counter) {
      Text('计数名称（可选）')
        .fontSize(15)
        .fontColor(Colors.text);
      TextInput({ text: this.draft.counterName })
        .height(44)
        .fontSize(15)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .padding({ left: Space.normal, right: Space.normal })
        .maxLength(30)
        .onChange((value: string) => { this.draft.counterName = value; this.changed(); });

      Text('初始数值')
        .fontSize(15)
        .fontColor(Colors.text);
      TextInput({ text: this.draft.initial })
        .height(44)
        .fontSize(15)
        .type(InputType.NUMBER_DECIMAL)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .padding({ left: Space.normal, right: Space.normal })
        .onChange((value: string) => { this.draft.initial = value; this.changed(); });

      Text('每次增加')
        .fontSize(15)
        .fontColor(Colors.text);
      TextInput({ text: this.draft.step })
        .height(44)
        .fontSize(15)
        .type(InputType.NUMBER_DECIMAL)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .padding({ left: Space.normal, right: Space.normal })
        .onChange((value: string) => { this.draft.step = value; this.changed(); });
    } else if (type === ModuleType.Note) {
      Text('备注内容')
        .fontSize(15)
        .fontColor(Colors.text);
      TextArea({ text: this.draft.note })
        .width('100%')
        .height(120)
        .fontSize(15)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .padding(Space.normal)
        .onChange((value: string) => { this.draft.note = value; this.changed(); });
    } else if (type === ModuleType.EventRecord) {
      Text('记录名称（可选）')
        .fontSize(15)
        .fontColor(Colors.text);
      TextInput({ text: this.draft.recordName })
        .height(44)
        .fontSize(15)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .padding({ left: Space.normal, right: Space.normal })
        .maxLength(30)
        .onChange((value: string) => { this.draft.recordName = value; this.changed(); });
    } else if (type === ModuleType.Checklist) {
      this.listEditor();
    }
  }

  @Builder
  private listEditor() {
    Row({ space: Space.small }) {
      TextInput({ text: this.draft.pending })
        .height(42)
        .fontSize(15)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .padding({ left: Space.normal, right: Space.normal })
        .layoutWeight(1)
        .onChange((value: string) => { this.draft.pending = value; this.changed(); });
      Button('添加')
        .type(ButtonType.Normal)
        .height(42)
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor(Colors.primary)
        .borderRadius(Radius.normal)
        .padding({ left: 14, right: 14 })
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
      .fontSize(14)
      .fontColor(Colors.primary)
      .backgroundColor(Color.Transparent)
      .padding({ top: 17, bottom: 17 })
      .onClick(() => {
        this.picking = !this.picking;
        this.candidates = this.service.linkCandidates(this.draft, this.ownerId);
      });

    if (this.picking) {
      Column({ space: Space.small }) {
        if (!this.candidates.length) {
          Text('暂无可关联事项')
            .fontSize(13)
            .fontColor(Colors.subText);
        }
        ForEach(this.candidates, (matter: Matter) => {
          Button(matter.title)
            .type(ButtonType.Normal)
            .width('100%')
            .height(42)
            .fontSize(14)
            .fontColor(Colors.text)
            .backgroundColor(Colors.surface)
            .borderRadius(Radius.small)
            .onClick(() => {
              this.draft.items = this.draft.items.concat({ id: createId('link'), title: matter.title, targetId: matter.id });
              this.picking = false;
              this.changed();
            });
        }, (matter: Matter) => matter.id);
      }
      .width('100%')
      .padding(Space.small)
      .backgroundColor(Colors.surfaceSoft)
      .borderRadius(Radius.normal);
    }

    ForEach(this.draft.items, (item: EditorItem) => {
      Row({ space: Space.small }) {
        Column({ space: 2 }) {
          if (!item.targetId && this.editingItemId === item.id) {
            TextInput({ text: item.title })
              .height(36)
              .fontSize(14)
              .backgroundColor(Colors.surfaceSoft)
              .borderRadius(Radius.small)
              .padding({ left: Space.small, right: Space.small })
              .onChange((value: string) => {
                item.title = value;
                this.changed();
              });
          } else {
            Text(item.targetId ? (this.service.findMatter(item.targetId)?.title ?? item.title) : item.title)
              .fontSize(14)
              .fontColor(Colors.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(item.targetId ? '关联事项' : '文字项')
              .fontSize(12)
              .fontColor(Colors.subText);
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);

        if (!item.targetId) {
          Button(this.editingItemId === item.id ? '完成' : '修改')
            .type(ButtonType.Normal)
            .fontSize(13)
            .fontColor(Colors.primary)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .onClick(() => {
              this.editingItemId = this.editingItemId === item.id ? '' : item.id;
            });
        }
        Button('移除')
          .type(ButtonType.Normal)
          .fontSize(13)
          .fontColor(Colors.primary)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .onClick(() => {
            this.draft.items = this.draft.items.filter((entry: EditorItem) => entry.id !== item.id);
            if (this.editingItemId === item.id) this.editingItemId = '';
            this.changed();
          });
      }
      .width('100%')
      .padding(Space.normal)
      .border({ width: { bottom: 1 }, color: Colors.border });
    }, (item: EditorItem) => item.id);
  }
}
