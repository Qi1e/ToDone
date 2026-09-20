import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { formatDate, formatDateTime } from '../common/DateFormat';
import { Colors, Radius, Space } from '../common/Theme';
import { MODULE_OPTIONS, moduleLabel } from '../model/Defaults';
import {
  ChecklistItem,
  EventRecordEntry,
  Matter,
  ModuleInstance,
  ModuleOption,
  ModuleType
} from '../model/Types';
import { MatterStore } from '../store/MatterStore';
import { refreshKnownCards } from '../widget/CardRefresh';

interface MatterRouteParams {
  matterId?: string;
}

@Entry
@Component
struct MatterDetail {
  private store: MatterStore = MatterStore.getInstance();

  @State matterId: string = '';
  @State titleInput: string = '';
  @State descriptionInput: string = '';
  @State customCounterInput: string = '';
  @State deadlineDate: Date = new Date();
  @State deadlineLocationInput: string = '';
  @State noteInput: string = '';
  @State checklistInput: string = '';
  @State changedTick: number = 0;
  @State enabledModuleSnapshot: ModuleInstance[] = [];
  @State feedbackText: string = '';

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.store.init(context);
    const params = router.getParams() as MatterRouteParams;
    this.matterId = params.matterId ?? '';
    this.loadFields();
  }

  onPageShow(): void {
    this.loadFields();
  }

  private currentMatter(): Matter | undefined {
    return this.store.findMatter(this.matterId);
  }

  private loadFields(): void {
    const matter = this.currentMatter();
    if (!matter) {
      return;
    }
    this.titleInput = matter.title;
    this.descriptionInput = matter.description ?? '';
    const deadline = this.store.getDeadline(matter.id);
    this.deadlineDate = deadline ? new Date(deadline.timestamp) : new Date();
    this.deadlineLocationInput = deadline?.location ?? '';
    this.noteInput = this.store.getNote(matter.id);
    this.enabledModuleSnapshot = matter.enabledModules.slice();
    this.changedTick++;
  }

  private refreshOnly(): void {
    this.changedTick++;
  }

  private saveMatter(): void {
    this.store.updateMatter(this.matterId, this.titleInput, this.descriptionInput);
    this.loadFields();
    this.refreshCards('已保存事项');
  }

  private refreshCards(prefix: string): void {
    const result = refreshKnownCards(this.store);
    this.feedbackText = `${prefix}。${result.message}`;
  }

  private hasCurrentMatter(): boolean {
    return this.currentMatter() !== undefined;
  }

  private enabledModules(): ModuleInstance[] {
    return this.enabledModuleSnapshot.filter((module: ModuleInstance) => {
      return module.moduleType !== ModuleType.Countdown && module.moduleType !== ModuleType.Progress;
    });
  }

  private isModuleEnabled(type: ModuleType): boolean {
    return this.enabledModuleSnapshot.some((module: ModuleInstance) => module.moduleType === type);
  }

  private deadlineDisplayText(): string {
    const deadline = this.store.getDeadline(this.matterId);
    return deadline ? `当前：${formatDate(deadline.timestamp)}` : '未设置日期';
  }

  private dateFromPickerResult(value: DatePickerResult): Date {
    const year = value.year ?? this.deadlineDate.getFullYear();
    const month = value.month ?? this.deadlineDate.getMonth();
    const day = value.day ?? this.deadlineDate.getDate();
    return new Date(year, month, day);
  }

  build() {
    Navigation() {
      Scroll() {
        Column({ space: Space.large }) {
          this.TopBar();

          if (this.currentMatter()) {
            this.EditPanel();
            this.FeedbackText();
            this.ModuleSelector();
            this.EnabledModules();
          } else {
            Text('没有找到这个事项')
              .fontSize(18)
              .fontColor(Colors.subText)
              .padding(Space.large);
          }
        }
        .width('100%')
        .padding(Space.large);
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.page);
    }
    .title(this.titleInput.length > 0 ? this.titleInput : '事项')
    .mode(NavigationMode.Stack);
  }

  @Builder
  private FeedbackText() {
    if (this.feedbackText.length > 0) {
      Text(this.feedbackText)
        .fontSize(13)
        .fontColor(Colors.subText)
        .width('100%')
        .padding({ left: Space.small, right: Space.small });
    }
  }

  @Builder
  private TopBar() {
    Row() {
      Button('返回')
        .fontSize(14)
        .fontColor(Colors.primary)
        .backgroundColor(Colors.primarySoft)
        .borderRadius(Radius.normal)
        .onClick(() => {
          router.back();
        });
      Text('详情')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text)
        .margin({ left: Space.normal })
        .layoutWeight(1);
    }
    .width('100%');
  }

  @Builder
  private EditPanel() {
    Column({ space: Space.normal }) {
      Text('事项信息')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text);

      TextInput({ placeholder: '事项名称', text: this.titleInput })
        .height(44)
        .fontSize(16)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .onChange((value: string) => {
          this.titleInput = value;
        });

      TextInput({ placeholder: '说明，可不填', text: this.descriptionInput })
        .height(44)
        .fontSize(15)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .onChange((value: string) => {
          this.descriptionInput = value;
        });

      Button('保存事项')
        .width('100%')
        .height(42)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(Colors.primary)
        .borderRadius(Radius.normal)
        .onClick(() => this.saveMatter());
    }
    .padding(Space.large)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.large)
    .border({ width: 1, color: Colors.border });
  }

  @Builder
  private ModuleSelector() {
    if (this.hasCurrentMatter()) {
      Column({ space: Space.normal }) {
        Text('信息')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.text);

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(MODULE_OPTIONS, (option: ModuleOption) => {
            Button(this.isModuleEnabled(option.type) ? `已启用 ${option.label}` : option.label)
              .fontSize(14)
              .fontColor(this.isModuleEnabled(option.type) ? Color.White : Colors.primary)
              .backgroundColor(this.isModuleEnabled(option.type) ? Colors.primary : Colors.primarySoft)
              .borderRadius(Radius.normal)
              .margin({ right: Space.small, bottom: Space.small })
              .onClick(() => {
                this.store.toggleModule(this.matterId, option.type);
                this.loadFields();
                this.refreshCards('已更新模块');
              });
          }, (option: ModuleOption) => option.label);
        }
      }
      .padding(Space.large)
      .backgroundColor(Colors.surface)
      .borderRadius(Radius.large)
      .border({ width: 1, color: Colors.border });
    }
  }

  @Builder
  private EnabledModules() {
    if (this.hasCurrentMatter()) {
      ForEach(this.enabledModules(), (module: ModuleInstance) => {
        this.ModulePanel(module.moduleType);
      }, (module: ModuleInstance) => module.id);
    }
  }

  @Builder
  private ModulePanel(type: ModuleType) {
    Column({ space: Space.normal }) {
      Row() {
        Text(moduleLabel(type))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.text)
          .layoutWeight(1);
        Text('信息')
          .fontSize(12)
          .fontColor(Colors.subText)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(Colors.surfaceSoft)
          .borderRadius(Radius.small);
      }

      if (type === ModuleType.EventRecord) {
        this.EventRecordModule();
      }
      if (type === ModuleType.Counter) {
        this.CounterModule();
      }
      if (type === ModuleType.Deadline) {
        this.DeadlineModule();
      }
      if (type === ModuleType.Note) {
        this.NoteModule();
      }
      if (type === ModuleType.Checklist) {
        this.ChecklistModule();
      }
    }
    .padding(Space.large)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.large)
    .border({ width: 1, color: Colors.border });
  }

  @Builder
  private EventRecordModule() {
    Button('记录一次')
      .height(42)
      .fontSize(15)
      .fontColor(Color.White)
      .backgroundColor(Colors.primary)
      .borderRadius(Radius.normal)
      .onClick(() => {
        this.store.addEventRecord(this.matterId);
        this.refreshOnly();
        this.refreshCards('已记录一次');
      });

    ForEach(this.store.eventRecordsFor(this.matterId), (entry: EventRecordEntry) => {
      Text(formatDateTime(entry.timestamp))
        .fontSize(14)
        .fontColor(Colors.subText)
        .padding({ top: 4, bottom: 4 });
    }, (entry: EventRecordEntry) => entry.id);
  }

  @Builder
  private CounterModule() {
    Row({ space: Space.small }) {
      Text(`今日 ${this.store.counterToday(this.matterId)}`)
        .fontSize(16)
        .fontColor(Colors.text)
        .layoutWeight(1);
      Text(`累计 ${this.store.counterTotal(this.matterId)}`)
        .fontSize(16)
        .fontColor(Colors.subText);
    }

    Row({ space: Space.small }) {
      Button('+1')
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(Colors.primary)
        .borderRadius(Radius.normal)
        .onClick(() => {
          this.store.addCounterEntry(this.matterId, 1);
          this.refreshOnly();
          this.refreshCards('已增加计数');
        });
      Button('+10')
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(Colors.primary)
        .borderRadius(Radius.normal)
        .onClick(() => {
          this.store.addCounterEntry(this.matterId, 10);
          this.refreshOnly();
          this.refreshCards('已增加计数');
        });
      Button('今日一次')
        .fontSize(15)
        .fontColor(Colors.primary)
        .backgroundColor(Colors.primarySoft)
        .borderRadius(Radius.normal)
        .onClick(() => {
          this.store.markDailyOnce(this.matterId);
          this.refreshOnly();
          this.refreshCards('已记录今日一次');
        });
    }

    Row({ space: Space.small }) {
      TextInput({ placeholder: '自定义数值', text: this.customCounterInput })
        .height(42)
        .fontSize(15)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.customCounterInput = value;
        });
      Button('增加')
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(Colors.primary)
        .borderRadius(Radius.normal)
        .onClick(() => {
          const parsed = Number(this.customCounterInput);
          if (!Number.isNaN(parsed)) {
            this.store.addCounterEntry(this.matterId, parsed);
            this.customCounterInput = '';
            this.refreshOnly();
            this.refreshCards('已增加计数');
          }
        });
    }
  }

  @Builder
  private DeadlineModule() {
    Text(this.deadlineDisplayText())
      .fontSize(15)
      .fontColor(Colors.subText);

    DatePicker({
      start: new Date('2020-01-01T00:00:00'),
      end: new Date('2100-12-31T00:00:00'),
      selected: this.deadlineDate
    })
      .width('100%')
      .onChange((value: DatePickerResult) => {
        this.deadlineDate = this.dateFromPickerResult(value);
      });

    TextInput({ placeholder: '地点，可不填', text: this.deadlineLocationInput })
      .height(42)
      .fontSize(15)
      .backgroundColor(Colors.surfaceSoft)
      .borderRadius(Radius.normal)
      .onChange((value: string) => {
        this.deadlineLocationInput = value;
      });

    Button('保存截止日期')
      .height(42)
      .fontSize(15)
      .fontColor(Color.White)
      .backgroundColor(Colors.primary)
      .borderRadius(Radius.normal)
      .onClick(() => {
        this.store.setDeadline(this.matterId, this.deadlineDate.getTime(), this.deadlineLocationInput);
        this.loadFields();
        this.refreshCards('已保存截止日期');
      });
  }

  @Builder
  private NoteModule() {
    TextArea({ placeholder: '写一点备注', text: this.noteInput })
      .height(120)
      .fontSize(15)
      .backgroundColor(Colors.surfaceSoft)
      .borderRadius(Radius.normal)
      .onChange((value: string) => {
        this.noteInput = value;
      });
    Button('保存备注')
      .height(42)
      .fontSize(15)
      .fontColor(Color.White)
      .backgroundColor(Colors.primary)
      .borderRadius(Radius.normal)
      .onClick(() => {
        this.store.setNote(this.matterId, this.noteInput);
        this.loadFields();
        this.refreshCards('已保存备注');
      });
  }

  @Builder
  private ChecklistModule() {
    Text(this.store.listSummaryText(this.matterId))
      .fontSize(28)
      .fontWeight(FontWeight.Bold)
      .fontColor(Colors.primary);

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
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(Colors.primary)
        .borderRadius(Radius.normal)
        .onClick(() => {
          this.store.addChecklistItem(this.matterId, this.checklistInput);
          this.checklistInput = '';
          this.refreshOnly();
          this.refreshCards('已添加列表项');
        });
    }

    Button('添加独立事项')
      .width('100%')
      .height(40)
      .fontSize(14)
      .fontColor(Colors.primary)
      .backgroundColor(Colors.primarySoft)
      .borderRadius(Radius.normal)
      .onClick(() => {
        router.pushUrl({
          url: 'pages/CreateMatter',
          params: { ownerMatterId: this.matterId }
        });
      });

    this.AvailableMatterLinks();

    ForEach(this.store.checklistItemsFor(this.matterId), (item: ChecklistItem) => {
      this.ChecklistItemRow(item);
    }, (item: ChecklistItem) => item.id);
  }

  @Builder
  private AvailableMatterLinks() {
    if (this.linkableMatters().length > 0) {
      Column({ space: Space.small }) {
        Text('关联已有事项')
          .fontSize(14)
          .fontColor(Colors.subText);
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.linkableMatters(), (matter: Matter) => {
            Button(matter.title)
              .fontSize(13)
              .fontColor(Colors.primary)
              .backgroundColor(Colors.surfaceSoft)
              .borderRadius(Radius.normal)
              .margin({ right: Space.small, bottom: Space.small })
              .onClick(() => {
                this.store.addMatterListEntry(this.matterId, matter.id);
                this.refreshOnly();
                this.refreshCards('已关联事项');
              });
          }, (matter: Matter) => matter.id);
        }
      }
      .width('100%');
    }
  }

  @Builder
  private ChecklistItemRow(item: ChecklistItem) {
    if (item.entryType === 'matter_ref') {
      Row({ space: Space.small }) {
        Column({ space: 3 }) {
          Text(this.linkedMatterTitle(item))
            .fontSize(15)
            .fontColor(Colors.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.linkedMatterPrimary(item))
            .fontSize(13)
            .fontColor(Colors.subText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1);
        Button('打开')
          .fontSize(13)
          .fontColor(Colors.primary)
          .backgroundColor(Colors.primarySoft)
          .borderRadius(Radius.normal)
          .enabled(this.hasLinkedMatter(item))
          .onClick(() => {
            const linked = this.store.linkedMatterFor(item);
            if (linked) {
              router.pushUrl({
                url: 'pages/MatterDetail',
                params: { matterId: linked.id }
              });
            }
          });
        this.DeleteChecklistButton(item);
      }
      .padding({ top: 4, bottom: 4 });
    } else {
      Row({ space: Space.small }) {
        Button(item.completed ? '已完成' : '未完成')
          .fontSize(13)
          .fontColor(item.completed ? Color.White : Colors.primary)
          .backgroundColor(item.completed ? Colors.success : Colors.primarySoft)
          .borderRadius(Radius.normal)
          .onClick(() => {
            this.store.toggleChecklistItem(item.id);
            this.refreshOnly();
            this.refreshCards('已更新列表项');
          });
        Text(item.title)
          .fontSize(15)
          .fontColor(item.completed ? Colors.subText : Colors.text)
          .decoration({ type: item.completed ? TextDecorationType.LineThrough : TextDecorationType.None })
          .layoutWeight(1);
        this.DeleteChecklistButton(item);
      }
      .padding({ top: 4, bottom: 4 });
    }
  }

  @Builder
  private DeleteChecklistButton(item: ChecklistItem) {
    Button('删除')
      .fontSize(13)
      .fontColor(Colors.danger)
      .backgroundColor('#FFE7ED')
      .borderRadius(Radius.normal)
      .onClick(() => {
        this.store.deleteChecklistItem(item.id);
        this.refreshOnly();
        this.refreshCards('已删除列表项');
      });
  }

  private hasLinkedMatter(item: ChecklistItem): boolean {
    return this.store.linkedMatterFor(item) !== undefined;
  }

  private linkableMatters(): Matter[] {
    return this.store.availableMatterLinks(this.matterId);
  }

  private linkedMatterTitle(item: ChecklistItem): string {
    const linked = this.store.linkedMatterFor(item);
    return linked ? linked.title : `${item.title}（事项已删除）`;
  }

  private linkedMatterPrimary(item: ChecklistItem): string {
    const linked = this.store.linkedMatterFor(item);
    return linked ? this.store.cardPrimaryText(linked) : '关联事项不可用';
  }
}
