let singleMatterCardStorage = new LocalStorage();

interface MessageParams {
  message: string;
}

interface MessageAction {
  action: string;
  params: MessageParams;
}

interface RouterAction {
  action: string;
  abilityName: string;
  params: MessageParams;
}

@Entry(singleMatterCardStorage)
@Component
struct SingleMatterCard {
  @LocalStorageProp('title') title: string = '事项';
  @LocalStorageProp('primary') primary: string = '暂无记录';
  @LocalStorageProp('secondary') secondary: string = '打开 App 管理模块';
  @LocalStorageProp('quickActionLabel') quickActionLabel: string = '打开';
  @LocalStorageProp('quickActionType') quickActionType: string = 'open';
  @LocalStorageProp('matterId') matterId: string = '';
  @LocalStorageProp('clusterColor') clusterColor: string = '#2F7BFF';

  private readonly ABILITY_NAME: string = 'EntryAbility';

  build() {
    Column({ space: 10 }) {
      Row() {
        Column()
          .width(6)
          .height(50)
          .backgroundColor(this.clusterColor)
          .borderRadius(3);
        Column({ space: 4 }) {
          Text(this.title.length > 0 ? this.title : 'ToDone')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#101828')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.primary.length > 0 ? this.primary : '暂无事项')
            .fontSize(14)
            .fontColor('#2F7BFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.secondary.length > 0 ? this.secondary : '打开应用')
            .fontSize(11)
            .fontColor('#667085')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .margin({ left: 10 })
        .layoutWeight(1);
      }
      .width('100%')
      .onClick(() => {
        this.openApp();
      });

      Row({ space: 8 }) {
        Button('打开')
          .height(34)
          .fontSize(14)
          .fontColor('#2F7BFF')
          .backgroundColor('#DDEBFF')
          .borderRadius(10)
          .layoutWeight(1)
          .onClick(() => {
            this.openApp();
          });

        Button(this.quickActionLabel)
          .height(34)
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor('#2F7BFF')
          .borderRadius(10)
          .layoutWeight(1)
          .enabled(this.matterId.length > 0)
          .onClick(() => {
            this.performQuickAction();
          });
      }
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor('#FFFFFF');
  }

  private recordOnce(): void {
    if (this.matterId.length === 0) {
      return;
    }
    const params: MessageParams = {
      message: `record:${this.matterId}`
    };
    const action: MessageAction = {
      action: 'message',
      params
    };
    postCardAction(this, action);
  }

  private counterOnce(): void {
    if (this.matterId.length === 0) {
      return;
    }
    const params: MessageParams = {
      message: `counter:${this.matterId}:1`
    };
    const action: MessageAction = {
      action: 'message',
      params
    };
    postCardAction(this, action);
  }

  private performQuickAction(): void {
    if (this.quickActionType === 'record') {
      this.recordOnce();
      return;
    }
    if (this.quickActionType === 'counter:1') {
      this.counterOnce();
      return;
    }
    this.openApp();
  }

  private openApp(): void {
    const params: MessageParams = {
      message: 'open'
    };
    const action: RouterAction = {
      action: 'router',
      abilityName: this.ABILITY_NAME,
      params
    };
    postCardAction(this, action);
  }
}
