@Entry
@Component
struct SummaryCard {
  @LocalStorageProp('title') title: string = '事项汇总';
  @LocalStorageProp('primary') primary: string = '打开 App 查看';

  build() {
    Column({ space: 10 }) {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#101828')
        .width('100%');

      this.RowItem('健身', '今日 0 次', '#2F7BFF');
      this.RowItem('六级考试', '剩余天数', '#9B6CFF');
      this.RowItem('书单', '1 / 3', '#00A88B');

      Text(this.primary)
        .fontSize(12)
        .fontColor('#667085')
        .width('100%');
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor('#FFFFFF');
  }

  @Builder
  private RowItem(title: string, text: string, color: string) {
    Row() {
      Column()
        .width(5)
        .height(30)
        .backgroundColor(color)
        .borderRadius(3);
      Column({ space: 2 }) {
        Text(title)
          .fontSize(14)
          .fontColor('#101828')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(text)
          .fontSize(12)
          .fontColor('#667085')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .margin({ left: 8 })
      .layoutWeight(1);
      Text('›')
        .fontSize(16)
        .fontColor('#667085');
    }
    .width('100%');
  }
}

