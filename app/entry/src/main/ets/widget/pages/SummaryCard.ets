let summaryCardStorage = new LocalStorage();

@Entry(summaryCardStorage)
@Component
struct SummaryCard {
  @LocalStorageProp('summaryTitle') title: string = '事项汇总';
  @LocalStorageProp('summaryPrimary') primary: string = '打开 App 查看';
  @LocalStorageProp('row1Title') row1Title: string = '未设置';
  @LocalStorageProp('row1Primary') row1Primary: string = '打开 App 管理';
  @LocalStorageProp('row1Color') row1Color: string = '#D8DEE8';
  @LocalStorageProp('row2Title') row2Title: string = '未设置';
  @LocalStorageProp('row2Primary') row2Primary: string = '打开 App 管理';
  @LocalStorageProp('row2Color') row2Color: string = '#D8DEE8';
  @LocalStorageProp('row3Title') row3Title: string = '未设置';
  @LocalStorageProp('row3Primary') row3Primary: string = '打开 App 管理';
  @LocalStorageProp('row3Color') row3Color: string = '#D8DEE8';

  private readonly ABILITY_NAME: string = 'EntryAbility';

  build() {
    Column({ space: 10 }) {
      Text(this.title.length > 0 ? this.title : '事项汇总')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#101828')
        .width('100%');

      this.RowItem(this.row1Title, this.row1Primary, this.row1Color);
      this.RowItem(this.row2Title, this.row2Primary, this.row2Color);
      this.RowItem(this.row3Title, this.row3Primary, this.row3Color);

      Button('打开 App')
        .height(30)
        .fontSize(13)
        .fontColor('#2F7BFF')
        .backgroundColor('#DDEBFF')
        .borderRadius(10)
        .width('100%')
        .onClick(() => {
          this.openApp();
        });

      Text(this.primary)
        .fontSize(12)
        .fontColor('#667085')
        .width('100%');
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor('#FFFFFF')
    .onClick(() => {
      this.openApp();
    });
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
        Text(title.length > 0 ? title : '暂无事项')
          .fontSize(14)
          .fontColor('#101828')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(text.length > 0 ? text : '打开应用')
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

  private openApp(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: this.ABILITY_NAME,
      params: {
        message: 'open'
      }
    });
  }
}
