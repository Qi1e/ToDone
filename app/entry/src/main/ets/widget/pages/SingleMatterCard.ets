let singleMatterCardStorage = new LocalStorage();

interface MessageParams {
  message: string;
  operationId?: string;
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

function resolveCardClusterDot(raw: string): Resource | undefined {
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

@Entry(singleMatterCardStorage)
@Component
struct SingleMatterCard {
  @LocalStorageProp('formId') formId: string = '';
  @LocalStorageProp('completedOperationId') completedOperationId: string = '';
  @LocalStorageProp('saveError') saveError: string = '';
  @State private pendingOperationId: string = '';
  @State private pendingRequest: string = '';
  @LocalStorageProp('title') title: string = '事项';
  @LocalStorageProp('primary') primary: string = '暂无记录';
  @LocalStorageProp('secondary') secondary: string = '打开 App 管理模块';
  @LocalStorageProp('quickActionLabel') quickActionLabel: string = '打开';
  @LocalStorageProp('quickActionType') quickActionType: string = 'open';
  @LocalStorageProp('matterId') matterId: string = '';
  @LocalStorageProp('clusterColor') clusterColor: string = '';

  private readonly ABILITY_NAME: string = 'EntryAbility';

  build() {
    Column({ space: 8 }) {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          if (resolveCardClusterDot(this.clusterColor)) {
            Column()
              .width(8)
              .height(8)
              .borderRadius(4)
              .backgroundColor(resolveCardClusterDot(this.clusterColor) ?? $r('app.color.paper_ink'));
          }
          Text(this.title.length > 0 ? this.title : 'ToDone')
            .fontSize(14)
            .fontWeight(600)
            .fontColor($r('app.color.paper_ink'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);

        Text(this.primary.length > 0 ? this.primary : '暂无事项')
          .fontSize(20)
          .fontWeight(600)
          .fontColor($r('app.color.paper_ink'))
          .fontFeature('"tnum" 1')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');

        Text(this.saveError || (this.secondary.length > 0 ? this.secondary : '打开应用'))
          .fontSize(12)
          .fontWeight(this.saveError ? 600 : 400)
          .fontColor(this.saveError ? $r('app.color.accent_red') : $r('app.color.paper_ink_muted'))
          .fontFeature('"tnum" 1')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => {
        this.openApp();
      });

      Row({ space: 8 }) {
        Button('打开')
          .type(ButtonType.Normal)
          .height(36)
          .fontSize(13)
          .fontWeight(600)
          .fontColor($r('app.color.paper_ink_soft'))
          .backgroundColor(Color.Transparent)
          .borderRadius(4)
          .layoutWeight(1)
          .onClick(() => {
            this.openApp();
          });

        Button(this.pendingOperationId && this.pendingOperationId !== this.completedOperationId &&
          this.pendingRequest === this.matterId + ':' + this.quickActionType ? '确认保存' : this.quickActionLabel)
          .type(ButtonType.Normal)
          .height(36)
          .fontSize(13)
          .fontWeight(600)
          .fontColor($r('app.color.paper_ink'))
          .backgroundColor($r('app.color.paper_wash'))
          .borderRadius(4)
          .layoutWeight(1)
          .enabled(this.matterId.length > 0 && this.formId.length > 0)
          .opacity(this.matterId.length > 0 && this.formId.length > 0 ? 1 : 0.4)
          .onClick(() => {
            this.performQuickAction();
          });
      }
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor($r('app.color.paper_card'));
  }

  private recordOnce(): void {
    if (this.matterId.length === 0) {
      return;
    }
    const params: MessageParams = {
      message: `record:${this.matterId}`,
      operationId: this.operationId()
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
      message: `counter:${this.matterId}:${this.quickActionType.substring(8)}`,
      operationId: this.operationId()
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
    if (this.quickActionType.startsWith('counter:')) {
      this.counterOnce();
      return;
    }
    this.openApp();
  }

  private operationId(): string {
    const request = this.matterId + ':' + this.quickActionType;
    if (!this.pendingOperationId || this.pendingOperationId === this.completedOperationId || this.pendingRequest !== request) {
      this.pendingOperationId = 'form:' + this.formId + ':' + Date.now().toString(36) + ':' + Math.random().toString(36).substring(2);
      this.pendingRequest = request;
    }
    return this.pendingOperationId;
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
