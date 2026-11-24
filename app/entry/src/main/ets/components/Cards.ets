import {
  Colors,
  Radius,
  Space,
  TABULAR_NUMS,
  TypeSize,
  TypeWeight,
  resolveClusterColor
} from '../common/Theme';
import { Matter } from '../model/Types';

@Component
export struct SingleMatterCardView {
  matter: Matter = {
    id: '',
    title: '事项',
    createdAt: 0,
    updatedAt: 0,
    archived: false,
    orderIndex: 0,
    enabledModules: []
  };
  primaryText: string = '';
  quickActionLabel: string = '打开';
  clusterColor: string = '';

  build() {
    Column({ space: Space.md }) {
      Row({ space: Space.sm }) {
        if (resolveClusterColor(this.clusterColor)) {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(resolveClusterColor(this.clusterColor) ?? Colors.ink);
        }
        Text(this.matter.title)
          .fontSize(TypeSize.body)
          .fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Text(this.primaryText)
        .fontSize(TypeSize.figure)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.ink)
        .fontFeature(TABULAR_NUMS)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');

      Button(this.quickActionLabel)
        .type(ButtonType.Normal)
        .constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.body)
        .fontWeight(TypeWeight.semibold)
        .fontColor(Colors.ink)
        .backgroundColor(Colors.wash)
        .borderRadius(Radius.card)
        .width('100%');
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Space.lg)
    .backgroundColor(Colors.card)
    .borderRadius(Radius.card)
    .border({
      width: 1,
      color: Colors.hairline
    });
  }
}

@Component
export struct SummaryCardView {
  matters: Matter[] = [];
  primaryTexts: string[] = [];
  clusterColors: string[] = [];

  build() {
    Column({ space: 0 }) {
      Text('事项汇总')
        .fontSize(TypeSize.meta)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkMuted)
        .width('100%')
        .margin({ bottom: Space.sm });

      ForEach(this.matters.slice(0, 4), (matter: Matter, index: number) => {
        Row({ space: Space.sm }) {
          if (resolveClusterColor(this.clusterColors[index])) {
            Column()
              .width(8)
              .height(8)
              .borderRadius(4)
              .backgroundColor(resolveClusterColor(this.clusterColors[index]) ?? Colors.ink);
          }
          Text(matter.title)
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.semibold)
            .fontColor(Colors.ink)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Text(this.primaryTexts[index] ?? '')
            .fontSize(TypeSize.meta)
            .fontWeight(TypeWeight.regular)
            .fontColor(Colors.inkMuted)
            .fontFeature(TABULAR_NUMS)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text('›')
            .fontSize(16)
            .fontColor(Colors.inkMuted);
        }
        .width('100%')
        .constraintSize({ minHeight: 40 })
        .alignItems(VerticalAlign.Center)
        .border({ width: { top: index === 0 ? 0 : 1 }, color: Colors.hairline });
      }, (matter: Matter) => matter.id);
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Space.lg)
    .backgroundColor(Colors.card)
    .borderRadius(Radius.card)
    .border({
      width: 1,
      color: Colors.hairline
    });
  }
}
