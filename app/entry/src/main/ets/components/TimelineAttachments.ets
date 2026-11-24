import { common } from '@kit.AbilityKit';
import { Colors, Radius, Space, TypeSize, TypeWeight } from '../common/Theme';
import { TimelineAttachment, TimelineAttachmentKind } from '../contracts/TimelineService';
import { openTimelineAttachment, TimelineAttachmentSession } from '../application/TimelineAttachmentFiles';

function kindName(kind: TimelineAttachmentKind): string {
  if (kind === TimelineAttachmentKind.Image) return '图片';
  if (kind === TimelineAttachmentKind.Audio) return '音频';
  if (kind === TimelineAttachmentKind.Url) return '网址';
  return '文件';
}

@Component
export struct TimelineAttachmentButton {
  session: TimelineAttachmentSession = new TimelineAttachmentSession();
  onAdd: (item: TimelineAttachment) => void = () => {};
  onBusy: (busy: boolean) => void = () => {};
  @State private importing: boolean = false;
  private mounted: boolean = false;

  aboutToAppear(): void {
    this.mounted = true;
  }

  aboutToDisappear(): void {
    this.mounted = false;
    if (this.importing && this.session.isActive()) this.onBusy(false);
  }

  private current(session: TimelineAttachmentSession): boolean {
    return this.mounted && this.session === session && session.isActive();
  }

  private async pick(kind: TimelineAttachmentKind): Promise<void> {
    const session = this.session;
    if (this.importing || !this.current(session)) return;
    this.importing = true;
    this.onBusy(true);
    try {
      const item = await session.pick(getContext(this) as common.UIAbilityContext, kind);
      if (item && this.current(session)) this.onAdd(item);
    } catch (error) {
      if (this.current(session)) {
        this.getUIContext().getPromptAction().showToast({ message: kindName(kind) + '读取失败，请重新选择或检查可用空间' });
      }
    } finally {
      if (this.current(session)) {
        this.importing = false;
        this.onBusy(false);
      }
    }
  }

  @Builder
  private Choice(label: string, kind: TimelineAttachmentKind) {
    Button(label, { type: ButtonType.Normal })
      .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold).fontColor(Colors.ink)
      .backgroundColor(Color.Transparent)
      .constraintSize({ minHeight: 44 }).padding({ left: Space.sm, right: Space.sm }).borderRadius(Radius.card)
      .accessibilityText(kind === TimelineAttachmentKind.Image ? '从相册选照片' : '从文件中选择附件')
      .opacity(this.importing ? 0.4 : 1)
      .enabled(!this.importing).onClick(() => { this.pick(kind); })
  }

  build() {
    Row() {
      if (this.importing) {
        LoadingProgress().width(18).height(18).color(Colors.inkMuted).accessibilityText('正在添加附件')
      }
      this.Choice('选照片', TimelineAttachmentKind.Image)
      this.Choice('选文件', TimelineAttachmentKind.File)
    }
  }
}

@Component
export struct TimelineAttachmentList {
  @Prop items: TimelineAttachment[] = [];
  @Prop editable: boolean = false;
  onRemove: (id: string) => void = () => {};

  private async openItem(item: TimelineAttachment): Promise<void> {
    try {
      await openTimelineAttachment(getContext(this) as common.UIAbilityContext, item);
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({
        message: item.kind === TimelineAttachmentKind.Url ? '无法打开网址，请检查浏览器' : '无法打开附件，请检查文件或可用应用'
      });
    }
  }

  build() {
    Column() {
      ForEach(this.items, (item: TimelineAttachment) => {
        Row({ space: Space.xs }) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: Space.sm }) {
              Text(kindName(item.kind)).fontSize(TypeSize.meta).fontColor(Colors.inkMuted)
              Text(item.name).layoutWeight(1).fontSize(TypeSize.body)
                .fontWeight(item.kind === TimelineAttachmentKind.Url ? TypeWeight.semibold : TypeWeight.regular)
                .fontColor(Colors.ink)
                .decoration({ type: item.kind === TimelineAttachmentKind.Url ? TextDecorationType.Underline : TextDecorationType.None })
                .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.width('100%')
          }.layoutWeight(1).constraintSize({ minHeight: 44 })
          .padding({ left: Space.sm, right: Space.sm })
          .backgroundColor(Color.Transparent).borderRadius(Radius.card)
          .accessibilityText('打开' + kindName(item.kind) + '，' + item.name).onClick(() => this.openItem(item))
          if (this.editable) {
            Button('移除', { type: ButtonType.Normal }).constraintSize({ minHeight: 44 })
              .padding({ left: Space.sm, right: Space.sm })
              .fontSize(TypeSize.bodySmall).fontWeight(TypeWeight.semibold)
              .fontColor(Colors.red).backgroundColor(Color.Transparent).borderRadius(Radius.card)
              .accessibilityText('移除' + item.name).onClick(() => this.onRemove(item.id))
          }
        }.width('100%').border({ width: { top: 1 }, color: Colors.hairline })
      }, (item: TimelineAttachment) => item.id)
    }.width('100%')
  }
}
