import { matterErrorMessage } from '../domain/MatterSnapshot';
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { MatterServices } from '../application/MatterServices';
import { Colors, Radius, Space } from '../common/Theme';
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
        Column({ space: Space.large }) {
          Row() {
            Button('返回')
              .fontSize(14)
              .fontColor(Colors.primary)
              .backgroundColor(Colors.primarySoft)
              .borderRadius(Radius.normal)
              .onClick(() => router.back());
            Text('卡片设置')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(Colors.text)
              .margin({ left: Space.normal });
          }
          .width('100%');

          if (this.readError) {
            Text(this.readError).fontColor(Colors.danger);
            Button('重新读取').onClick(() => this.load());
          } else {
            this.CardSettingsPanel();
            this.SingleCardPreview();
            this.SummaryCardPreview();
          }

        }
        .width('100%')
        .padding(Space.large);
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.page);
    }
    .title('卡片设置')
    .mode(NavigationMode.Stack);
  }

  @Builder
  private CardSettingsPanel() {
    Column({ space: Space.normal }) {
      Text('单事项卡片显示')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text)
        .width('100%');

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.matters, (matter: Matter) => {
          Button(matter.title)
            .fontSize(14)
            .fontColor(this.selectedSingleId === matter.id ? Color.White : Colors.primary)
            .backgroundColor(this.selectedSingleId === matter.id ? Colors.primary : Colors.primarySoft)
            .borderRadius(Radius.normal)
            .margin({ right: Space.small, bottom: Space.small })
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
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text)
        .width('100%');

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.matters, (matter: Matter) => {
          Button(matter.title)
            .fontSize(14)
            .fontColor(this.isSummarySelected(matter.id) ? Color.White : Colors.primary)
            .backgroundColor(this.isSummarySelected(matter.id) ? Colors.primary : Colors.primarySoft)
            .borderRadius(Radius.normal)
            .margin({ right: Space.small, bottom: Space.small })
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
        .height(42)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(Colors.primary)
        .borderRadius(Radius.normal)
        .width('100%')
        .onClick(() => {
          this.refreshDesktopCards();
        });

    }
    .padding(Space.large)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.large)
    .border({ width: 1, color: Colors.border });
  }

  @Builder
  private SingleCardPreview() {
    if (this.hasSingleMatter()) {
      Text('单事项卡片预览')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text)
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
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor(Colors.text)
      .width('100%');
    SummaryCardView({
      matters: this.summaryMatters(),
      primaryTexts: this.summaryPrimaryTexts(),
      clusterColors: this.summaryClusterColors()
    });
  }
}
