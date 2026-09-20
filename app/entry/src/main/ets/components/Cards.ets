import { Colors, Radius, Space } from '../common/Theme';
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
  clusterColor: string = '#D8DEE8';

  build() {
    Column({ space: Space.normal }) {
      Row() {
        Column()
          .width(6)
          .height(48)
          .backgroundColor(this.clusterColor)
          .borderRadius(3);
        Column({ space: Space.small }) {
          Text(this.matter.title)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.primaryText)
            .fontSize(15)
            .fontColor(Colors.subText);
        }
        .margin({ left: Space.normal })
        .layoutWeight(1);
      }

      Button(this.quickActionLabel)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(Colors.primary)
        .borderRadius(Radius.normal)
        .width('100%');
    }
    .padding(Space.large)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.large)
    .border({
      width: 1,
      color: Colors.border
    });
  }
}

@Component
export struct SummaryCardView {
  matters: Matter[] = [];
  primaryTexts: string[] = [];
  clusterColors: string[] = [];

  build() {
    Column({ space: Space.normal }) {
      Text('事项汇总')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.text);

      ForEach(this.matters.slice(0, 4), (matter: Matter, index: number) => {
        Row() {
          Column()
            .width(5)
            .height(34)
            .backgroundColor(this.clusterColors[index] ?? '#D8DEE8')
            .borderRadius(3);
          Column({ space: 2 }) {
            Text(matter.title)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Colors.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(this.primaryTexts[index] ?? '')
              .fontSize(12)
              .fontColor(Colors.subText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .margin({ left: Space.small })
          .layoutWeight(1);
          Text('›')
            .fontSize(18)
            .fontColor(Colors.subText);
        }
      }, (matter: Matter) => matter.id);
    }
    .padding(Space.large)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.large)
    .border({
      width: 1,
      color: Colors.border
    });
  }
}
