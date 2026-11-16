import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { loadPortableEts } from '../scripts/load-portable-ets.mjs';

const bundle = await loadPortableEts();
after(() => bundle.close());
const { DefaultTimelineService } = bundle.modules['domain/DefaultTimelineService'];
const block = { id: 'review', title: '评审', startAt: 1, endAt: 2, note: '带上纪要' };
const tag = { id: 'team', name: '🪴 合作', color: '#33b3ab' };

class MemoryStorage {
  text = '';
  read() { return this.text; }
  async write(text) { this.text = text; }
}

test('旧日程数组按需迁移，标签跨重启保留；清除标签只解除该日程引用', async () => {
  const storage = new MemoryStorage();
  storage.text = JSON.stringify([block]);
  const old = storage.text;
  const service = new DefaultTimelineService(storage);
  assert.equal(storage.text, old);
  assert.deepEqual(service.list(), [block]);
  const presetIds = service.listTags().map(item => item.id);
  await service.saveTag({ ...tag, name: '  ' + tag.name + '  ' });
  await service.save({ ...block, tagId: tag.id });
  const reopen = new DefaultTimelineService(storage);
  assert.deepEqual(reopen.list(), [{ ...block, tagId: tag.id }]);
  const tags = reopen.listTags();
  assert.deepEqual(tags.map(item => item.id), [tag.id, ...presetIds]);
  assert.deepEqual(tags[0], { ...tag, color: tag.color.toUpperCase() });
  tags[0].name = '意外修改';
  assert.equal(reopen.listTags()[0].name, tag.name);
  await reopen.save({ ...block, tagId: undefined });
  assert.deepEqual(reopen.list(), [block]);
  assert.deepEqual(reopen.listTags().map(item => item.id), [...presetIds, tag.id]);
});

test('标签与日程共用队列，失败重试不重复，同名新建和无效引用不破坏已保存快照', async () => {
  const storage = new MemoryStorage();
  const service = new DefaultTimelineService(storage);
  let failOnce = true;
  storage.write = async text => {
    storage.text = text;
    if (failOnce) { failOnce = false; throw new Error('flush'); }
  };
  await assert.rejects(service.saveTag(tag));
  assert.equal(service.listTags().some(item => item.id === tag.id), false);
  await Promise.all([service.saveTag(tag), service.save({ ...block, tagId: tag.id }), service.saveTag(tag)]);
  const before = storage.text;
  const saved = service.listTags();
  assert.equal(saved.filter(item => item.id === tag.id).length, 1);
  for (const edit of [{ color: 'red' }, { color: '#z23bcd' }, { name: '   ' }, { id: '' },
    { id: 'other', name: ' ' + tag.name + ' ' }]) {
    await assert.rejects(service.saveTag({ ...tag, ...edit }));
  }
  await assert.rejects(service.save({ ...block, tagId: 'missing' }));
  assert.equal(storage.text, before);
  assert.deepEqual(new DefaultTimelineService(storage).listTags(), saved);
  const renamed = { ...tag, name: '👥 小组', color: '#ABCDEF' };
  await service.saveTag(renamed);
  assert.deepEqual(service.listTags()[0], renamed);
  assert.equal(service.list()[0].tagId, tag.id);
});

test('标签存档出现未知版本、悬空引用或重复 ID 时保留原始字节', () => {
  const storage = new MemoryStorage();
  for (const snapshot of [
    { version: 7, blocks: [], tags: [] },
    { version: 2, blocks: [{ ...block, tagId: tag.id }], tags: [] },
    { version: 2, blocks: [], tags: [tag, tag] }
  ]) {
    const before = JSON.stringify(snapshot);
    storage.text = before;
    assert.throws(() => new DefaultTimelineService(storage));
    assert.equal(storage.text, before);
  }
});
