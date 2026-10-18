import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { Colors, Radius, Space } from '../common/Theme';
import { formatDate } from '../common/DateFormat';
import { MODULE_OPTIONS } from '../model/Defaults';
import { ModuleOption, ModuleType } from '../model/Types';
import { MatterService } from '../contracts/MatterService';
import { MatterServices } from '../application/MatterServices';

interface CreateMatterRouteParams {
  ownerMatterId?: string;
}

@Entry
@Component
struct CreateMatter {
  private service: MatterService = MatterServices.getService();
  private pageVisible: boolean = false;

  @State titleInput: string = '';
  @State descriptionInput: string = '';
  @State selectedModuleTypes: ModuleType[] = [];
  @State noteInput: string = '';
  @State checklistInput: string = '';
  @State initialChecklistItems: string[] = [];
  @State deadlineDate: Date = new Date();
  @State deadlineTimestamp: number = 0;
  @State deadlineLocationInput: string = '';
  @State feedbackText: string = '';
  @State ownerMatterId: string = '';
  @State isSaving: boolean = false;
  @State pendingMatterId: string = '';

  aboutToAppear(): void {
    this.pageVisible = true;
    const context = getContext(this) as common.UIAbilityContext;
    MatterServices.initialize(context);
    const params = router.getParams() as CreateMatterRouteParams | undefined;
    this.ownerMatterId = params?.ownerMatterId ?? '';
    this.deadlineDate = this.dateAtOffset(0);
  }

  aboutToDisappear(): void {
    this.pageVisible = false;
  }

  private dateAtOffset(offset: number): Date {
    const date = new Date();
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() + offset);
    return date;
  }

  private weekendDate(): Date {
    const date = this.dateAtOffset(0);
    const day = date.getDay();
    const offset = day === 0 ? 0 : 6 - day;
    date.setDate(date.getDate() + offset);
    return date;
  }

  private nextWeekDate(): Date {
    const date = this.dateAtOffset(0);
    const daysToMonday = ((8 - date.getDay()) % 7) || 7;
    date.setDate(date.getDate() + daysToMonday);
    return date;
  }

  private setDeadlineDate(date: Date): void {
    this.deadlineDate = new Date(date.getTime());
    this.deadlineTimestamp = this.deadlineDate.getTime();
  }

  private dateFromPickerResult(value: DatePickerResult): Date {
    const year = value.year ?? this.deadlineDate.getFullYear();
    const month = value.month ?? this.deadlineDate.getMonth();
    const day = value.day ?? this.deadlineDate.getDate();
    return new Date(year, month, day);
  }

  private isSelected(type: ModuleType): boolean {
    return this.selectedModuleTypes.includes(type);
  }

  private toggleModule(type: ModuleType): void {
    if (this.isSelected(type)) {
      this.selectedModuleTypes = this.selectedModuleTypes.filter((item: ModuleType) => item !== type);
      return;
    }
    this.selectedModuleTypes = [...this.selectedModuleTypes, type];
    if (type === ModuleType.Deadline && this.deadlineTimestamp === 0) {
      this.setDeadlineDate(this.dateAtOffset(0));
    }
  }

  private ownerTitle(): string {
    const owner = this.ownerMatterId.length > 0 ? this.service.findMatter(this.ownerMatterId) : undefined;
    return owner ? owner.title : '';
  }

  private async createMatter(): Promise<void> {
    if (this.isSaving) return;
    const title = this.titleInput.trim();
    if (title.length === 0) {
      this.feedbackText = '请先填写事项名称';
      return;
    }
    if (this.isSelected(ModuleType.Deadline) && this.deadlineTimestamp === 0) {
      this.feedbackText = '请先选择截止日期';
      return;
    }

    this.isSaving = true;
    try {
      const result = this.pendingMatterId.length > 0 ? await this.service.retrySave(this.pendingMatterId) :
        await this.service.createMatter({
          intent: {
            title,
            description: this.descriptionInput,
            enabledModuleTypes: this.selectedModuleTypes,
            deadlineTimestamp: this.isSelected(ModuleType.Deadline) ? this.deadlineTimestamp : undefined,
            deadlineLocation: this.isSelected(ModuleType.Deadline) ? this.deadlineLocationInput : undefined,
            note: this.isSelected(ModuleType.Note) ? this.noteInput : undefined
          },
          ownerMatterId: this.ownerMatterId,
          checklistTitles: this.isSelected(ModuleType.Checklist) ? this.initialChecklistItems : []
        });
      if (!result.success) {
        this.pendingMatterId = result.matterId;
        this.feedbackText = result.message;
        return;
      }
      this.pendingMatterId = result.matterId;
      MatterServices.requestCardRefresh();
      if (this.pageVisible) router.back();
    } catch (error) {
      this.feedbackText = '创建未完成，请返回首页确认事项状态后重试。';
    } finally {
      this.isSaving = false;
    }
  }

  build() {
    Navigation() {
      Scroll() {
        Column({ space: Space.large }) {
          this.TopBar();
          Column({ space: Space.large }) {
            this.TitlePanel();
            this.ModulePanel();
            this.SelectedModuleConfig();
          }
          .enabled(!this.isSaving && this.pendingMatterId.length === 0);

          Button(this.isSaving ? '正在保存' : (this.pendingMatterId.length > 0 ? '重试保存' :
            (this.ownerMatterId.length > 0 ? '创建并加入列表' : '创建事项')))
            .width('100%')
            .height(46)
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor(Colors.primary)
            .borderRadius(Radius.normal)
            .enabled(!this.isSaving)
            .onClick(() => { this.createMatter(); });

          if (this.feedbackText.length > 0) {
            Text(this.feedbackText)
              .fontSize(13)
              .fontColor(Colors.danger)
              .width('100%');
          }
        }
        .width('100%')
        .padding(Space.large);
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.page);
    }
    .title(this.ownerMatterId.length > 0 ? '添加列表事项' : '新建事项')
    .mode(NavigationMode.Stack);
  }

  @Builder
  private TopBar() {
    Row() {
      Button('返回')
        .enabled(!this.isSaving)
        .fontSize(14)
        .fontColor(Colors.primary)
        .backgroundColor(Colors.primarySoft)
        .borderRadius(Radius.normal)
        .onClick(() => router.back());
      Text(this.ownerMatterId.length > 0 ? '添加列表事项' : '新建事项')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text)
        .margin({ left: Space.normal });
    }
    .width('100%');
  }

  @Builder
  private TitlePanel() {
    Column({ space: Space.normal }) {
      if (this.ownerMatterId.length > 0 && this.ownerTitle().length > 0) {
        Text(`添加到「${this.ownerTitle()}」`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.text);
      }

      TextInput({ placeholder: '事项名称', text: this.titleInput })
        .height(46)
        .fontSize(17)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .onChange((value: string) => {
          this.titleInput = value;
        });

      TextInput({ placeholder: '说明（可选）', text: this.descriptionInput })
        .height(44)
        .fontSize(15)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .onChange((value: string) => {
          this.descriptionInput = value;
        });
    }
    .padding(Space.large)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.large)
    .border({ width: 1, color: Colors.border });
  }

  @Builder
  private ModulePanel() {
    Column({ space: Space.normal }) {
      Text('添加信息')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text);

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(MODULE_OPTIONS, (option: ModuleOption) => {
          Button(option.label)
            .fontSize(14)
            .fontColor(this.isSelected(option.type) ? Color.White : Colors.primary)
            .backgroundColor(this.isSelected(option.type) ? Colors.primary : Colors.primarySoft)
            .borderRadius(Radius.normal)
            .margin({ right: Space.small, bottom: Space.small })
            .onClick(() => this.toggleModule(option.type));
        }, (option: ModuleOption) => option.type);
      }
    }
    .padding(Space.large)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.large)
    .border({ width: 1, color: Colors.border });
  }

  @Builder
  private SelectedModuleConfig() {
    if (this.isSelected(ModuleType.Deadline)) {
      this.DeadlineConfigPanel();
    }
    if (this.isSelected(ModuleType.Note)) {
      this.NoteConfigPanel();
    }
    if (this.isSelected(ModuleType.Counter)) {
      this.CounterConfigPanel();
    }
    if (this.isSelected(ModuleType.Checklist)) {
      this.ChecklistConfigPanel();
    }
  }

  @Builder
  private DeadlineConfigPanel() {
    Column({ space: Space.normal }) {
      Text('截止日期')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text);

      Row({ space: Space.small }) {
        Button('今天')
          .fontSize(13)
          .fontColor(Colors.primary)
          .backgroundColor(Colors.primarySoft)
          .borderRadius(Radius.normal)
          .onClick(() => this.setDeadlineDate(this.dateAtOffset(0)));
        Button('明天')
          .fontSize(13)
          .fontColor(Colors.primary)
          .backgroundColor(Colors.primarySoft)
          .borderRadius(Radius.normal)
          .onClick(() => this.setDeadlineDate(this.dateAtOffset(1)));
        Button('本周末')
          .fontSize(13)
          .fontColor(Colors.primary)
          .backgroundColor(Colors.primarySoft)
          .borderRadius(Radius.normal)
          .onClick(() => this.setDeadlineDate(this.weekendDate()));
        Button('下周')
          .fontSize(13)
          .fontColor(Colors.primary)
          .backgroundColor(Colors.primarySoft)
          .borderRadius(Radius.normal)
          .onClick(() => this.setDeadlineDate(this.nextWeekDate()));
      }

      Text(`已选：${this.deadlineTimestamp === 0 ? '未选择' : formatDate(this.deadlineTimestamp)}`)
        .fontSize(15)
        .fontColor(this.deadlineTimestamp === 0 ? Colors.warning : Colors.text);

      DatePicker({
        start: new Date('2020-01-01T00:00:00'),
        end: new Date('2100-12-31T00:00:00'),
        selected: this.deadlineDate
      })
        .width('100%')
        .onChange((value: DatePickerResult) => this.setDeadlineDate(this.dateFromPickerResult(value)));

      TextInput({ placeholder: '地点，可不填', text: this.deadlineLocationInput })
        .height(42)
        .fontSize(15)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .onChange((value: string) => {
          this.deadlineLocationInput = value;
        });
    }
    .padding(Space.large)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.large)
    .border({ width: 1, color: Colors.border });
  }

  @Builder
  private NoteConfigPanel() {
    Column({ space: Space.normal }) {
      Text('备注')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text);
      TextArea({ placeholder: '备注（可选）', text: this.noteInput })
        .height(120)
        .fontSize(15)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .onChange((value: string) => {
          this.noteInput = value;
        });
    }
    .padding(Space.large)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.large)
    .border({ width: 1, color: Colors.border });
  }

  @Builder
  private CounterConfigPanel() {
    Column({ space: Space.small }) {
      Text('计数')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text);
    }
    .padding(Space.large)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.large)
    .border({ width: 1, color: Colors.border });
  }

  @Builder
  private ChecklistConfigPanel() {
    Column({ space: Space.small }) {
      Text('列表')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text);

      Row({ space: Space.small }) {
        TextInput({ placeholder: '列表项', text: this.checklistInput })
          .height(42)
          .fontSize(15)
          .backgroundColor(Colors.surfaceSoft)
          .borderRadius(Radius.normal)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.checklistInput = value;
          });
        Button('添加')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor(Colors.primary)
          .borderRadius(Radius.normal)
          .onClick(() => {
            const item = this.checklistInput.trim();
            if (item.length > 0) {
              this.initialChecklistItems = [...this.initialChecklistItems, item];
              this.checklistInput = '';
            }
          });
      }

      ForEach(this.initialChecklistItems, (item: string, index: number) => {
        Row() {
          Text(item)
            .fontSize(14)
            .fontColor(Colors.text)
            .layoutWeight(1);
          Button('删除')
            .fontSize(12)
            .fontColor(Colors.danger)
            .backgroundColor('#FFE7ED')
            .borderRadius(Radius.small)
            .onClick(() => {
              this.initialChecklistItems = this.initialChecklistItems.filter((_, itemIndex: number) => itemIndex !== index);
            });
        }
        .width('100%');
      });
    }
    .padding(Space.large)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.large)
    .border({ width: 1, color: Colors.border });
  }
}
