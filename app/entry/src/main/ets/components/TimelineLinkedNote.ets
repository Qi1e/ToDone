import { common } from '@kit.AbilityKit';
import { openTimelineUrl } from '../application/TimelineAttachmentFiles';
import { Colors, TypeSize, TypeWeight } from '../common/Theme';
import { TimelineNotePart, timelineNoteParts } from '../domain/TimelineNoteLinks';

@Component
export struct TimelineLinkedNote {
  @Prop value: string = '';
  onEdit?: () => void;

  private async open(href: string): Promise<void> {
    try {
      await openTimelineUrl(getContext(this) as common.UIAbilityContext, href);
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: '无法打开网址，请检查浏览器' });
    }
  }

  build() {
    Text() {
      ForEach(timelineNoteParts(this.value), (part: TimelineNotePart) => {
        if (part.href !== undefined) {
          Span(part.text).fontColor(Colors.ink).fontWeight(TypeWeight.semibold)
            .decoration({ type: TextDecorationType.Underline })
            .onClick(() => { if (part.href) this.open(part.href); })
        } else if (this.onEdit) {
          Span(part.text).onClick(() => { this.onEdit?.(); })
        } else {
          Span(part.text)
        }
      }, (part: TimelineNotePart) => part.start.toString() + ':' + part.text)
    }.width('100%').fontSize(TypeSize.body).fontColor(Colors.ink)
  }
}
