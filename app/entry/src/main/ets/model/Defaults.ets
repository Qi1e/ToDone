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
  NoteConfig,
  ProgressConfig
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
    label: '事件记录',
    description: '记录某件事发生的时刻'
  },
  {
    type: ModuleType.Counter,
    label: '计数',
    description: '累加数值或每日一次'
  },
  {
    type: ModuleType.Progress,
    label: '进度',
    description: '展示手动百分比'
  },
  {
    type: ModuleType.Deadline,
    label: '截止日期',
    description: '记录关键日期和地点'
  },
  {
    type: ModuleType.Countdown,
    label: '倒计时',
    description: '根据截止日期计算剩余天数'
  },
  {
    type: ModuleType.Note,
    label: '备注',
    description: '自由文本说明'
  },
  {
    type: ModuleType.Checklist,
    label: '列表',
    description: '简单条目和完成状态'
  }
];

export function createId(prefix: string): string {
  return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
}

export function moduleLabel(type: ModuleType): string {
  const matched = MODULE_OPTIONS.find((item: ModuleOption) => item.type === type);
  return matched ? matched.label : '模块';
}

export function defaultConfigJson(type: ModuleType): string {
  if (type === ModuleType.Counter) {
    return JSON.stringify({
      mode: 'fixed',
      unit: '次',
      fixedSteps: [1, 10]
    });
  }
  if (type === ModuleType.Progress) {
    const config: ProgressConfig = {
      mode: 'manual_percent',
      percent: 0
    };
    return JSON.stringify(config);
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

export function createMatter(intent: CreateMatterIntent, orderIndex: number): Matter {
  const now = Date.now();
  const matter: Matter = {
    id: createId('matter'),
    title: intent.title.trim(),
    description: intent.description?.trim(),
    createdAt: now,
    updatedAt: now,
    archived: false,
    orderIndex,
    enabledModules: []
  };

  if (intent.deadlineTimestamp) {
    matter.enabledModules.push(createModuleInstance(matter.id, ModuleType.Deadline));
    matter.enabledModules.push(createModuleInstance(matter.id, ModuleType.Countdown));
  }

  if (intent.note && intent.note.trim().length > 0) {
    const note = createModuleInstance(matter.id, ModuleType.Note);
    const config: NoteConfig = {
      text: intent.note.trim()
    };
    note.configJson = JSON.stringify(config);
    matter.enabledModules.push(note);
  }

  return matter;
}

export function createSeedState(): AppState {
  const now = Date.now();
  const fitness = createMatter({ title: '健身', description: '记录运动次数和关键时刻' }, 0);
  fitness.enabledModules = [
    createModuleInstance(fitness.id, ModuleType.EventRecord),
    createModuleInstance(fitness.id, ModuleType.Counter),
    createModuleInstance(fitness.id, ModuleType.Note)
  ];

  const exam = createMatter({ title: '六级考试', description: '考试信息和准备进度' }, 1);
  exam.enabledModules = [
    createModuleInstance(exam.id, ModuleType.Deadline),
    createModuleInstance(exam.id, ModuleType.Countdown),
    createModuleInstance(exam.id, ModuleType.Progress),
    createModuleInstance(exam.id, ModuleType.Note)
  ];

  const bookList = createMatter({ title: '书单', description: '想读和已读的书' }, 2);
  bookList.enabledModules = [
    createModuleInstance(bookList.id, ModuleType.Checklist),
    createModuleInstance(bookList.id, ModuleType.Progress)
  ];

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
      orderIndex: 0,
      createdAt: now,
      updatedAt: now
    },
    {
      id: createId('check'),
      matterId: bookList.id,
      title: '活着',
      completed: false,
      orderIndex: 1,
      createdAt: now,
      updatedAt: now
    },
    {
      id: createId('check'),
      matterId: bookList.id,
      title: '百年孤独',
      completed: false,
      orderIndex: 2,
      createdAt: now,
      updatedAt: now
    }
  ];

  return {
    matters: [fitness, exam, bookList],
    clusters: [cluster],
    eventRecords: [],
    counterEntries: [],
    checklistItems
  };
}

