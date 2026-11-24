import { TimelineAttachment, TimelineOverride, TimelineRepeat, TimelineTag } from '../contracts/TimelineService';

export enum ModuleType {
  EventRecord = 'EventRecord',
  Counter = 'Counter',
  Progress = 'Progress',
  Deadline = 'Deadline',
  Countdown = 'Countdown',
  Tag = 'Tag',
  Note = 'Note',
  Checklist = 'Checklist'
}

export interface Matter {
  lastEditorToken?: string;
  id: string;
  title: string;
  description?: string;
  tagId?: string;
  createdAt: number;
  updatedAt: number;
  archived: boolean;
  orderIndex: number;
  clusterId?: string;
  disabledModules?: ModuleInstance[];
  enabledModules: ModuleInstance[];
}

export interface ModuleInstance {
  name?: string;
  id: string;
  matterId: string;
  moduleType: ModuleType;
  configJson: string;
  createdAt: number;
  updatedAt: number;
}

export interface Cluster {
  id: string;
  color: string;
  createdAt: number;
  updatedAt: number;
}

export interface EventRecordEntry {
  id: string;
  matterId: string;
  timestamp: number;
  note?: string;
}

export type ActiveCounterMode = 'tally' | 'amount' | 'daily_once';
export type CounterMode = ActiveCounterMode | 'fixed' | 'variable';

export interface CounterConfig {
  mode: CounterMode;
  unit?: string;
  initialValue?: number;
  fixedSteps?: number[];
}

export interface CounterEntry {
  id: string;
  matterId: string;
  value: number;
  timestamp: number;
  note?: string;
}

export type ProgressMode = 'manual_percent' | 'target_value';

export interface ProgressConfig {
  mode: ProgressMode;
  percent?: number;
  currentValue?: number;
  targetValue?: number;
  unit?: string;
  linkedCounterModuleId?: string;
}

export type DateMode = 'deadline' | 'countdown' | 'elapsed';
export type TimeSpanMode = 'all_day' | 'range' | 'point';
export type DayCountMode = 'none' | 'countdown' | 'elapsed';

export interface DeadlineConfig {
  mode?: DateMode;
  span?: TimeSpanMode;
  dayCountMode?: DayCountMode;
  timestamp: number;
  endAt?: number;
  hasTime: boolean;
  location?: string;
  reminderMinutes?: number;
  repeat?: TimelineRepeat;
  repeatFromDay?: number;
  repeatUntilDay?: number;
  excludedDays?: number[];
  overrides?: TimelineOverride[];
}

export interface TagConfig {
  tagId: string;
}

export interface NoteConfig {
  text: string;
  attachments?: TimelineAttachment[];
}

export interface ChecklistItem {
  id: string;
  matterId: string;
  title: string;
  completed: boolean;
  entryType?: 'text' | 'matter_ref';
  targetMatterId?: string;
  orderIndex: number;
  createdAt: number;
  updatedAt: number;
}

export interface AppState {
  matters: Matter[];
  clusters: Cluster[];
  tags?: TimelineTag[];
  timelineImported?: boolean;
  eventRecords: EventRecordEntry[];
  counterEntries: CounterEntry[];
  checklistItems: ChecklistItem[];
  singleCardMatterId: string;
  summaryCardMatterIds: string[];
  cardFormIds: string[];
}

export interface CreateMatterIntent {
  title: string;
  description?: string;
  enabledModuleTypes?: ModuleType[];
  deadlineTimestamp?: number;
  deadlineEndAt?: number;
  deadlineSpan?: TimeSpanMode;
  dayCountMode?: DayCountMode;
  deadlineMode?: DateMode;
  deadlineHasTime?: boolean;
  deadlineLocation?: string;
  reminderMinutes?: number;
  repeat?: TimelineRepeat;
  tagId?: string;
  counterMode?: ActiveCounterMode;
  counterUnit?: string;
  counterInitial?: number;
  counterSteps?: number[];
  note?: string;
  attachments?: TimelineAttachment[];
}

export interface ModuleOption {
  type: ModuleType;
  label: string;
  description: string;
}
