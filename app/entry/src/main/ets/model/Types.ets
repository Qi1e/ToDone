export enum ModuleType {
  EventRecord = 'EventRecord',
  Counter = 'Counter',
  Progress = 'Progress',
  Deadline = 'Deadline',
  Countdown = 'Countdown',
  Note = 'Note',
  Checklist = 'Checklist'
}

export interface Matter {
  id: string;
  title: string;
  description?: string;
  createdAt: number;
  updatedAt: number;
  archived: boolean;
  orderIndex: number;
  clusterId?: string;
  enabledModules: ModuleInstance[];
}

export interface ModuleInstance {
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

export type CounterMode = 'fixed' | 'variable' | 'daily_once';

export interface CounterConfig {
  mode: CounterMode;
  unit?: string;
  fixedSteps?: number[];
}

export interface CounterEntry {
  id: string;
  matterId: string;
  value: number;
  timestamp: number;
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

export interface DeadlineConfig {
  timestamp: number;
  hasTime: boolean;
  location?: string;
}

export interface NoteConfig {
  text: string;
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
  deadlineHasTime?: boolean;
  deadlineLocation?: string;
  note?: string;
}

export interface ModuleOption {
  type: ModuleType;
  label: string;
  description: string;
}
