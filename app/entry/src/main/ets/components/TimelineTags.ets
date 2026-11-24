import { Colors, Radius, Space, TABULAR_NUMS, TypeSize, TypeWeight } from '../common/Theme';
import { TimelineTag } from '../contracts/TimelineService';
import { createId, stripTagEmoji } from '../model/Defaults';

interface TagSwatch {
  name: string;
  color: string;
}

const TAG_PALETTE: TagSwatch[] = [
  { name: '松花绿', color: '#2E6E62' }, { name: '藤紫', color: '#6A5C8C' },
  { name: '山吹黄', color: '#B9822C' }, { name: '黛蓝', color: '#3B5F86' },
  { name: '墨', color: '#23211C' }, { name: '赭石', color: '#8C583A' }
];

interface TagHsv {
  hue: number;
  saturation: number;
  value: number;
}

const COLOR_FIELD_HEIGHT: number = 126;

function tagHsv(hex: string, previousHue: number): TagHsv {
  const r = parseInt(hex.slice(1, 3), 16) / 255;
  const g = parseInt(hex.slice(3, 5), 16) / 255;
  const b = parseInt(hex.slice(5, 7), 16) / 255;
  const high = Math.max(r, g, b);
  const diff = high - Math.min(r, g, b);
  let hue = previousHue;
  if (diff > 0) {
    const sector = high === r ? (g - b) / diff : high === g ? 2 + (b - r) / diff : 4 + (r - g) / diff;
    hue = (sector * 60 + 360) % 360;
  }
  return { hue: hue, saturation: high === 0 ? 0 : diff / high, value: high };
}

function tagHex(hue: number, saturation: number, value: number): string {
  // HSV 各通道的三角波分别在色相环上相差 120°。
  const channel = (offset: number): string => {
    const k = (offset + hue / 60) % 6;
    const intensity = value * (1 - saturation * Math.max(0, Math.min(k, 4 - k, 1)));
    return Math.round(255 * intensity).toString(16).padStart(2, '0');
  };
  return ('#' + channel(5) + channel(3) + channel(1)).toUpperCase();
}

function normalizedTagHex(input: string): string {
  const value = input.trim();
  if (!/^#?[0-9a-fA-F]{6}$/.test(value)) return '';
  return '#' + value.replace(/^#/, '').toUpperCase();
}

@Component
export struct TimelineTagPicker {
  @Prop tags: TimelineTag[] = [];
  @Prop selectedId: string = '';
  onSelect: (id: string) => void = () => {};
  onCreate: () => void = () => {};
  onOpen: () => void = () => {};
  @State private menuVisible: boolean = false;

  private frequent(): TimelineTag[] {
    const shown = this.tags.slice(0, 3);
    const selected = this.tags.find((tag: TimelineTag) => tag.id === this.selectedId);
    if (selected && !shown.some((tag: TimelineTag) => tag.id === selected.id)) {
      shown[2] = selected;
    }
    return shown;
  }

  private choose(tag: TimelineTag): void {
    this.menuVisible = false;
    this.onSelect(this.selectedId === tag.id ? '' : tag.id);
  }

  @Builder
  private MenuContent() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.tags, (tag: TimelineTag) => {
            Button({ type: ButtonType.Normal }) {
              Row({ space: Space.md }) {
                Row().width(8).height(8).borderRadius(4).backgroundColor(tag.color)
                Text(tag.name).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontSize(TypeSize.body)
                  .fontWeight(tag.id === this.selectedId ? TypeWeight.semibold : TypeWeight.regular)
                  .fontColor(Colors.ink)
                if (tag.id === this.selectedId) {
                  Text('✓').fontSize(TypeSize.body).fontWeight(TypeWeight.semibold).fontColor(Colors.ink)
                }
              }.width('100%')
            }.width('100%').height(44).padding({ left: Space.md, right: Space.md })
            .backgroundColor(tag.id === this.selectedId ? Colors.wash : Color.Transparent)
            .borderRadius(Radius.card)
            .accessibilityText(tag.name + (this.selectedId === tag.id ? '，已选中' : ''))
            .onClick(() => this.choose(tag))
          }, (tag: TimelineTag) => tag.id)
        }.width('100%')
      }.width('100%').constraintSize({ maxHeight: 220 })
      Divider().color(Colors.hairline)
      Button({ type: ButtonType.Normal }) {
        Text('新建标签').width('100%').fontSize(TypeSize.body).fontWeight(TypeWeight.semibold).fontColor(Colors.ink)
      }.width('100%').height(44).padding({ left: Space.md, right: Space.md })
      .backgroundColor(Color.Transparent).borderRadius(Radius.card)
      .onClick(() => {
        this.menuVisible = false;
        this.onCreate();
      })
    }.width(210).padding(Space.xs)
  }

  build() {
    Row({ space: Space.sm }) {
      Text('标签').fontSize(TypeSize.body).fontColor(Colors.inkSoft)
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        ForEach(this.frequent(), (tag: TimelineTag) => {
          Button({ type: ButtonType.Normal }) {
            Row({ space: Space.xs }) {
              Row().width(8).height(8).borderRadius(4).backgroundColor(tag.color)
              Text((tag.id === this.selectedId ? '✓ ' : '') + tag.name)
                .fontSize(TypeSize.bodySmall)
                .fontWeight(tag.id === this.selectedId ? TypeWeight.semibold : TypeWeight.regular)
                .fontColor(tag.id === this.selectedId ? Colors.ink : Colors.inkSoft)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.alignItems(VerticalAlign.Center)
          }
          .constraintSize({ minHeight: 34, maxWidth: 124 })
          .padding({ left: Space.sm, right: Space.sm })
          .margin({ right: Space.xs, top: Space.xs, bottom: Space.xs })
          .borderRadius(Radius.chip)
          .backgroundColor(tag.id === this.selectedId ? Colors.wash : Color.Transparent)
          .accessibilityText(tag.name + (tag.id === this.selectedId ? '，已选中' : ''))
          .onClick(() => this.choose(tag))
        }, (tag: TimelineTag) => tag.id)
      }.layoutWeight(1)
      Button({ type: ButtonType.Normal }) {
        Stack({ alignContent: Alignment.Center }) {
          Row().width(14).height(1.5).borderRadius(1).backgroundColor(Colors.inkSoft)
          Row().width(1.5).height(14).borderRadius(1).backgroundColor(Colors.inkSoft)
        }.width(20).height(20)
      }
      .width(40).height(40).padding(0).backgroundColor(Color.Transparent).borderRadius(Radius.card)
      .accessibilityText('查看全部标签或新建标签')
      .onClick(() => {
        this.onOpen();
        this.menuVisible = !this.menuVisible;
      })
      .bindPopup(this.menuVisible, {
        builder: this.MenuContent, placement: Placement.Bottom, enableArrow: false,
        popupColor: Colors.card, autoCancel: true,
        onStateChange: (event) => { if (!event.isVisible) this.menuVisible = false; }
      })
    }.width('100%')
  }
}

@Component
export struct TimelineTagForm {
  @Prop tags: TimelineTag[] = [];
  onSaveTag: (tag: TimelineTag) => Promise<void> = (tag: TimelineTag) => Promise.reject(new Error('标签存储未就绪'));
  onDone: (id: string) => void = () => {};
  onCancel: () => void = () => {};
  @State private nameDraft: string = '';
  @State private colorDraft: string = TAG_PALETTE[0].color;
  @State private paletteOpen: boolean = false;
  @State private hsv: TagHsv = tagHsv(TAG_PALETTE[0].color, 0);
  @State private hexDraft: string = TAG_PALETTE[0].color;
  @State private fieldWidth: number = 0;
  @State private focused: boolean = false;
  @State private saving: boolean = false;
  @State private errorMessage: string = '';
  private tagId: string = createId('tag');
  private nameController: TextInputController = new TextInputController();
  private hexController: TextInputController = new TextInputController();

  private selectHex(color: string): void {
    this.colorDraft = color;
    this.hexDraft = color;
    this.hsv = tagHsv(color, this.hsv.hue);
    this.errorMessage = '';
  }

  private setChannels(hue: number, saturation: number, value: number): void {
    this.hsv = { hue: hue, saturation: saturation, value: value };
    this.colorDraft = tagHex(hue, saturation, value);
    this.hexDraft = this.colorDraft;
    this.errorMessage = '';
  }

  private pickInField(event: GestureEvent): void {
    const finger = event.fingerList[0];
    if (!finger || this.fieldWidth <= 0) return;
    const saturation = Math.max(0, Math.min(1, finger.localX / this.fieldWidth));
    const value = 1 - Math.max(0, Math.min(1, finger.localY / COLOR_FIELD_HEIGHT));
    this.setChannels(this.hsv.hue, saturation, value);
  }

  private togglePalette(): void {
    this.nameController.stopEditing();
    if (this.paletteOpen) {
      this.hexController.stopEditing();
      this.hexDraft = this.colorDraft;
      this.errorMessage = '';
    }
    this.paletteOpen = !this.paletteOpen;
  }

  aboutToAppear(): void {
    while (this.tags.some((tag: TimelineTag) => tag.id === this.tagId)) {
      this.tagId = createId('tag');
    }
  }

  private async submit(): Promise<void> {
    if (this.saving) return;
    const rawTrimmed = this.nameDraft.trim();
    const name = stripTagEmoji(rawTrimmed);
    if (rawTrimmed.length === 0) {
      this.errorMessage = '请输入标签名称';
      return;
    }
    if (name.length === 0) {
      this.errorMessage = '标签仅支持文字分类，请勿使用表情符号';
      return;
    }
    if (this.tags.some((tag: TimelineTag) => stripTagEmoji(tag.name) === name && tag.id !== this.tagId)) {
      this.errorMessage = '这个标签名已存在';
      return;
    }
    if (this.paletteOpen && normalizedTagHex(this.hexDraft).length === 0) {
      this.errorMessage = '请输入六位颜色值，如 #2E6E62';
      return;
    }
    this.errorMessage = '';
    this.saving = true;
    try {
      await this.onSaveTag({ id: this.tagId, name: name, color: this.colorDraft });
    } catch (error) {
      this.errorMessage = '标签保存失败，可重新保存';
      this.saving = false;
      return;
    }
    this.saving = false;
    this.onDone(this.tagId);
  }

  @Builder
  private CustomPalette() {
    Column({ space: Space.xs }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Row().width('100%').height('100%')
          .linearGradient({ direction: GradientDirection.Right, colors: [['#FFFFFF', 0], [tagHex(this.hsv.hue, 1, 1), 1]] })
        Row().width('100%').height('100%')
          .linearGradient({ direction: GradientDirection.Bottom, colors: [['#00000000', 0], ['#FF000000', 1]] })
        Row().width(18).height(18).borderRadius(9)
          .border({ color: Colors.card, width: 2 }).backgroundColor(this.colorDraft)
          .position({ x: Math.max(0, Math.min(this.fieldWidth - 18, this.hsv.saturation * this.fieldWidth - 9)),
            y: Math.max(0, Math.min(COLOR_FIELD_HEIGHT - 18, (1 - this.hsv.value) * COLOR_FIELD_HEIGHT - 9)) })
      }.width('100%').height(COLOR_FIELD_HEIGHT).borderRadius(Radius.card).clip(true)
      .border({ width: 1, color: Colors.hairline })
      .accessibilityText('调整颜色饱和度与明暗，也可在下方输入颜色值')
      .onAreaChange((_old: Area, area: Area) => { this.fieldWidth = Number(area.width); })
      .priorityGesture(GestureGroup(GestureMode.Exclusive,
        PanGesture({ direction: PanDirection.All, distance: 2 })
          .onActionStart((event: GestureEvent) => this.pickInField(event))
          .onActionUpdate((event: GestureEvent) => this.pickInField(event)),
        TapGesture().onAction((event: GestureEvent) => this.pickInField(event))))

      Stack({ alignContent: Alignment.Center }) {
        Row().height(10).borderRadius(Radius.chip).width('100%')
          .linearGradient({ direction: GradientDirection.Right, colors: [
            ['#FF0000', 0], ['#FFFF00', 1 / 6], ['#00FF00', 2 / 6], ['#00FFFF', 3 / 6],
            ['#0000FF', 4 / 6], ['#FF00FF', 5 / 6], ['#FF0000', 1]] })
        Slider({ value: this.hsv.hue, min: 0, max: 360, step: 1 })
          .width('100%').height(40).trackColor(Color.Transparent).selectedColor(Color.Transparent)
          .blockColor(tagHex(this.hsv.hue, 1, 1)).blockBorderColor(Colors.card).blockBorderWidth(2)
          .accessibilityText('色相')
          .onChange((value: number) => this.setChannels(value, this.hsv.saturation, this.hsv.value))
      }.width('100%').height(40)
      Row({ space: Space.sm }) {
        Text('颜色值').fontSize(TypeSize.body).fontColor(Colors.inkSoft)
        TextInput({ text: this.hexDraft, controller: this.hexController })
          .width(120).height(40).padding({ left: Space.sm, right: Space.sm })
          .backgroundColor(Colors.wash).borderRadius(Radius.card)
          .fontColor(Colors.ink).caretColor(Colors.red).fontSize(TypeSize.body)
          .accessibilityText('六位十六进制颜色值')
          .onChange((input: string) => {
            this.hexDraft = input;
            this.errorMessage = '';
            const color = normalizedTagHex(input);
            if (color.length > 0) {
              this.colorDraft = color;
              this.hsv = tagHsv(color, this.hsv.hue);
            }
          })
      }.width('100%')
    }.width('100%')
  }

  build() {
    Column() {
      Row() {
        Button('返回', { type: ButtonType.Normal }).constraintSize({ minHeight: 40 })
          .fontSize(TypeSize.body).fontColor(Colors.inkSoft).backgroundColor(Color.Transparent)
          .borderRadius(Radius.card).padding({ left: Space.sm, right: Space.sm })
          .onClick(() => this.onCancel())
        Blank()
        Text('新建标签').fontSize(TypeSize.title).fontWeight(TypeWeight.semibold).fontColor(Colors.ink)
        Blank()
        Button(this.saving ? '保存中' : '保存', { type: ButtonType.Normal }).constraintSize({ minHeight: 40 })
          .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold)
          .backgroundColor(Colors.red).fontColor(Colors.onRed).borderRadius(Radius.card)
          .padding({ left: Space.lg, right: Space.lg })
          .opacity(this.saving ? 0.4 : 1)
          .onClick(() => { this.submit(); })
      }.width('100%').padding({ left: Space.md, right: Space.page, top: Space.sm, bottom: Space.sm })
      Scroll() {
        Column({ space: Space.md }) {
          Text('标签名称').fontSize(TypeSize.bodySmall).fontColor(Colors.inkSoft)
          TextInput({ text: this.nameDraft, placeholder: this.focused ? '' : '例如 答辩', controller: this.nameController })
            .accessibilityText('标签名称').width('100%').constraintSize({ minHeight: 48 })
            .padding({ left: Space.md, right: Space.md }).fontSize(TypeSize.heading).fontWeight(TypeWeight.semibold)
            .backgroundColor(Colors.wash).borderRadius(Radius.card)
            .fontColor(Colors.ink).placeholderColor(Colors.inkMuted).caretColor(Colors.red)
            .onFocus(() => { this.focused = true; }).onBlur(() => { this.focused = false; })
            .onChange((value: string) => { this.nameDraft = value; this.errorMessage = ''; })
          Divider().color(Colors.hairline)
          Row() {
            Text('颜色').layoutWeight(1).fontSize(TypeSize.body).fontColor(Colors.inkSoft)
            Button({ type: ButtonType.Normal }) {
              Row({ space: Space.sm }) {
                Row().width(14).height(14).borderRadius(7).backgroundColor(this.colorDraft)
                  .border({ width: 1, color: Colors.hairline })
                Text('自定义颜色').fontSize(TypeSize.body).fontColor(Colors.ink)
                Text(this.paletteOpen ? '▴' : '▾').fontSize(TypeSize.meta).fontColor(Colors.inkMuted)
              }
            }.height(40).padding({ left: Space.sm, right: Space.sm }).backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .accessibilityText('自定义颜色，当前 ' + this.colorDraft + (this.paletteOpen ? '，已展开' : ''))
            .onClick(() => this.togglePalette())
          }.width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(TAG_PALETTE, (swatch: TagSwatch) => {
              Button({ type: ButtonType.Normal }) {
                Stack({ alignContent: Alignment.Center }) {
                  Row().width(24).height(24).borderRadius(12).backgroundColor(swatch.color)
                }.width(34).height(34).borderRadius(17)
                .border({ width: this.colorDraft === swatch.color ? 2 : 0, color: Colors.ink })
              }.width(44).height(44).padding(0).backgroundColor(Color.Transparent).borderRadius(Radius.card)
              .accessibilityText(swatch.name + (this.colorDraft === swatch.color ? '，已选中' : ''))
              .onClick(() => this.selectHex(swatch.color))
            }, (swatch: TagSwatch) => swatch.color)
          }.width('100%')
          if (this.paletteOpen) {
            this.CustomPalette()
          }
          if (this.errorMessage.length > 0) {
            Text(this.errorMessage).fontSize(TypeSize.meta).fontWeight(TypeWeight.semibold).fontColor(Colors.red)
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding(Space.page)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }.width('100%').height('100%').enabled(!this.saving).backgroundColor(Colors.card)
  }
}
