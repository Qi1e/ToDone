import { Colors, Radius } from '../common/Theme';

@Component
export struct Chip {
  text: string = '';
  selected: boolean = false;

  build() {
    Text(this.text)
      .fontSize(13)
      .fontColor(this.selected ? Colors.primary : Colors.subText)
      .padding({
        left: 10,
        right: 10,
        top: 6,
        bottom: 6
      })
      .backgroundColor(this.selected ? Colors.primarySoft : Colors.surfaceSoft)
      .borderRadius(Radius.small);
  }
}

