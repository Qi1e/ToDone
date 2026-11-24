import { copyTimelineAttachments, TimelineRepeat, TimelineTag } from '../contracts/TimelineService';
import {
  ActiveCounterMode,
  AppState,
  ChecklistItem,
  Cluster,
  CounterConfig,
  CreateMatterIntent,
  DayCountMode,
  DeadlineConfig,
  Matter,
  ModuleInstance,
  ModuleOption,
  ModuleType,
  NoteConfig,
  TagConfig,
  TimeSpanMode
} from './Types';

export const CLUSTER_COLORS: string[] = [
  '#2F7BFF',
  '#00A88B',
  '#FF8A3D',
  '#9B6CFF',
  '#E5486D'
];

export const DEFAULT_MATTER_TAGS: TimelineTag[] = [
  { id: 'study', name: '学习', color: '#3B5F86' },
  { id: 'project', name: '项目', color: '#6A5C8C' },
  { id: 'life', name: '生活', color: '#2E6E62' },
  { id: 'urgent', name: '重要', color: '#B84A39' },
  { id: 'exercise', name: '运动', color: '#B9822C' }
];

export function stripTagEmoji(raw: string): string {
  return raw
    .replace(/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE00}-\u{FE0F}\u{200D}]/gu, '')
    .replace(/\s+/g, ' ')
    .trim();
}

export const MODULE_OPTIONS: ModuleOption[] = [
  {
    type: ModuleType.Deadline,
    label: '时间',
    description: '时间段、截止时刻或倒数天数'
  },
  {
    type: ModuleType.Tag,
    label: '标签',
    description: '按颜色分类标记'
  },
  {
    type: ModuleType.Counter,
    label: '计数',
    description: '计次、累加数值或每日打卡'
  },
  {
    type: ModuleType.Note,
    label: '备注',
    description: '文字说明、链接与图文附件'
  },
  {
    type: ModuleType.Checklist,
    label: '列表',
    description: '添加文字或关联事项'
  }
];

export function createId(prefix: string): string {
  return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
}

export function moduleLabel(type: ModuleType): string {
  if (type === ModuleType.Countdown || type === ModuleType.Deadline) {
    return '时间';
  }
  if (type === ModuleType.EventRecord) {
    return '计次';
  }
  const matched = MODULE_OPTIONS.find((item: ModuleOption) => item.type === type);
  return matched ? matched.label : '信息';
}

export function defaultConfigJson(type: ModuleType): string {
  if (type === ModuleType.Counter) {
    const config: CounterConfig = {
      mode: 'tally',
      unit: '次',
      initialValue: 0,
      fixedSteps: [1]
    };
    return JSON.stringify(config);
  }
  if (type === ModuleType.Deadline) {
    const config: DeadlineConfig = {
      span: 'all_day',
      dayCountMode: 'countdown',
      timestamp: Date.now() + 7 * 24 * 60 * 60 * 1000,
      hasTime: false
    };
    return JSON.stringify(config);
  }
  if (type === ModuleType.Tag) {
    const config: TagConfig = { tagId: '' };
    return JSON.stringify(config);
  }
  if (type === ModuleType.Note) {
    const config: NoteConfig = {
      text: ''
    };
    return JSON.stringify(config);
  }
  return '{}';
}

export function createModuleInstance(matterId: string, type: ModuleType): ModuleInstance {
  const now = Date.now();
  return {
    id: createId('module'),
    matterId,
    moduleType: type,
    configJson: defaultConfigJson(type),
    createdAt: now,
    updatedAt: now
  };
}

export function createMatter(intent: CreateMatterIntent, orderIndex: number, id: string = createId('matter')): Matter {
  const now = Date.now();
  const trimmedDesc = intent.description?.trim();
  const matter: Matter = {
    id,
    title: intent.title.trim(),
    description: trimmedDesc && trimmedDesc.length > 0 ? trimmedDesc : undefined,
    createdAt: now,
    updatedAt: now,
    archived: false,
    orderIndex,
    enabledModules: []
  };

  const selectedTypes = intent.enabledModuleTypes ?? [];
  const hasDeadline = selectedTypes.includes(ModuleType.Deadline) || intent.deadlineTimestamp !== undefined;
  if (hasDeadline) {
    const startAt = intent.deadlineTimestamp ?? now;
    let span: TimeSpanMode | undefined = intent.deadlineSpan;
    if (!span && intent.deadlineEndAt !== undefined && intent.deadlineEndAt > startAt) {
      span = 'range';
    }
    let dayCountMode: DayCountMode | undefined = intent.dayCountMode;
    if (!dayCountMode && intent.deadlineMode) {
      dayCountMode = intent.deadlineMode === 'elapsed' ? 'elapsed' : 'countdown';
    }
    const hasTime = span ? (span === 'range' || span === 'point')
      : ((intent.deadlineMode ?? 'deadline') === 'deadline' && (intent.deadlineHasTime ?? false));
    const deadline: DeadlineConfig = {
      timestamp: startAt,
      endAt: span === 'range' ? intent.deadlineEndAt : undefined,
      span,
      dayCountMode,
      mode: intent.deadlineMode,
      hasTime,
      location: intent.deadlineLocation?.trim() || undefined,
      reminderMinutes: intent.reminderMinutes,
      repeat: intent.repeat && intent.repeat !== TimelineRepeat.None ? intent.repeat : undefined
    };
    const deadlineModule = createModuleInstance(matter.id, ModuleType.Deadline);
    deadlineModule.configJson = JSON.stringify(deadline);
    matter.enabledModules.push(deadlineModule);
  }

  const tagId = intent.tagId?.trim() ?? '';
  if (selectedTypes.includes(ModuleType.Tag) || tagId.length > 0) {
    matter.tagId = tagId || undefined;
    const tagModule = createModuleInstance(matter.id, ModuleType.Tag);
    const tagConfig: TagConfig = { tagId };
    tagModule.configJson = JSON.stringify(tagConfig);
    matter.enabledModules.push(tagModule);
  }

  const wantsCounter = selectedTypes.includes(ModuleType.Counter) ||
    selectedTypes.includes(ModuleType.EventRecord) || intent.counterMode !== undefined;
  if (wantsCounter) {
    const mode: ActiveCounterMode = intent.counterMode ??
      (selectedTypes.includes(ModuleType.EventRecord) && !selectedTypes.includes(ModuleType.Counter) ? 'tally' : 'amount');
    const counterModule = createModuleInstance(matter.id, ModuleType.Counter);
    const steps = intent.counterSteps && intent.counterSteps.length > 0
      ? intent.counterSteps
      : (mode === 'amount' ? [1, 10] : [1]);
    const counterConfig: CounterConfig = {
      mode,
      unit: intent.counterUnit?.trim() || (mode === 'tally' ? '次' : undefined),
      initialValue: intent.counterInitial ?? 0,
      fixedSteps: steps
    };
    counterModule.configJson = JSON.stringify(counterConfig);
    matter.enabledModules.push(counterModule);
  }

  selectedTypes.forEach((type: ModuleType) => {
    if (type === ModuleType.Deadline || type === ModuleType.Countdown || type === ModuleType.Progress ||
      type === ModuleType.Note || type === ModuleType.Tag || type === ModuleType.Counter ||
      type === ModuleType.EventRecord) {
      return;
    }
    matter.enabledModules.push(createModuleInstance(matter.id, type));
  });

  const attachments = copyTimelineAttachments(intent.attachments);
  if (selectedTypes.includes(ModuleType.Note) || (intent.note && intent.note.trim().length > 0) ||
    (attachments && attachments.length > 0)) {
    const note = createModuleInstance(matter.id, ModuleType.Note);
    const config: NoteConfig = {
      text: intent.note?.trim() ?? '',
      attachments
    };
    note.configJson = JSON.stringify(config);
    matter.enabledModules.push(note);
  }

  return matter;
}

interface DeckExample {
  id: string;
  intent: CreateMatterIntent;
  items?: string[];
}

// 固定的示例 ID 只用于按需补齐，改名、排序或归档后仍能认出原卡。
export function appendDeckExamples(state: AppState): number {
  const due = new Date();
  due.setDate(due.getDate() + 3);
  due.setHours(9, 0, 0, 0);
  const dueEnd = due.getTime() + 90 * 60 * 1000;
  const examples: DeckExample[] = [
    { id: 'sample_presentation', intent: { title: '课程汇报',
      enabledModuleTypes: [ModuleType.Deadline, ModuleType.Tag, ModuleType.Checklist, ModuleType.Note],
      deadlineTimestamp: due.getTime(), deadlineEndAt: dueEnd, deadlineSpan: 'range', dayCountMode: 'countdown',
      tagId: 'study', note: '准备五分钟讲稿，先讲问题再放两张对比图。' }, items: ['核对图表', '计时试讲'] },
    { id: 'sample_listening', intent: { title: '听力跟读',
      enabledModuleTypes: [ModuleType.Counter, ModuleType.Note], counterMode: 'daily_once',
      note: '午休听一段材料，跟读两遍。' } },
    { id: 'sample_groceries', intent: { title: '周末采购',
      enabledModuleTypes: [ModuleType.Checklist] }, items: ['燕麦', '牛奶', '洗衣液'] },
    { id: 'sample_photowalk', intent: { title: '摄影散步',
      enabledModuleTypes: [ModuleType.Counter, ModuleType.Note], counterMode: 'tally', counterUnit: '次',
      note: '沿河走到人行桥，从西门出发记录日落机位。' } }
  ];
  const next = state.matters.reduce((max: number, matter: Matter) => Math.max(max, matter.orderIndex), -1) + 1;
  let added = 0;
  examples.forEach((example: DeckExample) => {
    if (state.matters.some((matter: Matter) => matter.id === example.id)) return;
    const matter = createMatter(example.intent, next + added, example.id);
    state.matters.push(matter);
    example.items?.forEach((title: string, index: number) => {
      state.checklistItems.push({ id: createId('check'), matterId: matter.id, title, completed: false,
        entryType: 'text', orderIndex: index, createdAt: matter.createdAt, updatedAt: matter.createdAt });
    });
    added++;
  });
  return added;
}

export function createSeedState(): AppState {
  const now = Date.now();
  const fitness = createMatter({
    title: '健身',
    enabledModuleTypes: [ModuleType.Counter, ModuleType.Note],
    counterMode: 'tally',
    counterUnit: '次',
    note: '记录每次训练与身体状态。'
  }, 0);

  const examDate = new Date(now + 30 * 24 * 60 * 60 * 1000);
  examDate.setHours(9, 0, 0, 0);
  const exam = createMatter({
    title: '六级考试',
    enabledModuleTypes: [ModuleType.Deadline, ModuleType.Tag, ModuleType.Note],
    deadlineTimestamp: examDate.getTime(),
    deadlineEndAt: examDate.getTime() + 140 * 60 * 1000,
    deadlineSpan: 'range',
    dayCountMode: 'countdown',
    tagId: 'study',
    note: '带身份证、准考证与听力耳机，提前 30 分钟到场。'
  }, 1);

  const bookList = createMatter({
    title: '书单',
    enabledModuleTypes: [ModuleType.Checklist]
  }, 2);

  const cluster: Cluster = {
    id: createId('cluster'),
    color: CLUSTER_COLORS[0],
    createdAt: now,
    updatedAt: now
  };
  exam.clusterId = cluster.id;

  const checklistItems: ChecklistItem[] = [
    {
      id: createId('check'),
      matterId: bookList.id,
      title: '三体',
      completed: true,
      entryType: 'text',
      orderIndex: 0,
      createdAt: now,
      updatedAt: now
    },
    {
      id: createId('check'),
      matterId: bookList.id,
      title: '活着',
      completed: false,
      entryType: 'text',
      orderIndex: 1,
      createdAt: now,
      updatedAt: now
    },
    {
      id: createId('check'),
      matterId: bookList.id,
      title: '百年孤独',
      completed: false,
      entryType: 'text',
      orderIndex: 2,
      createdAt: now,
      updatedAt: now
    }
  ];

  const state: AppState = {
    matters: [fitness, exam, bookList],
    clusters: [cluster],
    tags: DEFAULT_MATTER_TAGS.map((tag: TimelineTag): TimelineTag => ({ id: tag.id, name: tag.name, color: tag.color })),
    eventRecords: [],
    counterEntries: [],
    checklistItems,
    singleCardMatterId: fitness.id,
    summaryCardMatterIds: [fitness.id, exam.id, bookList.id],
    cardFormIds: []
  };
  appendDeckExamples(state);
  return state;
}
