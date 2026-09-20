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
    label: '截止日期',
    description: '设置日期，自动显示倒计时'
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

  const selectedTypes = intent.enabledModuleTypes ?? [];
  const hasDeadline = selectedTypes.includes(ModuleType.Deadline) || intent.deadlineTimestamp !== undefined;
  if (hasDeadline) {
    const deadline: DeadlineConfig = {
      timestamp: intent.deadlineTimestamp ?? Date.now(),
      hasTime: intent.deadlineHasTime ?? false,
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

  return {
    matters: [fitness, exam, bookList],
    clusters: [cluster],
    eventRecords: [],
    counterEntries: [],
    checklistItems,
    singleCardMatterId: fitness.id,
    summaryCardMatterIds: [fitness.id, exam.id, bookList.id],
    cardFormIds: []
  };
}
