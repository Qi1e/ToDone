import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { Colors, Radius, Space } from '../common/Theme';
import { SingleMatterCardView, SummaryCardView } from '../components/Cards';
import { Matter } from '../model/Types';
import { MatterStore } from '../store/MatterStore';

@Entry
@Component
struct WidgetPreview {
  private store: MatterStore = MatterStore.getInstance();
  @State matters: Matter[] = [];

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.store.init(context);
    this.matters = this.store.activeMatters();
  }

  private primaryTexts(): string[] {
    return this.matters.map((matter: Matter) => this.store.cardPrimaryText(matter));
  }

  private clusterColors(): string[] {
    return this.matters.map((matter: Matter) => this.store.clusterColor(matter.clusterId));
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
            Text('卡片预览')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(Colors.text)
              .margin({ left: Space.normal });
          }
          .width('100%');

          if (this.matters.length > 0) {
            Text('单事项卡片')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(Colors.text)
              .width('100%');
            SingleMatterCardView({
              matter: this.matters[0],
              primaryText: this.store.cardPrimaryText(this.matters[0]),
              clusterColor: this.store.clusterColor(this.matters[0].clusterId)
            });
          }

          Text('汇总卡片')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.text)
            .width('100%');
          SummaryCardView({
            matters: this.matters,
            primaryTexts: this.primaryTexts(),
            clusterColors: this.clusterColors()
          });

          Text('桌面服务卡片用于快速查看和高频记录。完整编辑仍在 App 内完成。')
            .fontSize(14)
            .fontColor(Colors.subText)
            .lineHeight(22);
        }
        .width('100%')
        .padding(Space.large);
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.page);
    }
    .title('卡片预览')
    .mode(NavigationMode.Stack);
  }
}
