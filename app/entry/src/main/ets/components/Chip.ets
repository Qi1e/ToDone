import { Colors, Radius, TABULAR_NUMS, TypeSize, TypeWeight } from '../common/Theme';

@Component
export struct Chip {
  text: string = '';
  selected: boolean = false;

  build() {
    Text(this.text)
      .fontSize(TypeSize.meta)
      .fontWeight(this.selected ? TypeWeight.semibold : TypeWeight.regular)
      .fontColor(this.selected ? Colors.inkSoft : Colors.inkMuted)
      .fontFeature(TABULAR_NUMS)
      .padding({
        left: 8,
        right: 8,
        top: 4,
        bottom: 4
      })
      .backgroundColor(Colors.wash)
      .borderRadius(Radius.chip);
  }
}
