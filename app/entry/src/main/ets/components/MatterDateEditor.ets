import { DateMode } from '../model/Types';
import { daysUntil, formatDate, pad2 } from '../common/DateFormat';
import { Colors, Radius, Space } from '../common/Theme';

@Component
export struct MatterDateEditor {
  @Link date: Date;
  @Link mode: DateMode;
  @Link hasTime: boolean;

  private dateLabel(): string {
    if (this.mode === 'elapsed') return '起始日期';
    if (this.mode === 'deadline') return '截止日期';
    return '目标日期';
  }

  private dateEnd(): Date {
    if (this.mode === 'elapsed') {
      const end = new Date();
      end.setHours(23, 59, 59, 999);
      return end;
    }
    return new Date(2100, 11, 31);
  }

  private pickDate(): void {
    DatePickerDialog.show({
      start: new Date(1900, 0, 1),
      end: this.dateEnd(),
      selected: this.date,
      onAccept: (value: DatePickerResult) => {
        this.date = new Date(value.year ?? this.date.getFullYear(), value.month ?? this.date.getMonth(),
          value.day ?? this.date.getDate(), this.date.getHours(), this.date.getMinutes());
      }
    });
  }

  private pickTime(): void {
    TimePickerDialog.show({
      selected: this.date,
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        const next = new Date(this.date.getTime());
        next.setHours(value.hour ?? 0, value.minute ?? 0, 0, 0);
        this.date = next;
      }
    });
  }

  private selectMode(mode: DateMode): void {
    this.mode = mode;
    if (mode === 'elapsed' && daysUntil(this.date.getTime()) > 0) {
      const today = new Date();
      today.setHours(this.date.getHours(), this.date.getMinutes(), 0, 0);
      this.date = today;
    }
  }

  @Builder
  private modeOption(value: DateMode, title: string, help: string) {
    Row({ space: Space.normal }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(18)
          .height(18)
          .borderRadius(9)
          .backgroundColor(Colors.surface)
          .border({ width: 1, color: this.mode === value ? Colors.primary : Colors.border });
        if (this.mode === value) {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(Colors.primary);
        }
      }
      .width(18)
      .height(18);

      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.text);
        Text(help)
          .fontSize(13)
          .fontColor(Colors.subText);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .constraintSize({ minHeight: 66 })
    .padding(Space.normal)
    .margin({ bottom: Space.small })
    .backgroundColor(this.mode === value ? Colors.primarySoft : Colors.page)
    .borderRadius(Radius.normal)
    .border({ width: 1, color: this.mode === value ? Colors.primary : Colors.border })
    .onClick(() => this.selectMode(value));
  }

  @Builder
  private pickerField(label: string, value: string, onPick: () => void) {
    Column({ space: Space.small }) {
      Text(label)
        .fontSize(15)
        .fontColor(Colors.text)
        .width('100%');
      Button() {
        Row() {
          Text(value)
            .fontSize(15)
            .fontColor(Colors.text);
          Blank();
          Text('⌄')
            .fontSize(16)
            .fontColor(Colors.subText);
        }
        .width('100%')
        .padding({ left: Space.normal, right: Space.normal });
      }
      .width('100%')
      .height(44)
      .type(ButtonType.Normal)
      .backgroundColor(Colors.surfaceSoft)
      .borderRadius(Radius.normal)
      .onClick(onPick);
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  build() {
    Column({ space: Space.small }) {
      Text('你想怎样使用这个日期？')
        .fontSize(13)
        .fontColor(Colors.subText)
        .width('100%');

      this.modeOption('countdown', '倒数日', '看距离某一天还有多少天');
      this.modeOption('elapsed', '正数日', '看从某一天起已经过多少天');
      this.modeOption('deadline', '截止时间', '标记最晚何时完成');

      this.pickerField(this.dateLabel(), formatDate(this.date.getTime()), () => this.pickDate());

      if (this.mode === 'deadline') {
        Row({ space: Space.small }) {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(18)
              .height(18)
              .borderRadius(4)
              .backgroundColor(this.hasTime ? Colors.primary : Colors.surface)
              .border({ width: 1, color: this.hasTime ? Colors.primary : Colors.border });
            if (this.hasTime) {
              Text('✓')
                .fontSize(12)
                .fontColor(Color.White);
            }
          }
          .width(18)
          .height(18);

          Text('设置具体时间')
            .fontSize(15)
            .fontColor(Colors.text);
        }
        .width('100%')
        .onClick(() => {
          if (!this.hasTime) {
            const next = new Date(this.date.getTime());
            next.setHours(18, 0, 0, 0);
            this.date = next;
            this.hasTime = true;
          } else {
            this.hasTime = false;
          }
        });

        if (this.hasTime) {
          this.pickerField('具体时间', pad2(this.date.getHours()) + ':' + pad2(this.date.getMinutes()),
            () => this.pickTime());
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }
}
