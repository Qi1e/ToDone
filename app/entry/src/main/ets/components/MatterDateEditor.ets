import { DateMode } from '../model/Types';
import { dateModeLabel, formatDate, pad2 } from '../common/DateFormat';

@Component
export struct MatterDateEditor {
  @Link date: Date;
  @Link mode: DateMode;
  @Link hasTime: boolean;

  private shortcut(offset: number): void {
    const today = new Date();
    today.setDate(today.getDate() + offset);
    today.setHours(this.date.getHours(), this.date.getMinutes(), 0, 0);
    this.date = today;
  }

  build() {
    Column() {
      Row() {
        ForEach(['countdown', 'elapsed', 'deadline'], (mode: DateMode) => {
          Button(dateModeLabel(mode))
            .type(this.mode === mode ? ButtonType.Capsule : ButtonType.Normal)
            .onClick(() => { this.mode = mode; });
        });
      }
      Row() {
        Button('今天').onClick(() => this.shortcut(0))
        Button('明天').onClick(() => this.shortcut(1))
        Button('本周末').onClick(() => this.shortcut(new Date().getDay() === 0 ? 0 : 6 - new Date().getDay()))
        Button('下周').onClick(() => this.shortcut((8 - new Date().getDay()) % 7 || 7))
      }
      Button(formatDate(this.date.getTime())).onClick(() => {
        DatePickerDialog.show({
          start: new Date(1900, 0, 1), end: new Date(2100, 11, 31), selected: this.date,
          onAccept: (value: DatePickerResult) => {
            this.date = new Date(value.year ?? this.date.getFullYear(), value.month ?? this.date.getMonth(),
              value.day ?? this.date.getDate(), this.date.getHours(), this.date.getMinutes());
          }
        });
      })
      if (this.mode === 'deadline') {
        Row() {
          Text('具体时间')
          Toggle({ type: ToggleType.Switch, isOn: this.hasTime })
            .onChange((enabled: boolean) => { this.hasTime = enabled; });
        }
        if (this.hasTime) {
          Button(pad2(this.date.getHours()) + ':' + pad2(this.date.getMinutes())).onClick(() => {
            TimePickerDialog.show({
              selected: this.date, useMilitaryTime: true,
              onAccept: (value: TimePickerResult) => {
                const next = new Date(this.date.getTime());
                next.setHours(value.hour ?? 0, value.minute ?? 0, 0, 0);
                this.date = next;
              }
            });
          })
        }
      }
    }
  }
}
