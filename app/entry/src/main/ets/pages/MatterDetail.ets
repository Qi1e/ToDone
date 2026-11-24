import { matterErrorMessage } from '../domain/MatterSnapshot';
import { dateSummary } from '../common/DateFormat';
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { MatterServices } from '../application/MatterServices';
import { formatDateTime } from '../common/DateFormat';
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
import { moduleLabel } from '../model/Defaults';
import {
  ChecklistItem,
  EventRecordEntry,
  Matter,
  ModuleInstance,
  ModuleType
} from '../model/Types';
import { MatterStore } from '../store/MatterStore';

interface MatterRouteParams {
  matterId?: string;
}

@Entry
@Component
struct MatterDetail {
  @State private savingMatter: boolean = false;
  private store: MatterStore = MatterStore.getInstance();

  @State matterId: string = '';
  @State titleInput: string = '';
  @State descriptionInput: string = '';
  @State customCounterInput: string = '';
  @State noteInput: string = '';
  @State checklistInput: string = '';
  @State changedTick: number = 0;
  @State enabledModuleSnapshot: ModuleInstance[] = [];
  @State private matter: Matter | undefined = undefined;
  @State private readError: string = '';
  private unsubscribe?: () => void;

  aboutToAppear(): void {
    const params = router.getParams() as MatterRouteParams;
    this.matterId = params.matterId ?? '';
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
    this.descriptionInput = matter.description ?? '';
    this.noteInput = this.store.getNote(matter.id);
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

  private enabledModules(): ModuleInstance[] {
    return this.enabledModuleSnapshot.filter((module: ModuleInstance) => {
      return module.moduleType !== ModuleType.Countdown && module.moduleType !== ModuleType.Progress;
    });
  }

  private deadlineDisplayText(): string {
    const deadline = this.store.getDeadline(this.matterId);
    return deadline ? dateSummary(deadline) : '未设置日期';
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
            Column({ space: Space.sm }) {
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

              if (this.descriptionInput) {
                Text(this.descriptionInput)
                  .fontSize(TypeSize.bodySmall)
                  .fontWeight(TypeWeight.regular)
                  .fontColor(Colors.inkSoft)
                  .width('100%');
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
            router.pushUrl({ url: 'pages/CreateMatter', params: { matterId: this.matterId } });
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
      ForEach(this.enabledModules(), (module: ModuleInstance) => {
        this.ModulePanel(module.moduleType);
      }, (module: ModuleInstance) => module.id + '_' + this.changedTick);
    }
  }

  @Builder
  private ModulePanel(type: ModuleType) {
    Column({ space: Space.md }) {
      Row({ space: Space.sm }) {
        ModuleIcon({ moduleType: type, ink: Colors.inkSoft, iconSize: 18 });
        Text(type === ModuleType.EventRecord
          ? (this.enabledModuleSnapshot.find((m: ModuleInstance) => m.moduleType === type)?.name || moduleLabel(type))
          : moduleLabel(type))
          .fontSize(TypeSize.title)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink)
          .layoutWeight(1);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

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
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: Space.lg })
    .border({ width: { top: 1 }, color: Colors.hairline });
  }

  @Builder
  private EventRecordModule() {
    Button('记录一次')
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
          await this.store.addEventRecord(this.matterId);
          this.refreshOnly();
          this.refreshCards('已记录一次');
        });
      });

    ForEach(this.store.eventRecordsFor(this.matterId), (entry: EventRecordEntry) => {
      Text(formatDateTime(entry.timestamp))
        .fontSize(TypeSize.body)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkSoft)
        .fontFeature(TABULAR_NUMS)
        .width('100%')
        .padding({ top: Space.xs, bottom: Space.xs });
    }, (entry: EventRecordEntry) => entry.id);
  }

  @Builder
  private CounterModule() {
    Row({ space: Space.section }) {
      Column({ space: Space.xs }) {
        Text('今日')
          .fontSize(TypeSize.meta)
          .fontWeight(TypeWeight.regular)
          .fontColor(Colors.inkMuted);
        Text(`${this.store.counterToday(this.matterId)}`)
          .fontSize(TypeSize.figure)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink)
          .fontFeature(TABULAR_NUMS);
      }
      .alignItems(HorizontalAlign.Start);

      Column({ space: Space.xs }) {
        Text('累计')
          .fontSize(TypeSize.meta)
          .fontWeight(TypeWeight.regular)
          .fontColor(Colors.inkMuted);
        Text(`${this.store.counterTotal(this.matterId)}`)
          .fontSize(TypeSize.figure)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.inkSoft)
          .fontFeature(TABULAR_NUMS);
      }
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%');

    Flex({ wrap: FlexWrap.Wrap }) {
      Button(`+${this.store.counterStep(this.matterId)}`)
        .type(ButtonType.Normal)
        .constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.body)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.ink)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.card)
        .padding({ left: Space.lg, right: Space.lg })
        .margin({ right: Space.sm, bottom: Space.sm })
        .onClick(() => {
          this.perform(async (): Promise<void> => {
            await this.store.addCounterEntry(this.matterId, this.store.counterStep(this.matterId));
            this.refreshOnly();
            this.refreshCards('已增加计数');
          });
        });
      Button('+10')
        .type(ButtonType.Normal)
        .constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.body)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.ink)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.card)
        .padding({ left: Space.lg, right: Space.lg })
        .margin({ right: Space.sm, bottom: Space.sm })
        .onClick(() => {
          this.perform(async (): Promise<void> => {
            await this.store.addCounterEntry(this.matterId, 10);
            this.refreshOnly();
            this.refreshCards('已增加计数');
          });
        });
      Button('今日一次')
        .type(ButtonType.Normal)
        .constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.body)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.ink)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.card)
        .padding({ left: Space.lg, right: Space.lg })
        .margin({ right: Space.sm, bottom: Space.sm })
        .onClick(() => {
          this.perform(async (): Promise<void> => {
            await this.store.markDailyOnce(this.matterId);
            this.refreshOnly();
            this.refreshCards('已记录今日一次');
          });
        });
    }
    .width('100%');

    Row({ space: Space.sm }) {
      TextInput({ placeholder: '自定义数值', text: this.customCounterInput })
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
          this.customCounterInput = value;
        });
      Button('增加')
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
            const parsed = Number(this.customCounterInput);
            if (!Number.isNaN(parsed)) {
              await this.store.addCounterEntry(this.matterId, parsed);
              this.customCounterInput = '';
              this.refreshOnly();
              this.refreshCards('已增加计数');
            }
          });
        });
    }
    .width('100%');
  }

  @Builder
  private DeadlineModule() {
    Text(this.deadlineDisplayText())
      .fontSize(TypeSize.title)
      .fontWeight(TypeWeight.semibold)
      .fontColor(this.isDeadlineUrgent() ? Colors.red : Colors.ink)
      .fontFeature(TABULAR_NUMS)
      .width('100%');
  }

  @Builder
  private NoteModule() {
    Text(this.noteInput.length > 0 ? this.noteInput : '暂无备注')
      .fontSize(TypeSize.body)
      .fontWeight(TypeWeight.regular)
      .fontColor(this.noteInput.length > 0 ? Colors.ink : Colors.inkMuted)
      .width('100%');
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
