import {
  AppState,
  ChecklistItem,
  Cluster,
  CreateMatterIntent,
  DeadlineConfig,
  Matter,
  ModuleInstance,
  ModuleOption,
  ModuleType,
  NoteConfig
} from './Types';

export const CLUSTER_COLORS: string[] = [
  '#2F7BFF',
  '#00A88B',
  '#FF8A3D',
  '#9B6CFF',
  '#E5486D'
];

export const MODULE_OPTIONS: ModuleOption[] = [
  {
    type: ModuleType.EventRecord,
    label: '记录',
    description: '记录某件事发生的时刻'
  },
  {
    type: ModuleType.Counter,
    label: '计数',
    description: '累加数值或每日一次'
  },
  {
    type: ModuleType.Deadline,
    label: '日期与天数',
    description: '倒数日、正数日或截止时间'
  },
  {
    type: ModuleType.Note,
    label: '备注',
    description: '自由文本说明'
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
  const matched = MODULE_OPTIONS.find((item: ModuleOption) => item.type === type);
  if (type === ModuleType.Countdown) {
    return '截止日期';
  }
  return matched ? matched.label : '信息';
}

export function defaultConfigJson(type: ModuleType): string {
  if (type === ModuleType.Counter) {
    return JSON.stringify({
      mode: 'fixed',
      unit: '次',
      fixedSteps: [1, 10]
    });
  }
  if (type === ModuleType.Deadline) {
    const config: DeadlineConfig = {
      timestamp: Date.now() + 7 * 24 * 60 * 60 * 1000,
      hasTime: false
    };
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
  const matter: Matter = {
    id,
    title: intent.title.trim(),
    description: intent.description?.trim(),
    createdAt: now,
    updatedAt: now,
    archived: false,
    orderIndex,
    enabledModules: []
  };

  const selectedTypes = intent.enabledModuleTypes ?? [];
  const hasDeadline = selectedTypes.includes(ModuleType.Deadline) || intent.deadlineTimestamp !== undefined;
  if (hasDeadline) {
    const deadline: DeadlineConfig = {
      timestamp: intent.deadlineTimestamp ?? Date.now(),
      mode: intent.deadlineMode ?? 'deadline',
      hasTime: (intent.deadlineMode ?? 'deadline') === 'deadline' && (intent.deadlineHasTime ?? false),
      location: intent.deadlineLocation?.trim()
    };
    const deadlineModule = createModuleInstance(matter.id, ModuleType.Deadline);
    deadlineModule.configJson = JSON.stringify(deadline);
    matter.enabledModules.push(deadlineModule);
    matter.enabledModules.push(createModuleInstance(matter.id, ModuleType.Countdown));
  }

  selectedTypes.forEach((type: ModuleType) => {
    if (type === ModuleType.Deadline || type === ModuleType.Countdown || type === ModuleType.Progress || type === ModuleType.Note) {
      return;
    }
    matter.enabledModules.push(createModuleInstance(matter.id, type));
  });

  if (selectedTypes.includes(ModuleType.Note) || (intent.note && intent.note.trim().length > 0)) {
    const note = createModuleInstance(matter.id, ModuleType.Note);
    const config: NoteConfig = {
      text: intent.note?.trim() ?? ''
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
  const examples: DeckExample[] = [
    { id: 'sample_presentation', intent: { title: '课程汇报', description: '准备五分钟讲稿和两张对比图',
      enabledModuleTypes: [ModuleType.Deadline, ModuleType.Checklist, ModuleType.Note],
      deadlineTimestamp: due.getTime(), note: '先讲问题，再放两张对比图。' }, items: ['核对图表', '计时试讲'] },
    { id: 'sample_listening', intent: { title: '听力跟读', description: '午休听一段材料，跟读两遍',
      enabledModuleTypes: [ModuleType.EventRecord, ModuleType.Counter] } },
    { id: 'sample_groceries', intent: { title: '周末采购', description: '去超市前看一眼清单',
      enabledModuleTypes: [ModuleType.Checklist] }, items: ['燕麦', '牛奶', '洗衣液'] },
    { id: 'sample_photowalk', intent: { title: '摄影散步', description: '沿河走到人行桥，记录日落的机位',
      enabledModuleTypes: [ModuleType.EventRecord, ModuleType.Note], note: '从西门出发，日落前到桥边。' } }
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
    description: '记录运动次数和关键时刻',
    enabledModuleTypes: [ModuleType.EventRecord, ModuleType.Counter, ModuleType.Note]
  }, 0);

  const exam = createMatter({
    title: '六级考试',
    description: '考试信息和准备事项',
    enabledModuleTypes: [ModuleType.Deadline, ModuleType.Note],
    deadlineTimestamp: Date.now() + 30 * 24 * 60 * 60 * 1000
  }, 1);

  const bookList = createMatter({
    title: '书单',
    description: '想读和已读的书',
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
