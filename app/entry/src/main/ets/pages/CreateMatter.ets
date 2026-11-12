import { common } from '@kit.AbilityKit';
import { EditorDraftStorage } from '../store/EditorDraftStorage';
import { MatterService } from '../contracts/MatterService';
import { router } from '@kit.ArkUI';
import { MatterServices } from '../application/MatterServices';
import { MatterDateEditor } from '../components/MatterDateEditor';
import { dateSummary } from '../common/DateFormat';
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
  private key: string = '';
  private ownerId: string = '';
  private ready: boolean = false;
  private timer: number = -1;
  private original: string = '';
  @State compactWidth: boolean = false;
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

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    MatterServices.initialize(context);
    const route = router.getParams() as EditorRoute | undefined;
    const id = route?.matterId ?? '';
    this.ownerId = route?.ownerMatterId ?? '';
    this.key = id ? 'edit_' + id : this.ownerId ? 'owner_' + this.ownerId : 'new';
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
        this.storage = new EditorDraftStorage(context, this.key);
        const saved = this.storage.read();
        if (saved) this.draft = JSON.parse(saved) as EditorDraft;
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

  private activate(type: ModuleType): void {
    if (!this.draft.types.includes(type)) {
      this.draft.types = this.draft.types.concat(type);
      this.changed();
    }
    this.expanded = this.expanded === type ? '' : type;
    this.picking = false;
    const index = this.draft.types.indexOf(type) + 1;
    setTimeout(() => this.scroller.scrollToIndex(index, false, ScrollAlign.START), 0);
  }

  private disable(type: ModuleType): void {
    this.draft.types = this.draft.types.filter((item: ModuleType) => item !== type);
    if (this.expanded === type) this.expanded = '';
    this.changed();
  }

  private async save(): Promise<void> {
    if (this.busy) return;
    this.invalid = invalidEditorField(this.draft);
    if (this.invalid) {
      if (this.invalid === 'title') this.feedback = '请填写事项名称';
      if (this.invalid === ModuleType.Deadline) this.feedback = '正数日的起始日期不能晚于今天';
      if (this.invalid === ModuleType.Note) this.feedback = '请填写备注内容';
      if (this.invalid === ModuleType.Counter) this.feedback = '初始数值须非负，每次增加须大于零';
      if (this.invalid === ModuleType.Checklist) this.feedback = '请填写或移除空列表项';
      if (this.invalid !== 'title') this.expanded = this.invalid;
      const index = this.draft.types.findIndex((type: ModuleType) => type === this.invalid) + 1;
      setTimeout(() => this.scroller.scrollToIndex(index, false, ScrollAlign.START), 0);
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
    return name ? moduleLabel(type) + ' · ' + name : moduleLabel(type);
  }

  private summary(type: ModuleType): string {
    if (type === ModuleType.Deadline) return dateSummary({ timestamp: this.draft.timestamp, mode: this.mode, hasTime: this.hasTime });
    if (type === ModuleType.Counter) return `${this.draft.initial} · 每次增加 ${this.draft.step}`;
    if (type === ModuleType.Checklist) return this.draft.items.length ?
      `共 ${this.draft.items.length} 项 · ${this.draft.items.slice(0, 3).map((i: EditorItem) =>
        (i.targetId ? '事项：' : '文字：') + i.title).join('、')}` : '';
    if (type === ModuleType.EventRecord) return this.draft.recordName;
    return this.draft.note;
  }

  build() {
    Column({ space: Space.small }) {
      Row({ space: Space.normal }) {
        Button('返回').onClick(() => { if (!this.onBackPress()) router.back(); })
        Text(this.draft.editing ? '编辑事项' : this.ownerId ? '创建并加入列表' : '创建事项').fontSize(22)
      }.width('100%')
      if (!this.unavailable) {
        List({ scroller: this.scroller, space: Space.normal }) {
          ListItem() {
            Column({ space: Space.small }) {
              Text('事项名称')
              TextInput({ text: this.draft.title }).onChange((v: string) => { this.draft.title = v; this.changed(); })
                .border({ width: 1, color: this.invalid === 'title' ? Colors.danger : Colors.border })
              Text('说明（可选）')
              TextInput({ text: this.draft.description }).onChange((v: string) => { this.draft.description = v; this.changed(); })
            }.alignItems(HorizontalAlign.Start)
          }
          ForEach(this.draft.types, (type: ModuleType) => {
            ListItem() {
              Column({ space: Space.small }) {
                Row({ space: Space.small }) {
                  Button(this.moduleTitle(type)).onClick(() => this.activate(type))
                  Blank()
                  Button('关闭模块').onClick(() => this.disable(type))
                }.width('100%')
                if (this.expanded === type) {
                  this.config(type)
                } else if (this.summary(type)) {
                  Text(this.summary(type)).maxLines(2)
                }
              }.padding(Space.normal).width('100%').backgroundColor(Colors.surface)
                .borderRadius(Radius.normal).border({ width: 1, color: this.invalid === type ? Colors.danger : Colors.border })
            }
          }, (type: ModuleType) => type)
          ListItem() {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(MODULE_OPTIONS.filter((o: ModuleOption) => !this.draft.types.includes(o.type)), (o: ModuleOption) => {
                Column() {
                  Text(o.label).fontSize(16)
                  Text(o.description).fontSize(13).fontColor(Colors.subText)
                }.width(this.compactWidth ? '100%' : '48%').padding(Space.small)
                  .onClick(() => this.activate(o.type))
              }, (o: ModuleOption) => o.type)
            }.width('100%').backgroundColor(Colors.surfaceSoft)
              .onAreaChange((oldArea: Area, area: Area) => {
                const scale = getContext(this).config.fontSizeScale ?? 1;
                this.compactWidth = Number(area.width) < 300 || scale >= 1.5;
              })
          }
        }.layoutWeight(1).enabled(!this.busy && !this.draft.token)
        Button(this.busy ? '正在保存' : this.draft.token ? '重试保存' : this.draft.editing ? '保存修改' : '创建事项')
          .width('100%').enabled(!this.busy).onClick(() => { this.save(); })
      }
      if (this.feedback) { Text(this.feedback).fontColor(Colors.danger) }
    }.width('100%').height('100%').padding(Space.normal).backgroundColor(Colors.page)
  }

  @Builder
  private config(type: ModuleType) {
    if (type === ModuleType.Deadline) {
      Text('日期名称（可选）')
      TextInput({ text: this.draft.dateName }).maxLength(30)
        .onChange((v: string) => { this.draft.dateName = v; this.changed(); })
      MatterDateEditor({ date: $date, mode: $mode, hasTime: $hasTime })
      Text('地点（可选）')
      TextInput({ text: this.draft.location }).onChange((v: string) => { this.draft.location = v; this.changed(); })
    } else if (type === ModuleType.Counter) {
      Text('计数名称（可选）')
      TextInput({ text: this.draft.counterName }).maxLength(30)
        .onChange((v: string) => { this.draft.counterName = v; this.changed(); })
      Text('初始数值')
      TextInput({ text: this.draft.initial }).type(InputType.NUMBER_DECIMAL)
        .onChange((v: string) => { this.draft.initial = v; this.changed(); })
      Text('每次增加')
      TextInput({ text: this.draft.step }).type(InputType.NUMBER_DECIMAL)
        .onChange((v: string) => { this.draft.step = v; this.changed(); })
    } else if (type === ModuleType.Note) {
      TextArea({ text: this.draft.note }).onChange((v: string) => { this.draft.note = v; this.changed(); })
    } else if (type === ModuleType.EventRecord) {
      Text('记录名称（可选）')
      TextInput({ text: this.draft.recordName }).onChange((v: string) => { this.draft.recordName = v; this.changed(); })
    } else if (type === ModuleType.Checklist) {
      this.listEditor()
    }
  }

  @Builder
  private listEditor() {
    ForEach(this.draft.items, (item: EditorItem) => {
      Row() {
        if (item.targetId) {
          Text(`事项 · ${this.service.findMatter(item.targetId)?.title ?? item.title}`).layoutWeight(1)
        } else {
          TextInput({ text: item.title }).layoutWeight(1).onChange((v: string) => {
            item.title = v;
            this.changed();
          })
        }
        Button('移除').onClick(() => {
          this.draft.items = this.draft.items.filter((i: EditorItem) => i.id !== item.id);
          this.changed();
        })
      }
    }, (i: EditorItem) => i.id)
    Row() {
      TextInput({ text: this.draft.pending }).layoutWeight(1)
        .onChange((v: string) => { this.draft.pending = v; this.changed(); })
      Button('添加文字').onClick(() => {
        if (this.draft.pending.trim()) {
          this.draft.items = this.draft.items.concat({ id: createId('check'), title: this.draft.pending.trim() });
          this.draft.pending = '';
          this.changed();
        }
      })
    }
    Button('关联事项').onClick(() => {
      this.picking = !this.picking;
      this.candidates = this.service.linkCandidates(this.draft, this.ownerId);

    })
    if (this.picking) {
      if (!this.candidates.length) { Text('暂无可关联事项') }
      ForEach(this.candidates, (m: Matter) => {
        Button(m.title).onClick(() => {
          this.draft.items = this.draft.items.concat({ id: createId('link'), title: m.title, targetId: m.id });
          this.picking = false;
          this.changed();
        })
      }, (m: Matter) => m.id)
    }
  }
}
