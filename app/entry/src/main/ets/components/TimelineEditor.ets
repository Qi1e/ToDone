import { Colors, Radius, Space, TABULAR_NUMS, TypeSize, TypeWeight } from '../common/Theme';
import { formatDate, pad2 } from '../common/DateFormat';
import { TimelineAttachment, TimelineBlock, TimelineRepeat, timelineRepeatLabel, TimelineTag,
  TIMELINE_REMINDER_MINUTES, timelineReminderLabel } from '../contracts/TimelineService';
import { firstTimelineOccurrence, timelineDateNumber } from '../domain/TimelineRecurrence';
import { TimelineDatePicker } from './TimelineDatePicker';
import { TimelineTagForm, TimelineTagPicker } from './TimelineTags';
import { TimelineNotePart, timelineNoteParts } from '../domain/TimelineNoteLinks';
import { TimelineLinkedNote } from './TimelineLinkedNote';

import { TimelineAttachmentButton, TimelineAttachmentList } from './TimelineAttachments';
import { TimelineAttachmentSession } from '../application/TimelineAttachmentFiles';

enum Endpoint {
  Start,
  End
}

enum Picker {
  None,
  Clock,
  Month,
  Repeat,
  Reminder
}

const CLOCK_WIDTH: number = 180;
const CLOCK_COLUMNS_WIDTH: number = 144;
const CLOCK_HEIGHT: number = 164;
const CLOCK_SELECTION_HEIGHT: number = 38;
const REMINDER_OPTIONS: number[] = [-1].concat(TIMELINE_REMINDER_MINUTES);
const DAY_NAMES: string[] = ['日', '一', '二', '三', '四', '五', '六'];
const REPEAT_OPTIONS: TimelineRepeat[] = [TimelineRepeat.None, TimelineRepeat.Daily, TimelineRepeat.Weekdays,
  TimelineRepeat.Weekly, TimelineRepeat.Monthly];

@Component
export struct TimelineEditor {
  @Prop initial: TimelineBlock;
  attachmentSession: TimelineAttachmentSession = new TimelineAttachmentSession();
  onAttachmentBusy: (busy: boolean) => void = () => {};
  @Prop blocks: TimelineBlock[] = [];
  @Prop tags: TimelineTag[] = [];
  @Prop editing: boolean = false;
  @Prop seriesEdit: boolean = false;
  @Prop initialClock: string = '';
  @Prop saving: boolean = false;
  @Prop errorMessage: string = '';
  onSave: (block: TimelineBlock) => void = () => {};
  onCancel: () => void = () => {};
  onSaveTag: (tag: TimelineTag) => Promise<void> = (tag: TimelineTag) => Promise.reject(new Error('标签存储未就绪'));

  @State private titleDraft: string = '';
  @State private noteDraft: string = '';
  @State private attachmentDraft: TimelineAttachment[] = [];
  @State private importing: boolean = false;
  @State private reminder: number = -1;
  @State private tagId: string = '';
  @State private repeat: TimelineRepeat = TimelineRepeat.None;
  @Link newTagPage: boolean;
  @State private startAt: number = 0;
  @State private endAt: number = 0;
  @State private picker: Picker = Picker.None;
  @State private endpoint: Endpoint = Endpoint.Start;
  @State private weekEndpoint: Endpoint = Endpoint.Start;
  @State private titleFocused: boolean = false;
  @State private noteFocused: boolean = false;
  @State private noteHasLinks: boolean = false;
  @State private previewNote: boolean = false;
  private requestNoteFocus: boolean = false;
  @State private validation: string = '';

  private formScroller: Scroller = new Scroller();
  private titleController: TextInputController = new TextInputController();
  private noteController: RichEditorController = new RichEditorController();

  aboutToAppear(): void {
    this.titleDraft = this.initial.title;
    this.noteDraft = this.initial.note;
    this.noteHasLinks = timelineNoteParts(this.noteDraft).some((part: TimelineNotePart) => part.href !== undefined);
    this.previewNote = this.noteHasLinks;
    this.attachmentDraft = (this.initial.attachments ?? []).slice();
    this.attachmentSession.retain(this.attachmentDraft);
    this.reminder = this.initial.reminderMinutes ?? -1;
    this.tagId = this.initial.tagId ?? '';
    this.repeat = this.initial.repeat ?? TimelineRepeat.None;
    this.startAt = this.initial.startAt;
    this.endAt = this.initial.endAt;
    if (this.editing && (this.initialClock === 'start' || this.initialClock === 'end')) {
      this.endpoint = this.initialClock === 'start' ? Endpoint.Start : Endpoint.End;
      this.weekEndpoint = this.endpoint;
      this.picker = Picker.Clock;
    }
  }

  private endpointTime(endpoint: Endpoint): number {
    return endpoint === Endpoint.Start ? this.startAt : this.endAt;
  }

  private labelOf(endpoint: Endpoint): string {
    return endpoint === Endpoint.Start ? '开始' : '结束';
  }

  private dayLabel(timestamp: number): string {
    const date = new Date(timestamp);
    const showYear = date.getFullYear() !== new Date().getFullYear();
    const year = showYear ? `${date.getFullYear()}年` : '';
    return `${year}${date.getMonth() + 1}月${date.getDate()}日 周${DAY_NAMES[date.getDay()]}`;
  }

  private clockLabel(timestamp: number): string {
    const date = new Date(timestamp);
    return `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
  }

  private durationLabel(): string {
    const mins = Math.round((this.endAt - this.startAt) / 60000);
    if (mins <= 0) return '结束须晚于开始，跨日可调整结束日期';
    const hours = Math.floor(mins / 60);
    const rest = mins % 60;
    const hoursLabel = hours > 0 ? `${hours} 小时` : '';
    const minsLabel = rest > 0 ? `${rest} 分钟` : '';
    return `共 ${hoursLabel}${hours > 0 && rest > 0 ? ' ' : ''}${minsLabel}`;
  }

  private openPicker(next: Picker, endpoint: Endpoint): void {
    if (this.saving) return;
    if (this.titleFocused) this.titleController.stopEditing();
    if (this.noteFocused) this.noteController.stopEditing();
    const closing = this.picker === next && this.endpoint === endpoint;
    if (!closing && next === Picker.Month) {
      this.weekEndpoint = endpoint;
      this.formScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: true });
    }
    this.picker = closing ? Picker.None : next;
    this.endpoint = endpoint;
  }

  private setEndpoint(endpoint: Endpoint, timestamp: number): void {
    if (this.saving || !Number.isFinite(timestamp)) return;
    if (endpoint === Endpoint.Start) {
      const length = this.endAt - this.startAt;
      this.startAt = timestamp;
      if (length > 0) this.endAt = timestamp + length;
    } else {
      this.endAt = timestamp;
    }
    this.validation = '';
  }

  private pickDay(day: number): void {
    const chosen = new Date(day);
    const value = new Date(this.endpointTime(this.endpoint));
    value.setFullYear(chosen.getFullYear(), chosen.getMonth(), chosen.getDate());
    this.setEndpoint(this.endpoint, value.getTime());
    this.weekEndpoint = this.endpoint;
    this.picker = Picker.None;
  }

  private pickTime(endpoint: Endpoint, result: TimePickerResult): void {
    if (this.picker !== Picker.Clock || this.endpoint !== endpoint) return;
    const value = new Date(this.endpointTime(endpoint));
    value.setHours(result.hour ?? value.getHours(), result.minute ?? value.getMinutes(), 0, 0);
    this.setEndpoint(endpoint, value.getTime());
  }

  private draftBlock(): TimelineBlock {
    const block: TimelineBlock = { id: this.initial.id, title: this.titleDraft.trim(), startAt: this.startAt,
      endAt: this.endAt, note: this.noteDraft };
    if (this.attachmentDraft.length > 0) block.attachments = this.attachmentDraft.slice();
    if (this.reminder >= 0) block.reminderMinutes = this.reminder;
    if (this.tagId.length > 0) block.tagId = this.tagId;
    if (this.repeat !== TimelineRepeat.None) block.repeat = this.repeat;
    return block;
  }

  private pastOriginalHint(): string {
    return this.editing && timelineDateNumber(this.initial.startAt) < timelineDateNumber(Date.now()) ? '，原来的那次保留' : '';
  }

  private repeatHint(): string {
    if (this.repeat !== TimelineRepeat.None && !this.seriesEdit && this.endAt > this.startAt) {
      const first = firstTimelineOccurrence(this.draftBlock(), Date.now());
      const history = this.pastOriginalHint();
      if (formatDate(first.startAt) !== formatDate(this.startAt) || history.length > 0) {
        return '首次重复在' + this.dayLabel(first.startAt) + history;
      }
    }
    if (this.repeat === TimelineRepeat.Weekdays) return '每周一至周五';
    const date = new Date(this.startAt).getDate();
    if (this.repeat === TimelineRepeat.Monthly && date >= 29) {
      return '每月' + date + '日，跳过没有这一天的月份';
    }
    return '';
  }

  private submit(): void {
    if (this.saving || this.importing) return;
    if (this.noteFocused) {
      this.noteChanged();
      this.noteController.stopEditing();
    }
    const block = this.draftBlock();
    if (block.title.length === 0) {
      this.validation = '请填写日程名称';
      return;
    }
    if (!(this.endAt > this.startAt)) {
      this.validation = '结束时间须晚于开始时间';
      return;
    }
    this.validation = '';
    this.onSave(block);
  }

  @Builder
  private RepeatOptions() {
    Scroll() {
      Column() {
        ForEach(REPEAT_OPTIONS, (option: TimelineRepeat) => {
          Button({ type: ButtonType.Normal }) {
            Row() {
              Text(timelineRepeatLabel(option)).layoutWeight(1).fontSize(TypeSize.body)
                .fontWeight(option === this.repeat ? TypeWeight.semibold : TypeWeight.regular)
                .fontColor(option === this.repeat ? Colors.ink : Colors.inkSoft);
              if (option === this.repeat) {
                Text('✓').fontSize(TypeSize.body).fontWeight(TypeWeight.semibold).fontColor(Colors.ink);
              }
            }.width('100%');
          }.width('100%').height(44).padding({ left: Space.md, right: Space.md })
          .backgroundColor(option === this.repeat ? Colors.wash : Color.Transparent)
          .borderRadius(Radius.card)
          .accessibilityText(timelineRepeatLabel(option) + (option === this.repeat ? '，已选中' : ''))
          .onClick(() => { this.repeat = option; this.picker = Picker.None; });
        }, (option: TimelineRepeat) => option);
      }.width('100%').padding(Space.xs);
    }.width(176).constraintSize({ maxHeight: 224 });
  }

  @Builder
  private RepeatField() {
    Row() {
      Text('重复').layoutWeight(1).fontSize(TypeSize.body).fontColor(Colors.inkSoft);
      Button({ type: ButtonType.Normal }) {
        Row({ space: Space.sm }) {
          Text(timelineRepeatLabel(this.repeat)).fontSize(TypeSize.body).fontWeight(TypeWeight.semibold).fontColor(Colors.ink);
          Text('▾').fontSize(TypeSize.meta).fontColor(Colors.inkMuted);
        }
      }.height(44).padding({ left: Space.sm, right: Space.sm }).backgroundColor(Color.Transparent).borderRadius(Radius.card)
      .accessibilityText('重复，' + timelineRepeatLabel(this.repeat))
      .onClick(() => this.openPicker(Picker.Repeat, Endpoint.Start))
      .bindPopup(this.picker === Picker.Repeat, {
        builder: this.RepeatOptions, placement: Placement.Bottom, enableArrow: false,
        popupColor: Colors.card, autoCancel: true,
        onStateChange: (event) => { if (!event.isVisible && this.picker === Picker.Repeat) this.picker = Picker.None; }
      });
    }.width('100%');
    if (this.repeatHint().length > 0) {
      Text(this.repeatHint()).width('100%').fontSize(TypeSize.meta).fontColor(Colors.inkMuted);
    }
  }

  @Builder
  private ReminderOptions() {
    Scroll() {
      Column() {
        ForEach(REMINDER_OPTIONS, (minutes: number) => {
          Button({ type: ButtonType.Normal }) {
            Row() {
              Text(timelineReminderLabel(minutes < 0 ? undefined : minutes)).layoutWeight(1).fontSize(TypeSize.body)
                .fontWeight(minutes === this.reminder ? TypeWeight.semibold : TypeWeight.regular)
                .fontColor(minutes === this.reminder ? Colors.ink : Colors.inkSoft);
              if (minutes === this.reminder) {
                Text('✓').fontSize(TypeSize.body).fontWeight(TypeWeight.semibold).fontColor(Colors.ink);
              }
            }.width('100%');
          }.width('100%').height(44).padding({ left: Space.md, right: Space.md })
          .backgroundColor(minutes === this.reminder ? Colors.wash : Color.Transparent)
          .borderRadius(Radius.card)
          .accessibilityText(timelineReminderLabel(minutes < 0 ? undefined : minutes) +
            (minutes === this.reminder ? '，已选中' : ''))
          .onClick(() => { this.reminder = minutes; this.picker = Picker.None; });
        }, (minutes: number) => minutes.toString());
      }.width('100%').padding(Space.xs);
    }.width(176).constraintSize({ maxHeight: 268 });
  }

  @Builder
  private ReminderField() {
    Row() {
      Text('提醒').layoutWeight(1).fontSize(TypeSize.body).fontColor(Colors.inkSoft);
      Button({ type: ButtonType.Normal }) {
        Row({ space: Space.sm }) {
          Text(timelineReminderLabel(this.reminder < 0 ? undefined : this.reminder)).fontSize(TypeSize.body)
            .fontWeight(TypeWeight.semibold).fontColor(Colors.ink);
          Text('▾').fontSize(TypeSize.meta).fontColor(Colors.inkMuted);
        }
      }.height(44).padding({ left: Space.sm, right: Space.sm }).backgroundColor(Color.Transparent).borderRadius(Radius.card)
      .accessibilityText('提醒，' + timelineReminderLabel(this.reminder < 0 ? undefined : this.reminder))
      .onClick(() => this.openPicker(Picker.Reminder, Endpoint.Start))
      .bindPopup(this.picker === Picker.Reminder, {
        builder: this.ReminderOptions, placement: Placement.Bottom, enableArrow: false,
        popupColor: Colors.card, autoCancel: true,
        onStateChange: (event) => { if (!event.isVisible && this.picker === Picker.Reminder) this.picker = Picker.None; }
      });
    }.width('100%');
  }

  @Builder
  private TimeRow(endpoint: Endpoint) {
    Row() {
      Text(this.labelOf(endpoint)).fontSize(TypeSize.body).fontColor(Colors.inkSoft);
      Blank();
      Button(this.dayLabel(this.endpointTime(endpoint)), { type: ButtonType.Normal })
        .height(44).padding({ left: Space.xs, right: Space.xs }).fontSize(TypeSize.bodySmall).fontColor(Colors.inkSoft)
        .backgroundColor(Color.Transparent).borderRadius(Radius.card)
        .accessibilityText(`${this.labelOf(endpoint)}日期 ${formatDate(this.endpointTime(endpoint))}`)
        .onClick(() => this.openPicker(Picker.Month, endpoint));
      Button(this.clockLabel(this.endpointTime(endpoint)), { type: ButtonType.Normal })
        .height(44).padding({ left: Space.sm, right: Space.sm })
        .borderRadius(Radius.card).fontSize(20).fontWeight(TypeWeight.semibold).fontColor(Colors.ink)
        .backgroundColor(this.picker === Picker.Clock && this.endpoint === endpoint ? Colors.wash : Color.Transparent)
        .accessibilityText(`${this.labelOf(endpoint)}时刻 ${this.clockLabel(this.endpointTime(endpoint))}`)
        .onClick(() => this.openPicker(Picker.Clock, endpoint));
    }.width('100%');
    if (this.picker === Picker.Clock && this.endpoint === endpoint) {
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width('100%').height(CLOCK_SELECTION_HEIGHT).borderRadius(Radius.card)
          .backgroundColor(Colors.wash).hitTestBehavior(HitTestMode.None).accessibilityLevel('no');
        TimePicker({ selected: new Date(this.endpointTime(endpoint)) })
          .key(endpoint === Endpoint.Start ? 'timeline-start-clock' : 'timeline-end-clock')
          .width(CLOCK_COLUMNS_WIDTH).constraintSize({ maxWidth: '100%' }).height(CLOCK_HEIGHT)
          .backgroundColor(Color.Transparent).useMilitaryTime(true)
          .dateTimeOptions({ hour: '2-digit', minute: '2-digit' })
          .selectedTextStyle({ color: Colors.ink, font: { size: 22, weight: TypeWeight.semibold } })
          .textStyle({ color: Colors.inkSoft, font: { size: 17 } })
          .disappearTextStyle({ color: Colors.inkMuted, font: { size: 13 } })
          .onChange((result: TimePickerResult) => this.pickTime(endpoint, result));
      }
      .width(CLOCK_WIDTH).constraintSize({ maxWidth: '100%' }).height(CLOCK_HEIGHT);
    }
  }

  @Builder
  private Toolbar() {
    Row() {
      Button('取消', { type: ButtonType.Normal }).constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.body).fontWeight(TypeWeight.regular).fontColor(Colors.inkSoft)
        .backgroundColor(Color.Transparent).borderRadius(Radius.card).padding({ left: Space.sm, right: Space.sm })
        .onClick(() => this.onCancel());
      Blank();
      Text(this.editing ? '编辑日程' : '新建日程')
        .fontSize(TypeSize.title).fontWeight(TypeWeight.semibold).fontColor(Colors.ink);
      Blank();
      Button(this.saving ? '保存中' : '保存', { type: ButtonType.Normal }).constraintSize({ minHeight: 40 })
        .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold)
        .backgroundColor(Colors.red).fontColor(Colors.onRed).borderRadius(Radius.card)
        .padding({ left: Space.lg, right: Space.lg })
        .opacity(this.saving ? 0.4 : 1)
        .onClick(() => this.submit());
    }
    .width('100%')
    .padding({ left: Space.md, right: Space.page, top: Space.sm, bottom: Space.sm });
  }

  private editNote(): void {
    this.requestNoteFocus = true;
    this.previewNote = false;
  }

  private colorNote(parts: TimelineNotePart[]): void {
    for (const part of parts) {
      this.noteController.updateSpanStyle({ start: part.start, end: part.start + part.text.length,
        textStyle: { fontColor: Colors.ink, fontSize: 14 } });
    }
  }

  private noteChanged(): void {
    // 等输入法确认候选后再着色，保留组合输入、系统选区和撤销行为。
    if ((this.noteController.getPreviewText()?.value?.length ?? 0) > 0) return;
    let text = '';
    for (const span of this.noteController.getSpans()) {
      const item = span as RichEditorTextSpanResult;
      if (typeof item.value === 'string') text += item.value;
    }
    if (text === this.noteDraft) return;
    const hadLinks = this.noteHasLinks;
    this.noteDraft = text;
    const parts = timelineNoteParts(text);
    this.noteHasLinks = parts.some((part: TimelineNotePart) => part.href !== undefined);
    if (hadLinks || this.noteHasLinks) this.colorNote(parts);
  }

  @Builder
  private NoteField() {
    if (this.previewNote) {
      Column() {
        TimelineLinkedNote({ value: this.noteDraft, onEdit: () => this.editNote() });
      }.width('100%').constraintSize({ minHeight: 52 }).alignItems(HorizontalAlign.Start)
    } else {
      RichEditor({ controller: this.noteController })
        .id('timeline-note-editor').width('100%').constraintSize({ minHeight: 52 })
        .placeholder(this.noteFocused ? '' : '添加备注', { fontColor: Colors.inkMuted, font: { size: 14 } })
        .accessibilityText('备注').padding(Space.sm).backgroundColor(Colors.wash).borderRadius(Radius.card)
        .onReady(() => {
          this.noteController.setTypingStyle({ fontColor: Colors.ink, fontSize: 14 });
          if (this.noteDraft.length > 0) {
            this.noteController.addTextSpan(this.noteDraft, { style: { fontColor: Colors.ink, fontSize: 14 } });
            if (this.noteHasLinks) this.colorNote(timelineNoteParts(this.noteDraft));
          }
          if (this.requestNoteFocus) {
            this.requestNoteFocus = false;
            this.getUIContext().getFocusController().requestFocus('timeline-note-editor');
          }
        })
        .onEditingChange((editing: boolean) => {
          if (editing) this.picker = Picker.None;
          else if (this.noteFocused && !this.previewNote && !this.newTagPage) {
            this.noteChanged();
            this.previewNote = this.noteHasLinks;
          }
          this.noteFocused = editing;
        })
        .onWillChange((change: RichEditorChangeValue): boolean => (change.replacedImageSpans?.length ?? 0) === 0)
        .onDidChange(() => { this.noteChanged(); });
    }
  }

  @Builder
  private Fields() {
    Column({ space: Space.sm }) {
      Column() {
        TextInput({ text: this.titleDraft, placeholder: this.titleFocused ? '' : '日程名称', controller: this.titleController })
          .width('100%').constraintSize({ minHeight: 48 }).padding({ left: Space.sm, right: Space.sm })
          .fontSize(TypeSize.heading).fontWeight(TypeWeight.semibold)
          .fontColor(Colors.ink).placeholderColor(Colors.inkMuted).caretColor(Colors.red)
          .accessibilityText('日程名称')
          .backgroundColor(Color.Transparent).borderRadius(0)
          .onFocus(() => { this.titleFocused = true; this.picker = Picker.None; })
          .onBlur(() => { this.titleFocused = false; })
          .onChange((value: string) => { this.titleDraft = value; this.validation = ''; });
        Column()
          .width('100%')
          .height(2)
          .backgroundColor(this.validation.includes('名称')
            ? Colors.red
            : this.titleFocused ? Colors.ink : Color.Transparent);
      }
      .width('100%')
      .backgroundColor(Colors.wash)
      .borderRadius(Radius.card)
      .clip(true);

      Divider().color(Colors.hairline);
      Column() {
        this.TimeRow(Endpoint.Start);
        this.TimeRow(Endpoint.End);
      }.width('100%');
      Text(this.durationLabel())
        .width('100%').textAlign(TextAlign.End).fontSize(TypeSize.meta)
        .fontWeight(this.endAt > this.startAt ? TypeWeight.regular : TypeWeight.semibold)
        .fontColor(this.endAt > this.startAt ? Colors.inkMuted : Colors.red)
        .fontFeature(TABULAR_NUMS);
      Divider().color(Colors.hairline);
      TimelineTagPicker({
        tags: this.tags, selectedId: this.tagId,
        onSelect: (id: string) => { this.tagId = id; },
        onOpen: () => {
          this.picker = Picker.None;
          if (this.titleFocused) this.titleController.stopEditing();
          if (this.noteFocused) this.noteController.stopEditing();
        },
        onCreate: () => { this.newTagPage = true; }
      });
      this.RepeatField();
      this.ReminderField();
      Row() {
        Text('备注').layoutWeight(1).fontSize(TypeSize.body).fontColor(Colors.inkSoft);
        if (this.previewNote) {
          Button('编辑备注', { type: ButtonType.Normal }).constraintSize({ minHeight: 40 })
            .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold).padding({ left: Space.sm, right: Space.sm })
            .fontColor(Colors.ink).backgroundColor(Color.Transparent).borderRadius(Radius.card)
            .onClick(() => this.editNote());
        } else if (this.noteHasLinks) {
          Button('完成', { type: ButtonType.Normal }).constraintSize({ minHeight: 40 })
            .fontSize(TypeSize.body).fontWeight(TypeWeight.semibold).padding({ left: Space.sm, right: Space.sm })
            .accessibilityText('完成备注编辑').fontColor(Colors.ink).backgroundColor(Color.Transparent)
            .borderRadius(Radius.card)
            .onClick(() => { this.noteController.stopEditing(); this.previewNote = true; });
        }
        TimelineAttachmentButton({
          session: this.attachmentSession,
          onAdd: (item: TimelineAttachment) => { this.attachmentDraft = this.attachmentDraft.concat(item); },
          onBusy: (busy: boolean) => { this.importing = busy; this.onAttachmentBusy(busy); }
        });
      }.width('100%');
      this.NoteField();
      if (this.attachmentDraft.length > 0) {
        TimelineAttachmentList({ items: this.attachmentDraft, editable: true,
          onRemove: (id: string) => {
            this.attachmentDraft = this.attachmentDraft.filter((item: TimelineAttachment) => item.id !== id);
          }
        });
      }
    }
    .width('100%')
    .padding({ left: Space.page, right: Space.page, bottom: Space.lg });
  }

  @Builder
  private EventForm() {
    Scroll(this.formScroller) {
      Column() {
        TimelineDatePicker({
          day: this.endpointTime(this.weekEndpoint), expanded: this.picker === Picker.Month,
          blocks: this.blocks, tags: this.tags, caption: this.labelOf(this.weekEndpoint) + '日期',
          onToggle: () => this.openPicker(Picker.Month, this.weekEndpoint),
          onPick: (day: number) => this.pickDay(day)
        });
        this.Toolbar();
        if (this.validation.length > 0 || this.errorMessage.length > 0) {
          Text(this.validation.length > 0 ? this.validation : this.errorMessage)
            .width('100%').padding({ left: Space.page, right: Space.page, bottom: Space.xs })
            .fontSize(TypeSize.meta).fontWeight(TypeWeight.semibold).fontColor(Colors.red);
        }
        this.Fields();
      }.width('100%');
    }
    .align(Alignment.Top).width('100%').height('100%')
    .enabled(!this.saving && !this.importing)
    .backgroundColor(Colors.card);
  }

  build() {
    if (this.newTagPage) {
      TimelineTagForm({
        tags: this.tags, onSaveTag: (tag: TimelineTag) => this.onSaveTag(tag),
        onCancel: () => { this.newTagPage = false; },
        onDone: (id: string) => { this.tagId = id; this.newTagPage = false; }
      });
    } else {
      this.EventForm();
    }
  }
}
