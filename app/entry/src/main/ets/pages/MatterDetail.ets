import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { formatDate, formatDateTime, parseDate } from '../common/DateFormat';
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
  @State progressInput: string = '0';
  @State deadlineInput: string = '';
  @State deadlineLocationInput: string = '';
  @State noteInput: string = '';
  @State checklistInput: string = '';
  @State changedTick: number = 0;

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.store.init(context);
    const params = router.getParams() as MatterRouteParams;
    this.matterId = params.matterId ?? '';
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
    this.progressInput = `${this.store.getProgressPercent(matter.id)}`;
    const deadline = this.store.getDeadline(matter.id);
    this.deadlineInput = deadline ? formatDate(deadline.timestamp) : '';
    this.deadlineLocationInput = deadline?.location ?? '';
    this.noteInput = this.store.getNote(matter.id);
    this.changedTick++;
  }

  private refreshOnly(): void {
    this.changedTick++;
  }

  private saveMatter(): void {
    this.store.updateMatter(this.matterId, this.titleInput, this.descriptionInput);
    this.loadFields();
  }

  private hasCurrentMatter(): boolean {
    return this.currentMatter() !== undefined;
  }

  private enabledModules(): ModuleInstance[] {
    const matter = this.currentMatter();
    return matter ? matter.enabledModules : [];
  }

  private isModuleEnabled(type: ModuleType): boolean {
    const matter = this.currentMatter();
    return matter ? this.store.hasModule(matter, type) : false;
  }

  private deadlineDisplayText(): string {
    const deadline = this.store.getDeadline(this.matterId);
    return deadline ? `当前：${formatDate(deadline.timestamp)}` : '未设置日期';
  }

  build() {
    Navigation() {
      Scroll() {
        Column({ space: Space.large }) {
          this.TopBar();

          if (this.currentMatter()) {
            this.EditPanel();
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
        Text('模块')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.text);

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(MODULE_OPTIONS, (option: ModuleOption) => {
            Button(option.label)
              .fontSize(14)
              .fontColor(this.isModuleEnabled(option.type) ? Color.White : Colors.primary)
              .backgroundColor(this.isModuleEnabled(option.type) ? Colors.primary : Colors.primarySoft)
              .borderRadius(Radius.normal)
              .margin({ right: Space.small, bottom: Space.small })
              .onClick(() => {
                this.store.toggleModule(this.matterId, option.type);
                this.loadFields();
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
        Text('模块')
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
      if (type === ModuleType.Progress) {
        this.ProgressModule();
      }
      if (type === ModuleType.Deadline) {
        this.DeadlineModule();
      }
      if (type === ModuleType.Countdown) {
        this.CountdownModule();
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
        });
      Button('+10')
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(Colors.primary)
        .borderRadius(Radius.normal)
        .onClick(() => {
          this.store.addCounterEntry(this.matterId, 10);
          this.refreshOnly();
        });
      Button('今日一次')
        .fontSize(15)
        .fontColor(Colors.primary)
        .backgroundColor(Colors.primarySoft)
        .borderRadius(Radius.normal)
        .onClick(() => {
          this.store.markDailyOnce(this.matterId);
          this.refreshOnly();
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
          }
        });
    }
  }

  @Builder
  private ProgressModule() {
    Text(`${this.store.getProgressPercent(this.matterId)}%`)
      .fontSize(32)
      .fontWeight(FontWeight.Bold)
      .fontColor(Colors.primary);

    Slider({
      value: this.store.getProgressPercent(this.matterId),
      min: 0,
      max: 100,
      step: 1
    })
      .onChange((value: number) => {
        this.progressInput = `${Math.round(value)}`;
        this.store.setProgressPercent(this.matterId, value);
        this.refreshOnly();
      });

    Row({ space: Space.small }) {
      TextInput({ placeholder: '百分比', text: this.progressInput })
        .height(42)
        .fontSize(15)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.progressInput = value;
        });
      Button('保存')
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(Colors.primary)
        .borderRadius(Radius.normal)
        .onClick(() => {
          const parsed = Number(this.progressInput);
          if (!Number.isNaN(parsed)) {
            this.store.setProgressPercent(this.matterId, parsed);
            this.loadFields();
          }
        });
    }
  }

  @Builder
  private DeadlineModule() {
    Text(this.deadlineDisplayText())
      .fontSize(15)
      .fontColor(Colors.subText);

    TextInput({ placeholder: 'YYYY-MM-DD', text: this.deadlineInput })
      .height(42)
      .fontSize(15)
      .backgroundColor(Colors.surfaceSoft)
      .borderRadius(Radius.normal)
      .onChange((value: string) => {
        this.deadlineInput = value;
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
        const parsed = parseDate(this.deadlineInput);
        if (parsed) {
          this.store.setDeadline(this.matterId, parsed, this.deadlineLocationInput);
          this.loadFields();
        }
      });
  }

  @Builder
  private CountdownModule() {
    Text(this.store.countdownText(this.matterId))
      .fontSize(28)
      .fontWeight(FontWeight.Bold)
      .fontColor(Colors.primary);
    Text('倒计时根据截止日期自动计算，不重复保存日期。')
      .fontSize(14)
      .fontColor(Colors.subText);
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
      });
  }

  @Builder
  private ChecklistModule() {
    Text(this.store.checklistProgressText(this.matterId))
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
        });
    }

    ForEach(this.store.checklistItemsFor(this.matterId), (item: ChecklistItem) => {
      Row({ space: Space.small }) {
        Button(item.completed ? '已完成' : '未完成')
          .fontSize(13)
          .fontColor(item.completed ? Color.White : Colors.primary)
          .backgroundColor(item.completed ? Colors.success : Colors.primarySoft)
          .borderRadius(Radius.normal)
          .onClick(() => {
            this.store.toggleChecklistItem(item.id);
            this.refreshOnly();
          });
        Text(item.title)
          .fontSize(15)
          .fontColor(item.completed ? Colors.subText : Colors.text)
          .decoration({ type: item.completed ? TextDecorationType.LineThrough : TextDecorationType.None })
          .layoutWeight(1);
        Button('删除')
          .fontSize(13)
          .fontColor(Colors.danger)
          .backgroundColor('#FFE7ED')
          .borderRadius(Radius.normal)
          .onClick(() => {
            this.store.deleteChecklistItem(item.id);
            this.refreshOnly();
          });
      }
      .padding({ top: 4, bottom: 4 });
    }, (item: ChecklistItem) => item.id);
  }
}
