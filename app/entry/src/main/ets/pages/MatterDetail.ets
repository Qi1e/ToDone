import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { MatterServices } from '../application/MatterServices';
import { dateSummary, formatDateTime, timeConfigTitle } from '../common/DateFormat';
import {
  Colors,
  Radius,
  Space,
  TABULAR_NUMS,
  TypeSize,
  TypeWeight,
  resolveClusterColor
} from '../common/Theme';
import { ModuleIcon } from '../components/ModuleIcon';
import { TimelineAttachmentList } from '../components/TimelineAttachments';
import { TimelineLinkedNote } from '../components/TimelineLinkedNote';
import {
  TimelineAttachment,
  TimelineRepeat,
  timelineReminderLabel,
  timelineRepeatLabel,
  TimelineTag
} from '../contracts/TimelineService';
import { matterErrorMessage } from '../domain/MatterSnapshot';
import { TimelineNotePart, timelineNoteParts } from '../domain/TimelineNoteLinks';
import { moduleLabel } from '../model/Defaults';
import {
  ActiveCounterMode,
  ChecklistItem,
  CounterEntry,
  DeadlineConfig,
  Matter,
  ModuleInstance,
  ModuleType
} from '../model/Types';
import { MatterStore } from '../store/MatterStore';

interface MatterRouteParams {
  matterId?: string;
  occurrenceStart?: number;
}

@Entry
@Component
struct MatterDetail {
  @State private savingMatter: boolean = false;
  private store: MatterStore = MatterStore.getInstance();

  @State matterId: string = '';
  @State occurrenceStart?: number = undefined;
  @State titleInput: string = '';
  @State customCounterInput: string = '';
  @State entryNoteInput: string = '';
  @State noteText: string = '';
  @State noteAttachments: TimelineAttachment[] = [];
  @State checklistInput: string = '';
  @State changedTick: number = 0;
  @State enabledModuleSnapshot: ModuleInstance[] = [];
  @State private matter: Matter | undefined = undefined;
  @State private readError: string = '';
  private unsubscribe?: () => void;

  aboutToAppear(): void {
    const params = router.getParams() as MatterRouteParams | undefined;
    this.matterId = params?.matterId ?? '';
    this.occurrenceStart = params?.occurrenceStart;
    this.unsubscribe = this.store.subscribe(() => this.loadFields());
    this.load();
  }

  onPageShow(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
  }

  private async load(): Promise<void> {
    try {
      await this.store.init(getContext(this) as common.UIAbilityContext);
      this.readError = '';
      this.loadFields();
    } catch (error) {
      this.readError = matterErrorMessage(error as Error);
    }
  }

  private currentMatter(): Matter | undefined {
    return this.matter;
  }

  private loadFields(): void {
    const matter = this.store.findMatter(this.matterId);
    this.matter = matter;
    if (!matter) {
      return;
    }
    this.titleInput = matter.title;
    this.noteText = this.store.getNote(matter.id);
    this.noteAttachments = this.store.getAttachments(matter.id);
    this.enabledModuleSnapshot = matter.enabledModules.slice();
    this.changedTick++;
  }

  private refreshOnly(): void {
    this.changedTick++;
  }

  private refreshCards(action: string): void {
    const result = MatterServices.requestCardRefresh(action);
    this.getUIContext().getPromptAction().showToast({ message: result.message, duration: 1500 });
  }

  private hasCurrentMatter(): boolean {
    return this.currentMatter() !== undefined;
  }

  private displayModuleTypes(): ModuleType[] {
    const result: ModuleType[] = [];
    const pushOnce = (t: ModuleType): void => {
      if (!result.includes(t)) result.push(t);
    };
    for (const mod of this.enabledModuleSnapshot) {
      if (mod.moduleType === ModuleType.Countdown || mod.moduleType === ModuleType.Progress ||
        mod.moduleType === ModuleType.Tag) {
        continue;
      }
      if (mod.moduleType === ModuleType.EventRecord) {
        pushOnce(ModuleType.Counter);
      } else {
        pushOnce(mod.moduleType);
      }
    }
    if ((this.noteText.trim().length > 0 || this.noteAttachments.length > 0) && !result.includes(ModuleType.Note)) {
      pushOnce(ModuleType.Note);
    }
    return result;
  }

  private deadlineConfig(): DeadlineConfig | undefined {
    return this.store.getDeadline(this.matterId);
  }

  private deadlineDisplayText(): string {
    const deadline = this.deadlineConfig();
    return deadline ? dateSummary(deadline) : '未设置时间';
  }

  private isDeadlineUrgent(): boolean {
    const text = this.deadlineDisplayText();
    return text.includes('已逾期') || text.includes('今天截止');
  }

  private currentClusterColor(): Resource | undefined {
    const matter = this.currentMatter();
    if (!matter?.clusterId) {
      return undefined;
    }
    return resolveClusterColor(this.store.clusterColor(matter.clusterId));
  }

  private currentTag(): TimelineTag | undefined {
    const matter = this.currentMatter();
    return matter ? this.store.matterTag(matter) : undefined;
  }

  private noteHasLinks(text: string): boolean {
    return timelineNoteParts(text).some((p: TimelineNotePart) => p.href !== undefined);
  }

  private panelTitle(type: ModuleType): string {
    if (type === ModuleType.Deadline) {
      return timeConfigTitle(this.deadlineConfig());
    }
    if (type === ModuleType.Counter) {
      const mode = this.store.activeCounterMode(this.matterId);
      if (mode === 'tally') return '计次';
      if (mode === 'daily_once') return '每日打卡';
      return '计数';
    }
    return moduleLabel(type);
  }

  private async perform(write: () => Promise<void>): Promise<void> {
    if (this.savingMatter) return;
    this.savingMatter = true;
    try {
      await write();
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: matterErrorMessage(error as Error), duration: 3000 });
    } finally {
      this.savingMatter = false;
    }
  }

  build() {
    Navigation() {
      Scroll() {
        Column({ space: Space.lg }) {
          this.TopBar();

          if (this.readError) {
            Column({ space: Space.sm }) {
              Text(this.readError)
                .fontSize(TypeSize.bodySmall)
                .fontWeight(TypeWeight.semibold)
                .fontColor(Colors.red);
              Button('重新读取')
                .type(ButtonType.Normal)
                .constraintSize({ minHeight: 40 })
                .fontSize(TypeSize.body)
                .fontWeight(TypeWeight.semibold)
                .fontColor(Colors.ink)
                .backgroundColor(Colors.wash)
                .borderRadius(Radius.card)
                .padding({ left: Space.lg, right: Space.lg })
                .onClick(() => this.load());
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);
          } else if (this.currentMatter()) {
            Column({ space: Space.xs }) {
              Row({ space: Space.sm }) {
                if (this.currentClusterColor()) {
                  Column()
                    .width(8)
                    .height(8)
                    .borderRadius(4)
                    .backgroundColor(this.currentClusterColor() ?? Colors.ink);
                }
                Text(this.titleInput)
                  .fontSize(TypeSize.heading)
                  .fontWeight(TypeWeight.semibold)
                  .fontColor(Colors.ink)
                  .layoutWeight(1);
              }
              .width('100%')
              .alignItems(VerticalAlign.Center);

              if (this.currentTag()) {
                Row({ space: 6 }) {
                  Row()
                    .width(8)
                    .height(8)
                    .borderRadius(4)
                    .backgroundColor(this.currentTag()?.color ?? Colors.ink);
                  Text(this.currentTag()?.name ?? '')
                    .fontSize(TypeSize.bodySmall)
                    .fontColor(Colors.inkSoft);
                }
                .padding({ left: Space.sm, right: Space.sm, top: 4, bottom: 4 })
                .backgroundColor(Colors.wash)
                .borderRadius(Radius.chip)
                .alignItems(VerticalAlign.Center);
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            this.EnabledModules();
          } else {
            Text('没有找到这个事项')
              .fontSize(TypeSize.bodySmall)
              .fontWeight(TypeWeight.regular)
              .fontColor(Colors.inkSoft)
              .padding({ top: Space.xl, bottom: Space.xl });
          }
        }
        .width('100%')
        .padding({
          left: Space.page,
          right: Space.page,
          top: Space.lg,
          bottom: Space.xl
        });
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .backgroundColor(Colors.bg);
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack);
  }

  @Builder
  private TopBar() {
    Row({ space: Space.sm }) {
      Button('返回')
        .type(ButtonType.Normal)
        .constraintSize({ minHeight: 44 })
        .fontSize(TypeSize.body)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.ink)
        .backgroundColor(Color.Transparent)
        .borderRadius(Radius.card)
        .padding({ left: 0, right: Space.md })
        .onClick(() => {
          router.back();
        });
      Text('详情')
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkMuted)
        .layoutWeight(1);
      if (this.currentMatter() && !this.readError) {
        Button('编辑')
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 44 })
          .fontSize(TypeSize.body)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink)
          .backgroundColor(Color.Transparent)
          .borderRadius(Radius.card)
          .padding({ left: Space.md, right: 0 })
          .accessibilityText('编辑事项')
          .onClick(() => {
            router.pushUrl({
              url: 'pages/CreateMatter',
              params: { matterId: this.matterId, occurrenceStart: this.occurrenceStart }
            });
          });
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  private EnabledModules() {
    if (this.hasCurrentMatter()) {
      if (this.displayModuleTypes().length === 0) {
        Text('暂未启用附加信息，点击右上角「编辑」可添加时间、标签、计数、备注或列表。')
          .fontSize(TypeSize.bodySmall)
          .fontColor(Colors.inkMuted)
          .width('100%')
          .padding({ top: Space.md });
      } else {
        ForEach(this.displayModuleTypes(), (type: ModuleType) => {
          this.ModulePanel(type);
        }, (type: ModuleType) => `${type}_${this.changedTick}`);
      }
    }
  }

  @Builder
  private ModulePanel(type: ModuleType) {
    Column({ space: Space.md }) {
      Row({ space: Space.sm }) {
        ModuleIcon({ moduleType: type, ink: Colors.inkSoft, iconSize: 18 });
        Text(this.panelTitle(type))
          .fontSize(TypeSize.title)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink)
          .layoutWeight(1);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

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
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: Space.lg })
    .border({ width: { top: 1 }, color: Colors.hairline });
  }

  @Builder
  private CounterStatItem(label: string, value: string, highlight: boolean = false) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(TypeSize.meta)
        .fontColor(Colors.inkMuted);
      Text(value)
        .fontSize(TypeSize.figure)
        .fontWeight(TypeWeight.semibold)
        .fontColor(highlight ? Colors.ink : Colors.inkSoft)
        .fontFeature(TABULAR_NUMS);
    }
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private CounterModule() {
    Column({ space: Space.md }) {
      this.CounterFigures(this.store.activeCounterMode(this.matterId), this.store.counterUnit(this.matterId));
      this.CounterControls(this.store.activeCounterMode(this.matterId), this.store.counterUnit(this.matterId));
      this.CounterHistoryList(this.store.counterUnit(this.matterId));
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private CounterFigures(mode: ActiveCounterMode, unit: string) {
    Row({ space: Space.section }) {
      if (mode === 'daily_once') {
        this.CounterStatItem('连续打卡', `${this.store.counterStreakDays(this.matterId)} 天`, true);
        this.CounterStatItem('累计完成', `${this.store.counterTotal(this.matterId)} 天`);
      } else {
        this.CounterStatItem('今日', `${this.store.counterToday(this.matterId)}${unit ? ' ' + unit : ''}`, true);
        this.CounterStatItem('累计', `${this.store.counterTotal(this.matterId)}${unit ? ' ' + unit : ''}`);
        if (this.store.counterStreakDays(this.matterId) > 1) {
          this.CounterStatItem('连续', `${this.store.counterStreakDays(this.matterId)} 天`);
        }
      }
    }
    .width('100%');
  }

  @Builder
  private CounterControls(mode: ActiveCounterMode, unit: string) {
    if (mode === 'daily_once') {
      Row({ space: Space.sm }) {
        if (!this.store.isDailyDoneToday(this.matterId)) {
          TextInput({ placeholder: '打卡短记（可选）', text: this.entryNoteInput })
            .constraintSize({ minHeight: 40 })
            .fontSize(TypeSize.bodySmall)
            .fontColor(Colors.ink)
            .placeholderColor(Colors.inkMuted)
            .caretColor(Colors.red)
            .backgroundColor(Colors.wash)
            .borderRadius(Radius.card)
            .padding({ left: Space.md, right: Space.md })
            .maxLength(40)
            .layoutWeight(1)
            .onChange((val: string) => { this.entryNoteInput = val; });
        }
        Button(this.store.isDailyDoneToday(this.matterId) ? '✓ 今日已打卡（点按取消）' : '今日打卡')
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 42 })
          .fontSize(TypeSize.body)
          .fontWeight(TypeWeight.semibold)
          .fontColor(this.store.isDailyDoneToday(this.matterId) ? Colors.inkSoft : Colors.bg)
          .backgroundColor(this.store.isDailyDoneToday(this.matterId) ? Colors.wash : Colors.ink)
          .borderRadius(Radius.card)
          .padding({ left: Space.lg, right: Space.lg })
          .onClick(() => {
            this.perform(async (): Promise<void> => {
              const note = this.entryNoteInput.trim();
              const checked = await this.store.toggleDailyOnce(this.matterId, note);
              this.entryNoteInput = '';
              this.refreshOnly();
              this.refreshCards(checked ? '已完成今日打卡' : '已取消今日打卡');
            });
          });
      }
      .width('100%');
    } else if (mode === 'tally') {
      Row({ space: Space.sm }) {
        TextInput({ placeholder: '当次短备注（可选）', text: this.entryNoteInput })
          .constraintSize({ minHeight: 40 })
          .fontSize(TypeSize.bodySmall)
          .fontColor(Colors.ink)
          .placeholderColor(Colors.inkMuted)
          .caretColor(Colors.red)
          .backgroundColor(Colors.wash)
          .borderRadius(Radius.card)
          .padding({ left: Space.md, right: Space.md })
          .maxLength(40)
          .layoutWeight(1)
          .onChange((val: string) => { this.entryNoteInput = val; });

        Button(`记一${unit || '次'}`)
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 40 })
          .fontSize(TypeSize.body)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.bg)
          .backgroundColor(Colors.ink)
          .borderRadius(Radius.card)
          .padding({ left: Space.lg, right: Space.lg })
          .onClick(() => {
            this.perform(async (): Promise<void> => {
              const note = this.entryNoteInput.trim();
              await this.store.addCounterEntry(this.matterId, 1, undefined, note);
              this.entryNoteInput = '';
              this.refreshOnly();
              this.refreshCards('已记录一次');
            });
          });
      }
      .width('100%');
    } else {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.store.counterQuickSteps(this.matterId), (stepVal: number) => {
          Button(`+${stepVal}${unit ? ' ' + unit : ''}`)
            .type(ButtonType.Normal)
            .constraintSize({ minHeight: 40 })
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink)
            .backgroundColor(Colors.wash)
            .borderRadius(Radius.card)
            .padding({ left: Space.lg, right: Space.lg })
            .margin({ right: Space.sm, bottom: Space.xs })
            .onClick(() => {
              this.perform(async (): Promise<void> => {
                const note = this.entryNoteInput.trim();
                await this.store.addCounterEntry(this.matterId, stepVal, undefined, note);
                this.entryNoteInput = '';
                this.refreshOnly();
                this.refreshCards(`已增加 ${stepVal}${unit}`);
              });
            });
        }, (stepVal: number) => `step_${stepVal}`);
      }
      .width('100%');

      Row({ space: Space.xs }) {
        TextInput({ placeholder: '自定义数值', text: this.customCounterInput })
          .width(108)
          .constraintSize({ minHeight: 40 })
          .fontSize(TypeSize.body)
          .fontColor(Colors.ink)
          .placeholderColor(Colors.inkMuted)
          .caretColor(Colors.red)
          .type(InputType.NUMBER_DECIMAL)
          .backgroundColor(Colors.wash)
          .borderRadius(Radius.card)
          .padding({ left: Space.sm, right: Space.sm })
          .onChange((val: string) => { this.customCounterInput = val; });
        TextInput({ placeholder: '备注（可选）', text: this.entryNoteInput })
          .constraintSize({ minHeight: 40 })
          .fontSize(TypeSize.bodySmall)
          .fontColor(Colors.ink)
          .placeholderColor(Colors.inkMuted)
          .caretColor(Colors.red)
          .backgroundColor(Colors.wash)
          .borderRadius(Radius.card)
          .padding({ left: Space.sm, right: Space.sm })
          .maxLength(36)
          .layoutWeight(1)
          .onChange((val: string) => { this.entryNoteInput = val; });
        Button('增加')
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 40 })
          .fontSize(TypeSize.body)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink)
          .backgroundColor(Colors.wash)
          .borderRadius(Radius.card)
          .padding({ left: Space.md, right: Space.md })
          .onClick(() => {
            this.perform(async (): Promise<void> => {
              const parsed = Number(this.customCounterInput);
              if (Number.isFinite(parsed) && parsed !== 0) {
                const note = this.entryNoteInput.trim();
                await this.store.addCounterEntry(this.matterId, parsed, undefined, note);
                this.customCounterInput = '';
                this.entryNoteInput = '';
                this.refreshOnly();
                this.refreshCards('已更新计数');
              }
            });
          });
      }
      .width('100%');
    }
  }

  @Builder
  private CounterHistoryList(unit: string) {
    if (this.store.counterEntriesFor(this.matterId, 10).length > 0) {
      Column({ space: 2 }) {
        Text('最近记录')
          .fontSize(TypeSize.meta)
          .fontColor(Colors.inkMuted)
          .padding({ top: Space.xs, bottom: 2 });

        ForEach(this.store.counterEntriesFor(this.matterId, 10), (entry: CounterEntry) => {
          Row({ space: Space.xs }) {
            Column({ space: 2 }) {
              Text(
                `${entry.value > 0 ? '+' : ''}${entry.value}${unit ? ' ' + unit : ''}` +
                (entry.note ? ` · ${entry.note}` : '')
              )
                .fontSize(TypeSize.bodySmall)
                .fontColor(Colors.ink)
                .fontFeature(TABULAR_NUMS);
              Text(formatDateTime(entry.timestamp))
                .fontSize(TypeSize.meta)
                .fontColor(Colors.inkMuted)
                .fontFeature(TABULAR_NUMS);
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);

            Button('撤回')
              .type(ButtonType.Normal)
              .constraintSize({ minHeight: 34 })
              .fontSize(TypeSize.meta)
              .fontWeight(TypeWeight.semibold)
              .fontColor(Colors.inkSoft)
              .backgroundColor(Color.Transparent)
              .borderRadius(Radius.card)
              .padding({ left: Space.xs, right: Space.xs })
              .onClick(() => {
                this.perform(async (): Promise<void> => {
                  await this.store.removeCounterEntry(entry.id);
                  this.refreshOnly();
                  this.refreshCards('已撤回该条记录');
                });
              });
          }
          .width('100%')
          .padding({ top: 6, bottom: 6 })
          .border({ width: { top: 1 }, color: Colors.hairline });
        }, (entry: CounterEntry) => entry.id);
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start);
    }
  }

  @Builder
  private DeadlineModule() {
    Column({ space: Space.xs }) {
      Text(this.deadlineDisplayText())
        .fontSize(TypeSize.title)
        .fontWeight(TypeWeight.semibold)
        .fontColor(this.isDeadlineUrgent() ? Colors.red : Colors.ink)
        .fontFeature(TABULAR_NUMS)
        .width('100%');

      if (this.deadlineConfig()?.repeat && this.deadlineConfig()?.repeat !== TimelineRepeat.None) {
        Text(`重复 · ${timelineRepeatLabel(this.deadlineConfig()?.repeat ?? TimelineRepeat.None)}`)
          .fontSize(TypeSize.bodySmall)
          .fontColor(Colors.inkSoft)
          .width('100%');
      }
      if (this.deadlineConfig()?.reminderMinutes !== undefined) {
        Text(`提醒 · ${timelineReminderLabel(this.deadlineConfig()?.reminderMinutes)}`)
          .fontSize(TypeSize.bodySmall)
          .fontColor(Colors.inkSoft)
          .fontFeature(TABULAR_NUMS)
          .width('100%');
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private NoteModule() {
    Column({ space: Space.sm }) {
      if (this.noteText.trim().length > 0) {
        if (this.noteHasLinks(this.noteText)) {
          TimelineLinkedNote({ value: this.noteText });
        } else {
          Text(this.noteText)
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.regular)
            .fontColor(Colors.ink)
            .width('100%');
        }
      }
      if (this.noteAttachments.length > 0) {
        TimelineAttachmentList({ items: this.noteAttachments });
      }
      if (this.noteText.trim().length === 0 && this.noteAttachments.length === 0) {
        Text('暂无备注')
          .fontSize(TypeSize.body)
          .fontColor(Colors.inkMuted)
          .width('100%');
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private ChecklistModule() {
    Text(this.store.listSummaryText(this.matterId))
      .fontSize(TypeSize.figure)
      .fontWeight(TypeWeight.semibold)
      .fontColor(Colors.ink)
      .fontFeature(TABULAR_NUMS);

    Row({ space: Space.sm }) {
      TextInput({ placeholder: '列表项', text: this.checklistInput })
        .constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.body)
        .fontColor(Colors.ink)
        .placeholderColor(Colors.inkMuted)
        .caretColor(Colors.red)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.card)
        .padding({ left: Space.md, right: Space.md })
        .layoutWeight(1)
        .onChange((value: string) => {
          this.checklistInput = value;
        });
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
          this.perform(async (): Promise<void> => {
            await this.store.addChecklistItem(this.matterId, this.checklistInput);
            this.checklistInput = '';
            this.refreshOnly();
            this.refreshCards('已添加列表项');
          });
        });
    }
    .width('100%');

    Button('添加独立事项')
      .type(ButtonType.Normal)
      .width('100%')
      .constraintSize({ minHeight: 40 })
      .fontSize(TypeSize.body)
      .fontWeight(TypeWeight.semibold)
      .fontColor(Colors.ink)
      .backgroundColor(Colors.wash)
      .borderRadius(Radius.card)
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
      Column({ space: Space.sm }) {
        Text('关联已有事项')
          .fontSize(TypeSize.bodySmall)
          .fontWeight(TypeWeight.regular)
          .fontColor(Colors.inkSoft);
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.linkableMatters(), (matter: Matter) => {
            Button(matter.title)
              .type(ButtonType.Normal)
              .constraintSize({ minHeight: 40 })
              .fontSize(TypeSize.bodySmall)
              .fontWeight(TypeWeight.regular)
              .fontColor(Colors.ink)
              .backgroundColor(Colors.wash)
              .borderRadius(Radius.card)
              .padding({ left: Space.md, right: Space.md })
              .margin({ right: Space.sm, bottom: Space.sm })
              .onClick(() => {
                this.perform(async (): Promise<void> => {
                  await this.store.addMatterListEntry(this.matterId, matter.id);
                  this.refreshOnly();
                  this.refreshCards('已关联事项');
                });
              });
          }, (matter: Matter) => matter.id);
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start);
    }
  }

  @Builder
  private ChecklistItemRow(item: ChecklistItem) {
    if (item.entryType === 'matter_ref') {
      Row({ space: Space.sm }) {
        if (this.linkedMatterClusterColor(item)) {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.linkedMatterClusterColor(item) ?? Colors.ink);
        }
        Column({ space: Space.xs }) {
          Text(this.linkedMatterTitle(item))
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.linkedMatterPrimary(item))
            .fontSize(TypeSize.meta)
            .fontWeight(TypeWeight.regular)
            .fontColor(Colors.inkMuted)
            .fontFeature(TABULAR_NUMS)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
        Button('打开')
          .type(ButtonType.Normal)
          .constraintSize({ minHeight: 40 })
          .fontSize(TypeSize.bodySmall)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink)
          .backgroundColor(Color.Transparent)
          .borderRadius(Radius.card)
          .padding({ left: Space.sm, right: Space.sm })
          .enabled(this.hasLinkedMatter(item))
          .opacity(this.hasLinkedMatter(item) ? 1 : 0.4)
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
      .width('100%')
      .constraintSize({ minHeight: 48 })
      .alignItems(VerticalAlign.Center)
      .padding({ top: Space.xs, bottom: Space.xs })
      .border({ width: { top: 1 }, color: Colors.hairline });
    } else {
      Row({ space: Space.xs }) {
        Button() {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(20)
              .height(20)
              .borderRadius(Radius.chip)
              .backgroundColor(item.completed ? Colors.ink : Color.Transparent)
              .border({ width: 1, color: item.completed ? Colors.ink : Colors.line });
            if (item.completed) {
              Text('✓')
                .fontSize(TypeSize.meta)
                .fontWeight(TypeWeight.semibold)
                .fontColor(Colors.bg);
            }
          }
          .width(20)
          .height(20);
        }
        .type(ButtonType.Normal)
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .borderRadius(Radius.card)
        .margin({ left: -14 })
        .accessibilityText(item.completed ? '标记为未完成' : '标记为已完成')
        .onClick(() => {
          this.perform(async (): Promise<void> => {
            await this.store.toggleChecklistItem(item.id);
            this.refreshOnly();
            this.refreshCards('已更新列表项');
          });
        });
        Text(item.title)
          .fontSize(TypeSize.body)
          .fontWeight(TypeWeight.regular)
          .fontColor(item.completed ? Colors.inkMuted : Colors.ink)
          .decoration({ type: item.completed ? TextDecorationType.LineThrough : TextDecorationType.None })
          .layoutWeight(1);
        this.DeleteChecklistButton(item);
      }
      .width('100%')
      .constraintSize({ minHeight: 48 })
      .alignItems(VerticalAlign.Center)
      .border({ width: { top: 1 }, color: Colors.hairline });
    }
  }

  @Builder
  private DeleteChecklistButton(item: ChecklistItem) {
    Button('删除')
      .type(ButtonType.Normal)
      .constraintSize({ minHeight: 40 })
      .fontSize(TypeSize.bodySmall)
      .fontWeight(TypeWeight.semibold)
      .fontColor(Colors.red)
      .backgroundColor(Color.Transparent)
      .borderRadius(Radius.card)
      .padding({ left: Space.sm, right: Space.sm })
      .onClick(() => {
        this.perform(async (): Promise<void> => {
          await this.store.deleteChecklistItem(item.id);
          this.refreshOnly();
          this.refreshCards('已删除列表项');
        });
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

  private linkedMatterClusterColor(item: ChecklistItem): Resource | undefined {
    const linked = this.store.linkedMatterFor(item);
    if (!linked?.clusterId) {
      return undefined;
    }
    return resolveClusterColor(this.store.clusterColor(linked.clusterId));
  }
}
