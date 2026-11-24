import { Colors } from '../common/Theme';
import { ModuleType } from '../model/Types';

function moduleIconPath(type: ModuleType): string {
  switch (type) {
    case ModuleType.Deadline:
    case ModuleType.Countdown:
      return 'M4 7 H20 V20 H4 Z M8 3 V7 M16 3 V7 M4 11 H20';
    case ModuleType.Counter:
      return 'M4 5 H20 V19 H4 Z M12 8.5 V15.5 M8.5 12 H15.5';
    case ModuleType.Checklist:
      return 'M4 7 L6.2 9.2 L9.5 5.8 M12 7.5 H20 M4 16.5 L6.2 18.7 L9.5 15.3 M12 17 H20';
    case ModuleType.EventRecord:
      return 'M12 3.5 A8.5 8.5 0 1 0 12 20.5 A8.5 8.5 0 1 0 12 3.5 Z M12 7.5 V12 L15 14';
    case ModuleType.Note:
    default:
      return 'M5 4 H19 V20 H5 Z M8 9 H16 M8 13 H16 M8 17 H13';
  }
}

@Component
export struct ModuleIcon {
  @Prop moduleType: ModuleType = ModuleType.Note;
  @Prop ink: ResourceColor = Colors.inkSoft;
  @Prop iconSize: number = 18;

  build() {
    Shape() {
      Path().commands(moduleIconPath(this.moduleType))
    }
    .width(this.iconSize)
    .height(this.iconSize)
    .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
    .fill(Color.Transparent)
    .stroke(this.ink)
    .strokeWidth('1.5px')
    .strokeLineCap(LineCapStyle.Round)
    .strokeLineJoin(LineJoinStyle.Round)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no');
  }
}
