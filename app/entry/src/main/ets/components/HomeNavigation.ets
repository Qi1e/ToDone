import { Colors, Space } from '../common/Theme';

export enum HomeTab {
  Cards = '卡片',
  Timeline = '时间线',
  Review = '复盘',
  Settings = '设置'
}

export const DOCK_HEIGHT: number = 38;
const DOCK_TOUCH_HEIGHT: number = 44;
export const DOCK_MARGIN: number = 3;
export const DOCK_CLEARANCE: number = DOCK_TOUCH_HEIGHT + DOCK_MARGIN + Space.tiny;

export enum HomeGlyph {
  Cards, Timeline, Review, Settings, Hint, Search, Add
}

// 顶栏与底栏共用 24 × 24 的线稿，各自按所需的 vp 尺寸绘制。
const ICON_PATHS: string[] = [
  'M6 16 L4 16 Q2 16 2 14 L2 5 Q2 3 4 3 L14 3 Q16 3 16 5 L16 6 M9 7 H19 Q21 7 21 9 V19 Q21 21 19 21 H9 Q7 21 7 19 V9 Q7 7 9 7 Z',
  'M12 2.5 A9.5 9.5 0 1 0 12 21.5 A9.5 9.5 0 1 0 12 2.5 Z M12 6 V12 H16',
  'M5 19 V14 M12 19 V9 M19 19 V4',
  'M10 3 L14 3 L15 5.4 L17 6.5 L19.6 6 L21.5 9.4 L19.8 11.4 V13 L21.4 15 L19.4 18.4 L16.9 18 L15 19 L14 21.4 H10 L9 19 L7.1 18 L4.6 18.4 L2.6 15 L4.2 13 V11.4 L2.5 9.4 L4.4 6 L7 6.5 L9 5.4 Z M12 9 A3 3 0 1 0 12 15 A3 3 0 1 0 12 9 Z',
  'M9 19 H15 M10 22 H14 M8.5 16.5 C8.5 13 4.5 12.5 4.5 8 A7.5 7.5 0 0 1 19.5 8 C19.5 12.5 15.5 13 15.5 16.5 Z',
  'M10 3 A7 7 0 1 0 10 17 A7 7 0 1 0 10 3 Z M15.4 15.4 L21 21',
  'M12 3 V21 M3 12 H21'
];

@Component
export struct HomeIcon {
  @Prop glyph: HomeGlyph;
  @Prop ink: string = Colors.text;
  @Prop iconSize: number = 24;
  build() {
    Shape() {
      Path().commands(ICON_PATHS[this.glyph])
    }.width(this.iconSize).height(this.iconSize).viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
    .fill(Color.Transparent).stroke(this.ink).strokeWidth('1.8px')
    .strokeLineCap(LineCapStyle.Round).strokeLineJoin(LineJoinStyle.Round)
    .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}

@Component
export struct HomeDock {
  @Prop tab: HomeTab;
  onSelect: (tab: HomeTab) => void = () => {};

  @Builder
  private Item(tab: HomeTab, glyph: HomeGlyph) {
    Button({ type: ButtonType.Capsule }) {
      Row() {
        HomeIcon({ glyph: glyph, ink: this.tab === tab ? Colors.text : Colors.subText, iconSize: 20 })
      }.width('100%').height(30).justifyContent(FlexAlign.Center).borderRadius(15)
      .backgroundColor(this.tab === tab ? '#F1F3F5' : Color.Transparent)
    }.height(DOCK_TOUCH_HEIGHT).layoutWeight(1).padding(0).backgroundColor(Color.Transparent)
    .enabled(tab !== HomeTab.Review)
    .accessibilityText(tab + (tab === this.tab ? '，已选中' : ''))
    .onClick(() => this.onSelect(tab))
  }

  build() {
    Stack() {
      Row().width('100%').height(DOCK_HEIGHT).backgroundColor('#FAFFFFFF').borderRadius(DOCK_HEIGHT / 2)
        .border({ width: 1, color: Colors.border }).shadow({ radius: 7, color: '#200F1A27', offsetY: 2 })
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      Row({ space: 2 }) {
        this.Item(HomeTab.Cards, HomeGlyph.Cards)
        this.Item(HomeTab.Timeline, HomeGlyph.Timeline)
        this.Item(HomeTab.Review, HomeGlyph.Review)
        this.Item(HomeTab.Settings, HomeGlyph.Settings)
      }.width('100%').height(DOCK_TOUCH_HEIGHT).padding({ left: 4, right: 4 })
    }.width('65%').constraintSize({ minWidth: 192, maxWidth: 260 }).height(DOCK_TOUCH_HEIGHT)
  }
}
