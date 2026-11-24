let summaryCardStorage = new LocalStorage();

function resolveSummaryClusterDot(raw: string): Resource | undefined {
  const normalized = raw.trim().toUpperCase();
  if (normalized.length === 0 || normalized === '#D8DEE8') {
    return undefined;
  }
  if (normalized === 'CLUSTER.PINE' || normalized === '#2F7BFF' || normalized === '#2E6E62' || normalized === '#8BBFAF') {
    return $r('app.color.cluster_pine');
  }
  if (normalized === 'CLUSTER.WISTERIA' || normalized === '#00A88B' || normalized === '#6A5C8C' || normalized === '#B3A2D4') {
    return $r('app.color.cluster_wisteria');
  }
  if (normalized === 'CLUSTER.KERRIA' || normalized === '#FF8A3D' || normalized === '#B9822C' || normalized === '#DDB26A') {
    return $r('app.color.cluster_kerria');
  }
  if (normalized === 'CLUSTER.INDIGO' || normalized === '#9B6CFF' || normalized === '#3B5F86' || normalized === '#93AFCF') {
    return $r('app.color.cluster_indigo');
  }
  if (normalized === 'CLUSTER.INK' || normalized === '#E5486D' || normalized === '#23211C' || normalized === '#EFE9DC') {
    return $r('app.color.cluster_ink');
  }
  return $r('app.color.cluster_pine');
}

@Entry(summaryCardStorage)
@Component
struct SummaryCard {
  @LocalStorageProp('summaryTitle') title: string = '事项汇总';
  @LocalStorageProp('summaryPrimary') primary: string = '打开 App 查看';
  @LocalStorageProp('row1Title') row1Title: string = '未设置';
  @LocalStorageProp('row1Primary') row1Primary: string = '打开 App 管理';
  @LocalStorageProp('row1Color') row1Color: string = '';
  @LocalStorageProp('row2Title') row2Title: string = '未设置';
  @LocalStorageProp('row2Primary') row2Primary: string = '打开 App 管理';
  @LocalStorageProp('row2Color') row2Color: string = '';
  @LocalStorageProp('row3Title') row3Title: string = '未设置';
  @LocalStorageProp('row3Primary') row3Primary: string = '打开 App 管理';
  @LocalStorageProp('row3Color') row3Color: string = '';

  private readonly ABILITY_NAME: string = 'EntryAbility';

  build() {
    Column({ space: 6 }) {
      Row() {
        Text(this.title.length > 0 ? this.title : '事项汇总')
          .fontSize(14)
          .fontWeight(600)
          .fontColor($r('app.color.paper_ink'))
          .layoutWeight(1);
        Text(this.primary)
          .fontSize(12)
          .fontWeight(400)
          .fontColor($r('app.color.paper_ink_muted'))
          .fontFeature('"tnum" 1');
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Column({ space: 0 }) {
        this.RowItem(this.row1Title, this.row1Primary, this.row1Color, true);
        this.RowItem(this.row2Title, this.row2Primary, this.row2Color, false);
        this.RowItem(this.row3Title, this.row3Primary, this.row3Color, false);
      }
      .width('100%')
      .layoutWeight(1);

      Button('打开 App')
        .type(ButtonType.Normal)
        .height(34)
        .fontSize(13)
        .fontWeight(600)
        .fontColor($r('app.color.paper_ink'))
        .backgroundColor($r('app.color.paper_wash'))
        .borderRadius(4)
        .width('100%')
        .onClick(() => {
          this.openApp();
        });
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor($r('app.color.paper_card'))
    .onClick(() => {
      this.openApp();
    });
  }

  @Builder
  private RowItem(title: string, text: string, color: string, isFirst: boolean) {
    Row({ space: 8 }) {
      if (resolveSummaryClusterDot(color)) {
        Column()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(resolveSummaryClusterDot(color) ?? $r('app.color.paper_ink'));
      }
      Text(title.length > 0 ? title : '暂无事项')
        .fontSize(13)
        .fontWeight(600)
        .fontColor($r('app.color.paper_ink'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1);
      Text(text.length > 0 ? text : '打开应用')
        .fontSize(12)
        .fontWeight(400)
        .fontColor($r('app.color.paper_ink_muted'))
        .fontFeature('"tnum" 1')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      Text('›')
        .fontSize(14)
        .fontColor($r('app.color.paper_ink_muted'));
    }
    .width('100%')
    .constraintSize({ minHeight: 28 })
    .alignItems(VerticalAlign.Center)
    .border({ width: { top: isFirst ? 0 : 1 }, color: $r('app.color.paper_hairline') });
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
