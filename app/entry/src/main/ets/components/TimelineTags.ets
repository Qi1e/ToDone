import { Colors, Radius, Space } from '../common/Theme';
import { TimelineTag } from '../contracts/TimelineService';
import { createId } from '../model/Defaults';

interface TagSwatch {
  name: string;
  color: string;
}

const TAG_PALETTE: TagSwatch[] = [
  { name: '蓝色', color: '#4384BB' }, { name: '紫色', color: '#9A7BC7' },
  { name: '绿色', color: '#60AC87' }, { name: '黄色', color: '#E0BD3D' },
  { name: '橙色', color: '#DD9A54' }, { name: '红色', color: '#DD6664' }
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
              Row({ space: Space.normal }) {
                Row().width(12).height(12).borderRadius(6).backgroundColor(tag.color)
                Text(tag.name).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontSize(15).fontColor(Colors.text)
                if (tag.id === this.selectedId) {
                  Text('✓').fontSize(15).fontColor(Colors.text)
                }
              }.width('100%')
            }.width('100%').height(44).padding({ left: Space.normal, right: Space.normal })
            .backgroundColor(Color.Transparent).borderRadius(Radius.small)
            .accessibilityText(tag.name + (this.selectedId === tag.id ? '，已选中' : ''))
            .onClick(() => this.choose(tag))
          }, (tag: TimelineTag) => tag.id)
        }.width('100%')
      }.width('100%').constraintSize({ maxHeight: 220 })
      Divider().color(Colors.border)
      Button({ type: ButtonType.Normal }) {
        Text('新建标签').width('100%').fontSize(15).fontColor(Colors.text)
      }.width('100%').height(44).padding({ left: Space.normal, right: Space.normal })
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.menuVisible = false;
        this.onCreate();
      })
    }.width(210).padding(Space.tiny)
  }

  build() {
    Row({ space: Space.small }) {
      Text('标签').fontSize(14).fontColor(Colors.subText)
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        ForEach(this.frequent(), (tag: TimelineTag) => {
          Button({ type: ButtonType.Capsule }) {
            Text((tag.id === this.selectedId ? '✓ ' : '') + tag.name).fontSize(13).fontColor(Colors.text)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .height(32).constraintSize({ maxWidth: 112 })
          .padding({ left: Space.small, right: Space.small })
          .margin({ right: Space.tiny, top: Space.tiny, bottom: Space.tiny })
          .backgroundColor(tag.id === this.selectedId ? '#38' + tag.color.slice(1) : '#F1F2F4')
          .accessibilityText(tag.name + (tag.id === this.selectedId ? '，已选中' : ''))
          .onClick(() => this.choose(tag))
        }, (tag: TimelineTag) => tag.id)
      }.layoutWeight(1)
      Button({ type: ButtonType.Circle }) {
        Stack({ alignContent: Alignment.Center }) {
          Row().width(14).height(2).borderRadius(1).backgroundColor(Colors.subText)
          Row().width(2).height(14).borderRadius(1).backgroundColor(Colors.subText)
        }.width(24).height(24)
      }
      .width(40).height(40).padding(0).backgroundColor(Color.Transparent)
      .accessibilityText('查看全部标签或新建标签')
      .onClick(() => {
        this.onOpen();
        this.menuVisible = !this.menuVisible;
      })
      .bindPopup(this.menuVisible, {
        builder: this.MenuContent, placement: Placement.Bottom, enableArrow: false,
        popupColor: Colors.surface, autoCancel: true,
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
    const name = this.nameDraft.trim();
    if (name.length === 0) {
      this.errorMessage = '请输入标签名称';
      return;
    }
    if (this.tags.some((tag: TimelineTag) => tag.name === name && tag.id !== this.tagId)) {
      this.errorMessage = '这个标签名已存在';
      return;
    }
    if (this.paletteOpen && normalizedTagHex(this.hexDraft).length === 0) {
      this.errorMessage = '请输入六位颜色值，如 #4384BB';
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
    Column({ space: Space.tiny }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Row().width('100%').height('100%')
          .linearGradient({ direction: GradientDirection.Right, colors: [['#FFFFFF', 0], [tagHex(this.hsv.hue, 1, 1), 1]] })
        Row().width('100%').height('100%')
          .linearGradient({ direction: GradientDirection.Bottom, colors: [['#00000000', 0], ['#FF000000', 1]] })
        Row().width(18).height(18).borderRadius(9)
          .border({ color: Color.White, width: 2 }).backgroundColor(this.colorDraft)
          .shadow({ radius: 2, color: '#90000000' })
          .position({ x: Math.max(0, Math.min(this.fieldWidth - 18, this.hsv.saturation * this.fieldWidth - 9)),
            y: Math.max(0, Math.min(COLOR_FIELD_HEIGHT - 18, (1 - this.hsv.value) * COLOR_FIELD_HEIGHT - 9)) })
      }.width('100%').height(COLOR_FIELD_HEIGHT).borderRadius(Radius.small).clip(true)
      .accessibilityText('调整颜色饱和度与明暗，也可在下方输入颜色值')
      .onAreaChange((_old: Area, area: Area) => { this.fieldWidth = Number(area.width); })
      .priorityGesture(GestureGroup(GestureMode.Exclusive,
        PanGesture({ direction: PanDirection.All, distance: 2 })
          .onActionStart((event: GestureEvent) => this.pickInField(event))
          .onActionUpdate((event: GestureEvent) => this.pickInField(event)),
        TapGesture().onAction((event: GestureEvent) => this.pickInField(event))))

      Stack({ alignContent: Alignment.Center }) {
        Row().height(10).borderRadius(5).width('100%')
          .linearGradient({ direction: GradientDirection.Right, colors: [
            ['#FF0000', 0], ['#FFFF00', 1 / 6], ['#00FF00', 2 / 6], ['#00FFFF', 3 / 6],
            ['#0000FF', 4 / 6], ['#FF00FF', 5 / 6], ['#FF0000', 1]] })
        Slider({ value: this.hsv.hue, min: 0, max: 360, step: 1 })
          .width('100%').height(40).trackColor(Color.Transparent).selectedColor(Color.Transparent)
          .blockColor(tagHex(this.hsv.hue, 1, 1)).blockBorderColor(Color.White).blockBorderWidth(2)
          .accessibilityText('色相')
          .onChange((value: number) => this.setChannels(value, this.hsv.saturation, this.hsv.value))
      }.width('100%').height(40)
      Row({ space: Space.small }) {
        Text('颜色值').fontSize(14).fontColor(Colors.subText)
        TextInput({ text: this.hexDraft, controller: this.hexController })
          .width(112).height(40).padding({ left: Space.small, right: Space.small })
          .backgroundColor(Color.Transparent).fontColor(Colors.text).fontSize(15)
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
        Button('返回').height(44).fontSize(14).fontColor(Colors.subText).backgroundColor(Color.Transparent)
          .onClick(() => this.onCancel())
        Blank()
        Text('新建标签').fontSize(16).fontWeight(FontWeight.Medium).fontColor(Colors.text)
        Blank()
        Button(this.saving ? '保存中' : '保存').fontSize(14).height(34)
          .backgroundColor(Colors.text).fontColor(Color.White).borderRadius(Radius.normal)
          .onClick(() => { this.submit(); })
      }.width('100%').padding({ left: Space.small, right: Space.normal, top: Space.tiny, bottom: Space.tiny })
      Scroll() {
        Column({ space: Space.normal }) {
          Text('标签名称').fontSize(14).fontColor(Colors.subText)
          TextInput({ text: this.nameDraft, placeholder: this.focused ? '' : '例如 🎓 答辩', controller: this.nameController })
            .accessibilityText('标签名称').width('100%').height(48).padding(0).fontSize(21)
            .backgroundColor(Color.Transparent).borderRadius(0).fontColor(Colors.text)
            .onFocus(() => { this.focused = true; }).onBlur(() => { this.focused = false; })
            .onChange((value: string) => { this.nameDraft = value; this.errorMessage = ''; })
          Divider().color(Colors.border)
          Row() {
            Text('颜色').layoutWeight(1).fontSize(14).fontColor(Colors.subText)
            Button() {
              Row({ space: Space.small }) {
                Row().width(16).height(16).borderRadius(8).backgroundColor(this.colorDraft)
                  .border({ width: 0.5, color: '#55888888' })
                Text('自定义颜色').fontSize(14).fontColor(Colors.text)
                Text(this.paletteOpen ? '▴' : '▾').fontSize(12).fontColor(Colors.subText)
              }
            }.height(40).padding({ left: Space.small, right: Space.small }).backgroundColor(Color.Transparent)
            .accessibilityText('自定义颜色，当前 ' + this.colorDraft + (this.paletteOpen ? '，已展开' : ''))
            .onClick(() => this.togglePalette())
          }.width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(TAG_PALETTE, (swatch: TagSwatch) => {
              Button({ type: ButtonType.Normal }) {
                Stack({ alignContent: Alignment.Center }) {
                  Row().width(27).height(27).borderRadius(14).backgroundColor(swatch.color)
                }.width(35).height(35).borderRadius(18)
                .border({ width: this.colorDraft === swatch.color ? 2 : 0, color: Colors.text })
              }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
              .accessibilityText(swatch.name + (this.colorDraft === swatch.color ? '，已选中' : ''))
              .onClick(() => this.selectHex(swatch.color))
            }, (swatch: TagSwatch) => swatch.color)
          }.width('100%')
          if (this.paletteOpen) {
            this.CustomPalette()
          }
          if (this.errorMessage.length > 0) {
            Text(this.errorMessage).fontSize(14).fontColor(Colors.danger)
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding(Space.large)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }.width('100%').height('100%').enabled(!this.saving).backgroundColor(Colors.surface)
  }
}
