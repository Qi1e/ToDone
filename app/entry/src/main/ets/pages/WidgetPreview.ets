import { matterErrorMessage } from '../domain/MatterSnapshot';
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { MatterServices } from '../application/MatterServices';
import { Colors, Radius, Space, TypeSize, TypeWeight } from '../common/Theme';
import { SingleMatterCardView, SummaryCardView } from '../components/Cards';
import { Matter } from '../model/Types';
import { MatterStore } from '../store/MatterStore';

@Entry
@Component
struct WidgetPreview {
  @State private savingMatter: boolean = false;
  private store: MatterStore = MatterStore.getInstance();
  @State matters: Matter[] = [];
  @State selectedSingleId: string = '';
  @State selectedSummaryIds: string[] = [];
  @State private readError: string = '';
  private unsubscribe?: () => void;

  aboutToAppear(): void {
    this.unsubscribe = this.store.subscribe(() => this.loadState());
    this.load();
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
  }

  private async load(): Promise<void> {
    try {
      await this.store.init(getContext(this) as common.UIAbilityContext);
      this.readError = '';
      this.loadState();
      MatterServices.requestCardRefresh();
    } catch (error) {
      this.readError = matterErrorMessage(error as Error);
    }
  }

  private loadState(): void {
    this.matters = this.store.activeMatters();
    this.selectedSingleId = this.store.selectedSingleCardMatterId();
    this.selectedSummaryIds = this.store.selectedSummaryCardMatterIds();
  }

  private singleMatter(): Matter | undefined {
    return this.matters.find((matter: Matter) => matter.id === this.selectedSingleId);
  }

  private singleMatterForPreview(): Matter {
    const matter = this.singleMatter();
    if (matter) {
      return matter;
    }
    return {
      id: '',
      title: '事项',
      createdAt: 0,
      updatedAt: 0,
      archived: false,
      orderIndex: 0,
      enabledModules: []
    };
  }

  private hasSingleMatter(): boolean {
    return this.singleMatter() !== undefined;
  }

  private summaryMatters(): Matter[] {
    return this.selectedSummaryIds
      .map((id: string) => this.matters.find((matter: Matter) => matter.id === id))
      .filter((matter: Matter | undefined) => matter !== undefined) as Matter[];
  }

  private summaryPrimaryTexts(): string[] {
    return this.summaryMatters().map((matter: Matter) => this.store.cardPrimaryText(matter));
  }

  private summaryClusterColors(): string[] {
    return this.summaryMatters().map((matter: Matter) => this.store.clusterColor(matter.clusterId));
  }

  private isSummarySelected(id: string): boolean {
    return this.selectedSummaryIds.includes(id);
  }

  private refreshDesktopCards(action?: string): void {
    const result = MatterServices.requestCardRefresh(action);
    this.getUIContext().getPromptAction().showToast({ message: result.message, duration: 1500 });
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
                .onClick(() => router.back());
            }
            .width('100%');

            Text('卡片设置')
              .fontSize(TypeSize.display)
              .fontWeight(TypeWeight.semibold)
              .fontColor(Colors.ink)
              .width('100%');
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);

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
          } else {
            this.CardSettingsPanel();
            this.SingleCardPreview();
            this.SummaryCardPreview();
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
  private CardSettingsPanel() {
    Column({ space: Space.md }) {
      Text('单事项卡片显示')
        .fontSize(TypeSize.title)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.ink)
        .width('100%');

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.matters, (matter: Matter) => {
          Button(matter.title)
            .type(ButtonType.Normal)
            .constraintSize({ minHeight: 40 })
            .fontSize(TypeSize.body)
            .fontWeight(this.selectedSingleId === matter.id ? TypeWeight.semibold : TypeWeight.regular)
            .fontColor(this.selectedSingleId === matter.id ? Colors.bg : Colors.inkSoft)
            .backgroundColor(this.selectedSingleId === matter.id ? Colors.ink : Colors.wash)
            .borderRadius(Radius.card)
            .padding({ left: Space.md, right: Space.md })
            .margin({ right: Space.sm, bottom: Space.sm })
            .onClick(() => {
              this.perform(async (): Promise<void> => {
                await this.store.setSingleCardMatter(matter.id);
                this.loadState();
                this.refreshDesktopCards('已更新单事项卡片选择');
              });
            });
        }, (matter: Matter) => matter.id);
      }

      Text('汇总卡片显示，最多 3 个事项')
        .fontSize(TypeSize.title)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.ink)
        .width('100%')
        .padding({ top: Space.sm })
        .border({ width: { top: 1 }, color: Colors.hairline });

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.matters, (matter: Matter) => {
          Button(matter.title)
            .type(ButtonType.Normal)
            .constraintSize({ minHeight: 40 })
            .fontSize(TypeSize.body)
            .fontWeight(this.isSummarySelected(matter.id) ? TypeWeight.semibold : TypeWeight.regular)
            .fontColor(this.isSummarySelected(matter.id) ? Colors.bg : Colors.inkSoft)
            .backgroundColor(this.isSummarySelected(matter.id) ? Colors.ink : Colors.wash)
            .borderRadius(Radius.card)
            .padding({ left: Space.md, right: Space.md })
            .margin({ right: Space.sm, bottom: Space.sm })
            .onClick(() => {
              this.perform(async (): Promise<void> => {
                await this.store.toggleSummaryCardMatter(matter.id);
                this.loadState();
                this.refreshDesktopCards('已更新汇总卡片选择');
              });
            });
        }, (matter: Matter) => matter.id);
      }

      Button('刷新桌面卡片')
        .type(ButtonType.Normal)
        .constraintSize({ minHeight: 44 })
        .fontSize(TypeSize.body)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.onRed)
        .backgroundColor(Colors.red)
        .borderRadius(Radius.card)
        .width('100%')
        .onClick(() => {
          this.refreshDesktopCards();
        });
    }
    .width('100%')
    .padding(Space.lg)
    .backgroundColor(Colors.card)
    .borderRadius(Radius.card)
    .border({ width: 1, color: Colors.hairline });
  }

  @Builder
  private SingleCardPreview() {
    if (this.hasSingleMatter()) {
      Text('单事项卡片预览')
        .fontSize(TypeSize.title)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.ink)
        .width('100%');
      SingleMatterCardView({
        matter: this.singleMatterForPreview(),
        primaryText: this.store.cardPrimaryText(this.singleMatterForPreview()),
        quickActionLabel: this.store.cardQuickActionLabel(this.singleMatterForPreview()),
        clusterColor: this.store.clusterColor(this.singleMatterForPreview().clusterId)
      });
    }
  }

  @Builder
  private SummaryCardPreview() {
    Text('汇总卡片预览')
      .fontSize(TypeSize.title)
      .fontWeight(TypeWeight.semibold)
      .fontColor(Colors.ink)
      .width('100%');
    SummaryCardView({
      matters: this.summaryMatters(),
      primaryTexts: this.summaryPrimaryTexts(),
      clusterColors: this.summaryClusterColors()
    });
  }
}
