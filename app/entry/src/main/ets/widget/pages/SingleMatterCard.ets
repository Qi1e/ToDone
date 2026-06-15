@Entry
@Component
struct SingleMatterCard {
  @LocalStorageProp('title') title: string = 'ToDone';
  @LocalStorageProp('primary') primary: string = '今日 0 次';

  build() {
    Column({ space: 10 }) {
      Row() {
        Column()
          .width(6)
          .height(44)
          .backgroundColor('#2F7BFF')
          .borderRadius(3);
        Column({ space: 4 }) {
          Text(this.title)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#101828')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.primary)
            .fontSize(14)
            .fontColor('#667085');
        }
        .margin({ left: 10 })
        .layoutWeight(1);
      }

      Button('记录')
        .height(34)
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor('#2F7BFF')
        .borderRadius(10)
        .width('100%');
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor('#FFFFFF');
  }
}

