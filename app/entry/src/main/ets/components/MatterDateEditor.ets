import { DateMode } from '../model/Types';
import { daysUntil, formatDate, pad2 } from '../common/DateFormat';
import { Colors, Radius, Space, TABULAR_NUMS, TypeSize, TypeWeight } from '../common/Theme';

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
    Row({ space: Space.md }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(20)
          .height(20)
          .borderRadius(10)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: this.mode === value ? Colors.ink : Colors.line });
        if (this.mode === value) {
          Column()
            .width(10)
            .height(10)
            .borderRadius(5)
            .backgroundColor(Colors.ink);
        }
      }
      .width(20)
      .height(20);

      Column({ space: Space.xs }) {
        Text(title)
          .fontSize(TypeSize.body)
          .fontWeight(this.mode === value ? TypeWeight.semibold : TypeWeight.regular)
          .fontColor(this.mode === value ? Colors.ink : Colors.inkSoft);
        Text(help)
          .fontSize(TypeSize.meta)
          .fontWeight(TypeWeight.regular)
          .fontColor(Colors.inkMuted);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding(Space.md)
    .margin({ bottom: Space.xs })
    .backgroundColor(this.mode === value ? Colors.wash : Color.Transparent)
    .borderRadius(Radius.card)
    .onClick(() => this.selectMode(value));
  }

  @Builder
  private pickerField(label: string, value: string, onPick: () => void) {
    Column({ space: Space.sm }) {
      Text(label)
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkSoft)
        .width('100%');
      Button() {
        Row() {
          Text(value)
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.regular)
            .fontColor(Colors.ink)
            .fontFeature(TABULAR_NUMS);
          Blank();
          Text('⌄')
            .fontSize(16)
            .fontColor(Colors.inkMuted);
        }
        .width('100%')
        .padding({ left: Space.md, right: Space.md });
      }
      .width('100%')
      .constraintSize({ minHeight: 44 })
      .type(ButtonType.Normal)
      .backgroundColor(Colors.wash)
      .borderRadius(Radius.card)
      .onClick(onPick);
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  build() {
    Column({ space: Space.sm }) {
      Text('你想怎样使用这个日期？')
        .fontSize(TypeSize.bodySmall)
        .fontWeight(TypeWeight.regular)
        .fontColor(Colors.inkSoft)
        .width('100%');

      this.modeOption('countdown', '倒数日', '看距离某一天还有多少天');
      this.modeOption('elapsed', '正数日', '看从某一天起已经过多少天');
      this.modeOption('deadline', '截止时间', '标记最晚何时完成');

      this.pickerField(this.dateLabel(), formatDate(this.date.getTime()), () => this.pickDate());

      if (this.mode === 'deadline') {
        Row({ space: Space.md }) {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(20)
              .height(20)
              .borderRadius(Radius.chip)
              .backgroundColor(this.hasTime ? Colors.ink : Color.Transparent)
              .border({ width: 1, color: this.hasTime ? Colors.ink : Colors.line });
            if (this.hasTime) {
              Text('✓')
                .fontSize(TypeSize.meta)
                .fontWeight(TypeWeight.semibold)
                .fontColor(Colors.bg);
            }
          }
          .width(20)
          .height(20);

          Text('设置具体时间')
            .fontSize(TypeSize.body)
            .fontWeight(TypeWeight.regular)
            .fontColor(Colors.ink);
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .alignItems(VerticalAlign.Center)
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
