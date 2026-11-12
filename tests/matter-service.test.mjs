import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { loadPortableEts } from '../scripts/load-portable-ets.mjs';

const bundle = await loadPortableEts();
after(() => bundle.close());
const { ModuleType } = bundle.modules['model/Types'];
const { DefaultMatterService } = bundle.modules['domain/DefaultMatterService'];
const { MockMatterService, MemoryMatterRepository } = bundle.modules['mocks/MockMatterService'];
const { canLinkMatterInState } = bundle.modules['domain/MatterLinks'];

function emptyState() {
  return { matters: [], clusters: [], eventRecords: [], counterEntries: [], checklistItems: [],
    singleCardMatterId: '', summaryCardMatterIds: [], cardFormIds: [] };
}
function fixture() {
  const repository = new MemoryMatterRepository(emptyState());
  return { repository, service: new DefaultMatterService(repository) };
}
const request = (title, extra = {}) => ({ intent: { title, ...extra } });

test('只填名称也能创建；返回数据与仓库快照互不污染', async () => {
  const { service, repository } = fixture();
  const result = await service.createMatter(request('  新事项  '));
  assert.equal(result.success, true);
  assert.equal(service.findMatter(result.matterId).title, '新事项');
  assert.equal(service.findMatter(result.matterId).enabledModules.length, 0);
  const state = repository.readState();
  state.matters[0].title = '外部修改';
  assert.equal(service.activeMatters()[0].title, '新事项');
});

test('无效输入不留下部分事项、列表项或引用', async () => {
  const { service, repository } = fixture();
  const bad = [request(' '), request('日期', { enabledModuleTypes: [ModuleType.Deadline] }),
    request('日期', { deadlineTimestamp: Number.NaN }),
    { ...request('子事项'), ownerMatterId: 'missing' },
    { ...request('列表'), checklistTitles: ['孤立项'] }];
  for (const input of bad) assert.equal((await service.createMatter(input)).success, false);
  assert.deepEqual(repository.readState(), emptyState());
});

test('截止日期派生倒计时，备注和文字列表一次提交', async () => {
  const { service, repository } = fixture();
  const result = await service.createMatter({
    intent: { title: '考试', enabledModuleTypes: [ModuleType.Deadline, ModuleType.Note, ModuleType.Checklist],
      deadlineTimestamp: 1800000000000, deadlineHasTime: false, note: '  带证件  ' },
    checklistTitles: ['  报名  ', '', '打印准考证']
  });
  assert.equal(result.success, true);
  const matter = service.findMatter(result.matterId);
  assert.deepEqual(matter.enabledModules.map(m => m.moduleType),
    [ModuleType.Deadline, ModuleType.Countdown, ModuleType.Checklist, ModuleType.Note]);
  assert.equal(JSON.parse(matter.enabledModules.find(m => m.moduleType === ModuleType.Note).configJson).text, '带证件');
  assert.deepEqual(repository.readState().checklistItems.map(i => [i.title, i.orderIndex]),
    [['报名', 0], ['打印准考证', 1]]);
});

test('创建关联事项保持一层引用，禁止继续引用或重复引用', async () => {
  const { service, repository } = fixture();
  const owner = await service.createMatter(request('主事项', { enabledModuleTypes: [ModuleType.Checklist] }));
  const child = await service.createMatter({ ...request('子事项', { enabledModuleTypes: [ModuleType.Checklist] }),
    ownerMatterId: owner.matterId });
  assert.equal(child.success, true);
  assert.equal(repository.readState().checklistItems[0].targetMatterId, child.matterId);
  const rejected = await service.createMatter({ ...request('孙事项'), ownerMatterId: child.matterId });
  assert.equal(rejected.errorCode, 'invalid_owner');
  assert.equal(service.activeMatters().length, 2);
  assert.equal(canLinkMatterInState(repository.readState(), owner.matterId, child.matterId), false);
  assert.equal(canLinkMatterInState(repository.readState(), owner.matterId, owner.matterId), false);
});

test('归档或没有列表能力的主事项不能接收新引用', async () => {
  const { service, repository } = fixture();
  const owner = await service.createMatter(request('普通事项'));
  assert.equal((await service.createMatter({ ...request('子项'), ownerMatterId: owner.matterId })).success, false);
  const state = repository.readState();
  state.matters[0].archived = true;
  await repository.commitState(state);
  assert.equal(service.activeMatters().length, 0);
  assert.equal(service.archivedMatters().length, 1);
  assert.equal((await service.createMatter({ ...request('子项'), ownerMatterId: owner.matterId })).success, false);
});

test('保存失败后重试同一事项，不重复创建或重复添加列表项', async () => {
  class FailingRepository extends MemoryMatterRepository {
    failures = 1;
    async commitState(state) {
      await super.commitState(state);
      if (this.failures-- > 0) throw new Error('模拟 flush 失败');
    }
  }
  const repository = new FailingRepository(emptyState());
  const service = new DefaultMatterService(repository);
  const failed = await service.createMatter({ ...request('待保存', { enabledModuleTypes: [ModuleType.Checklist] }),
    checklistTitles: ['一次'] });
  assert.equal(failed.success, false);
  assert.equal(failed.errorCode, 'save_failed');
  assert.ok(failed.matterId);
  assert.equal((await service.retrySave(failed.matterId)).success, true);
  assert.equal(service.activeMatters().length, 1);
  assert.equal(repository.readState().checklistItems.length, 1);
  assert.equal((await service.retrySave('deleted')).errorCode, 'missing_matter');
});

test('写入开始前失败不会虚构已创建的事项', async () => {
  const repository = new MemoryMatterRepository(emptyState());
  repository.commitState = async () => { throw new Error('存储不可用'); };
  const service = new DefaultMatterService(repository);
  const failed = await service.createMatter(request('失败'));
  assert.equal(failed.matterId, '');
  assert.equal(service.activeMatters().length, 0);
});

test('Mock 实例互相隔离，复用真实业务规则且不依赖设备', async () => {
  const first = new MockMatterService(emptyState());
  const second = new MockMatterService(emptyState());
  assert.equal((await first.createMatter(request('预览'))).success, true);
  assert.equal(first.activeMatters().length, 1);
  assert.equal(second.activeMatters().length, 0);
  assert.equal((await first.createMatter(request(' '))).errorCode, 'invalid_title');
});

test('日期用途兼容旧配置，按本地日历计算，到分钟判断逾期', async () => {
  const { dateSummary } = bundle.modules['common/DateFormat'];
  const now = new Date(2026, 10, 12, 10, 0).getTime();
  const yesterday = new Date(2026, 10, 11, 23, 59).getTime();
  assert.equal(dateSummary({ mode: 'elapsed', timestamp: yesterday }, now), '已过 1 天');
  assert.equal(dateSummary({ mode: 'elapsed', timestamp: now }, now), '已过 0 天');
  assert.equal(dateSummary({ mode: 'countdown', timestamp: yesterday }, now), '已过去 1 天');
  assert.match(dateSummary({ timestamp: now - 60000, hasTime: true }, now), /09:59 截止 · 已逾期/);
  assert.match(dateSummary({ timestamp: now - 60000, hasTime: false }, now), /今天截止/);
  const { service } = fixture();
  const result = await service.createMatter(request('开始', { deadlineMode: 'elapsed', deadlineTimestamp: 0 }));
  const saved = service.findMatter(result.matterId).enabledModules.find(m => m.moduleType === ModuleType.Deadline);
  assert.equal(JSON.parse(saved.configJson).mode, 'elapsed');
  const future = await service.createMatter(request('未来', { deadlineMode: 'elapsed', deadlineTimestamp: Date.now() + 172800000 }));
  assert.equal(future.errorCode, 'invalid_deadline');
});

test('共享表单创建并挂到原列表；重放保存和末项自动加入均不重复', async () => {
  const { service, repository } = fixture();
  const owner = await service.createMatter(request('原列表', { enabledModuleTypes: [ModuleType.Checklist] }));
  const draft = service.loadEditor('');
  Object.assign(draft, { title: '子事项', types: [ModuleType.Checklist, ModuleType.Counter], pending: '最后一项',
    initial: '2', step: '0.5', token: 'save-1' });
  for (let i = 0; i < 2; i++) assert.equal((await service.saveEditor(draft, owner.matterId)).success, true);
  const state = repository.readState();
  assert.equal(state.matters.length, 2);
  assert.deepEqual(state.checklistItems.map(i => i.title), ['最后一项', '子事项']);
  assert.equal(service.loadEditor(draft.id).step, '0.5');
});

test('编辑保留计数、记录、列表完成状态和隐藏配置；解除引用不删除目标', async () => {
  const { service, repository } = fixture();
  const target = await service.createMatter(request('关联目标'));
  const draft = service.loadEditor('');
  Object.assign(draft, { title: '事项', types: [ModuleType.Counter, ModuleType.Checklist, ModuleType.EventRecord],
    initial: '3', step: '2', recordName: '打卡', items: [
      { id: 'item', title: '文字' }, { id: 'ref', title: '关联目标', targetId: target.matterId }] });
  assert.equal((await service.saveEditor(draft, '')).success, true);
  const edit = service.loadEditor(draft.id);
  const state = repository.readState();
  state.checklistItems[0].completed = true;
  state.counterEntries.push({ id: 'count', matterId: draft.id, value: 5, timestamp: 42 });
  state.eventRecords.push({ id: 'record', matterId: draft.id, timestamp: 42 });
  await repository.commitState(state);
  edit.title = '新名称';
  edit.types = [ModuleType.Checklist];
  edit.items = [{ id: 'item', title: '新文字' }];
  assert.equal((await service.saveEditor(edit, '')).success, true);
  const saved = repository.readState();
  assert.equal(saved.checklistItems.length, 1);
  assert.equal(saved.checklistItems[0].completed, true);
  assert.deepEqual(saved.counterEntries, state.counterEntries);
  assert.deepEqual(saved.eventRecords, state.eventRecords);
  assert.ok(service.findMatter(target.matterId));
  const restored = service.loadEditor(draft.id);
  assert.equal(restored.step, '2');
  assert.equal(restored.recordName, '打卡');
  restored.types.push(ModuleType.Counter, ModuleType.EventRecord);
  assert.equal((await service.saveEditor(restored, '')).success, true);
  assert.equal(service.findMatter(draft.id).disabledModules.length, 0);
});

test('旧编辑草稿、无效引用或计数均不覆盖原事项', async () => {
  const { service, repository } = fixture();
  const { matterId } = await service.createMatter(request('原事项'));
  const first = service.loadEditor(matterId);
  const stale = service.loadEditor(matterId);
  first.title = '新名称';
  assert.equal((await service.saveEditor(first, '')).success, true);
  stale.title = '过期名称';
  const baseline = repository.readState();
  assert.equal((await service.saveEditor(stale, '')).success, false);
  const edit = service.loadEditor(matterId);
  edit.types = [ModuleType.Checklist];
  edit.items = [{ id: 'bad', targetId: matterId, title: '引用自身' }];
  assert.equal((await service.saveEditor(edit, '')).success, false);
  edit.types = [ModuleType.Counter];
  edit.step = '0';
  assert.equal((await service.saveEditor(edit, '')).success, false);
  assert.deepEqual(repository.readState(), baseline);
});

test('共享表单 flush 失败后用恢复的草稿重试', async () => {
  class FailOnce extends MemoryMatterRepository {
    fail = true;
    async commitState(state) {
      await super.commitState(state);
      if (this.fail) { this.fail = false; throw new Error('flush'); }
    }
  }
  const service = new DefaultMatterService(new FailOnce(emptyState()));
  const draft = service.loadEditor('');
  Object.assign(draft, { title: '重试', types: [ModuleType.Checklist], pending: '文字', token: 'stable' });
  const savedDraft = JSON.stringify(draft);
  assert.equal((await service.saveEditor(draft, '')).success, false);
  assert.equal((await service.saveEditor(JSON.parse(savedDraft), '')).success, true);
  assert.equal(service.activeMatters().length, 1);
  assert.equal(service.loadEditor(draft.id).items.length, 1);
});
