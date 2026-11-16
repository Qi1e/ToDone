import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { loadPortableEts } from '../scripts/load-portable-ets.mjs';

const bundle = await loadPortableEts();
after(() => bundle.close());
const { TimelineRepeat: R, TimelineDeleteScope: Scope, TimelineEditScope: Edit } = bundle.modules['contracts/TimelineService'];
const { firstTimelineOccurrence, firstVisibleTimelineOccurrence, timelineOccurrences } = bundle.modules['domain/TimelineRecurrence'];
const { layoutTimelineDay, timelineBlocksForDay } = bundle.modules['domain/TimelineLayout'];
const { timelineRingDays } = bundle.modules['domain/TimelineDayRing'];
const { DefaultTimelineService } = bundle.modules['domain/DefaultTimelineService'];
const date = (year, month, day, hour = 0, minute = 0) => new Date(year, month - 1, day, hour, minute).getTime();
const nov = (day, hour = 0, min = 0) => date(2026, 11, day, hour, min);
const series = (startAt, endAt, repeat) => ({ id: 'study', title: '晨读', startAt, endAt, note: '', repeat });

test('仅工作日从周六起首次排到周一，三种视图对跨夜和周末有相同口径', () => {
  const meeting = series(nov(14, 23, 30), nov(15, 0, 30), R.Weekdays);
  const first = firstTimelineOccurrence(meeting);
  assert.deepEqual([first.startAt, first.endAt], [nov(16, 23, 30), nov(17, 0, 30)]);
  const counts = [0, 0, 1, 2, 2, 2, 2, 1, 0, 1];
  const rings = timelineRingDays(nov(14), counts.length, [meeting], []);
  counts.forEach((count, i) => {
    const items = timelineBlocksForDay(nov(14 + i), [meeting]);
    const grid = layoutTimelineDay(nov(14 + i), [meeting]);
    assert.equal(rings[i].count, count);
    assert.equal(items.length, count);
    assert.deepEqual(grid.segments.map(s => s.block), items);
    assert.equal(grid.busyMinutes, count * 30);
  });
  assert.equal(timelineBlocksForDay(nov(21), [meeting])[0].startAt, nov(20, 23, 30));
});

test('每日与每周按本地钟点跨年，到某天零点结束的实例不进入该日', () => {
  const anchor = date(2026, 12, 25, 23);
  for (const repeat of [R.Daily, R.Weekly]) {
    const block = series(anchor, date(2026, 12, 26), repeat);
    const items = timelineOccurrences([block], date(2027, 1, 1), date(2027, 1, 3));
    const days = repeat === R.Daily ? [1, 2] : [1];
    assert.deepEqual(items.map(b => [b.startAt, b.endAt]), days.map(d => [date(2027, 1, d, 23), date(2027, 1, d + 1)]));
    assert.deepEqual(timelineOccurrences([block], date(2026, 12, 20), anchor), []);
  }
});

test('每月按起始日号，闰年出现 29 日，31 日跳过短月而且可以查询多年以后', () => {
  for (const [day, year, expected] of [[29, 2028, [1, 2, 3, 4]], [29, 2029, [1, 3, 4]], [31, 2050, [1, 3]]]) {
    const block = series(date(2026, 1, day, 9), date(2026, 1, day, 10), R.Monthly);
    const items = timelineOccurrences([block], date(year, 1, 1), date(year, 5, 1));
    assert.deepEqual(items.map(b => b.startAt), expected.map(m => date(year, m, day, 9)));
  }
});

test('长于一天的每日安排可有多个同系列实例并排，忙闲分钟只计覆盖并集', () => {
  const block = series(nov(16, 8), nov(17, 20), R.Daily);
  const layout = layoutTimelineDay(nov(18), [block]);
  assert.deepEqual(layout.segments.map(s => [s.block.startAt, s.laneCount]), [[nov(17, 8), 2], [nov(18, 8), 2]]);
  assert.equal(layout.busyMinutes, 1440);
  assert.equal(timelineRingDays(nov(18), 1, [block], [])[0].count, 2);
});

test('夏令时跨夜重复仍按当地钟点结束，春季少一小时、秋季多一小时', () => {
  const originalZone = process.env.TZ;
  process.env.TZ = 'America/New_York';
  try {
    for (const [month, anchor, night, hours] of [[3, 1, 7, 7], [10, 25, 31, 9]]) {
      const block = series(date(2026, month, anchor, 22), date(2026, month, anchor + 1, 6), R.Daily);
      const [item] = timelineOccurrences([block], date(2026, month, night, 22), date(2026, month, night + 1));
      assert.equal(item.startAt, date(2026, month, night, 22));
      assert.equal(item.endAt, date(2026, month, night + 1, 6));
      assert.equal((item.endAt - item.startAt) / 3600000, hours);
    }
  } finally {
    if (originalZone === undefined) delete process.env.TZ;
    else process.env.TZ = originalZone;
  }
});

test('v2 存档读入不写盘，重复规则落盘后按整组改期、转单次、删除，保留其他事项', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'todone-series-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const file = join(dir, 'timeline.json');
  const old = { id: 'old', title: '旧便签', startAt: nov(14, 8), endAt: nov(14, 9), note: '原备注' };
  await writeFile(file, JSON.stringify({ version: 2, blocks: [old], tags: [] }));
  async function reopen() {
    const text = await readFile(file, 'utf8');
    return new DefaultTimelineService({ read: () => text, write: updated => writeFile(file, updated) }, () => nov(13));
  }
  let service = await reopen();
  assert.deepEqual(service.list(), [old]);
  assert.equal(JSON.parse(await readFile(file, 'utf8')).version, 2);
  await service.save(series(nov(14, 9), nov(14, 10), R.Weekdays));
  service = await reopen();
  assert.equal(JSON.parse(await readFile(file, 'utf8')).version, 6);
  assert.equal(service.list().length, 2);
  const saved = service.list().find(b => b.id === 'study');
  assert.deepEqual([saved.startAt, saved.endAt, saved.repeat], [nov(16, 9), nov(16, 10), R.Weekdays]);
  await service.save({ ...saved, startAt: nov(16, 14), endAt: nov(16, 15), repeat: R.Weekly });
  service = await reopen();
  assert.deepEqual(timelineBlocksForDay(nov(17), service.list()), []);
  assert.equal(timelineBlocksForDay(nov(23), service.list())[0].startAt, nov(23, 14));
  await service.save({ ...service.list().find(b => b.id === 'study'), repeat: R.None });
  assert.deepEqual(timelineBlocksForDay(nov(23), service.list()), []);
  assert.equal(timelineBlocksForDay(nov(16), service.list()).length, 1);
  await service.save(saved);
  await service.remove(saved.id);
  service = await reopen();
  assert.deepEqual(service.list(), [old]);
  assert.deepEqual(timelineBlocksForDay(nov(23), service.list()), []);
});

test('无效重复规则不会覆盖存档；写入失败后用同一 ID 重试只落一组', async () => {
  let raw = '';
  let fail = false;
  const service = new DefaultTimelineService({ read: () => raw, write: async value => {
    if (fail) throw Error('写入失败');
    raw = value;
  }}, () => nov(13));
  const block = series(nov(16, 9), nov(16, 10), R.Daily);
  await service.save(block);
  const original = raw;
  fail = true;
  await assert.rejects(service.save({ ...block, repeat: R.Weekly }));
  assert.equal(service.list()[0].repeat, R.Daily);
  fail = false;
  await assert.rejects(service.save({ ...block, repeat: 'unknown' }));
  assert.equal(raw, original);
  const broken = original.replace('"daily"', '"unknown"');
  assert.throws(() => new DefaultTimelineService({ read: () => broken, write: async () => assert.fail() }));
  await service.save({ ...block, repeat: R.Weekly });
  assert.equal(JSON.parse(raw).blocks.length, 1);
  assert.equal(service.list()[0].repeat, R.Weekly);
});

function fixture(now = nov(17, 20), initial = '') {
  let raw = initial;
  let fail = false;
  const storage = {
    read: () => raw,
    write: async value => { if (fail) throw Error('写入失败'); raw = value; }
  };
  return {
    open: () => new DefaultTimelineService(storage, () => now),
    failWrites: value => { fail = value; },
    saved: () => raw
  };
}

test('新启用重复从设置日或指定的未来日期起，保留每周、每月的节奏', async () => {
  // 11月17日是周二，规则从当地日期而非点保存的时刻开始。
  for (const [repeat, start, first] of [
    [R.Daily, nov(3, 9), nov(17, 9)], [R.Weekdays, nov(1, 9), nov(17, 9)],
    [R.Weekly, nov(6, 9), nov(20, 9)], [R.Monthly, date(2026, 10, 31, 9), date(2026, 12, 31, 9)],
    [R.Daily, nov(25, 9), nov(25, 9)]
  ]) {
    const f = fixture();
    const s = f.open();
    await s.save(series(start, start + 1800000, repeat));
    const blocks = f.open().list();
    assert.equal(firstVisibleTimelineOccurrence(blocks[0]).startAt, first);
    assert.deepEqual(timelineOccurrences(blocks, start, first), []);
    assert.deepEqual(timelineOccurrences(blocks, first, first + 1).map(b => b.startAt), [first]);
  }
});

test('旧的单次转每日后保留原日程，设置日之前不补排；已有历史系列重开不丢过去安排', async () => {
  const f = fixture();
  const one = { id: 'study', title: '晨读', note: '', startAt: nov(4, 9), endAt: nov(4, 10) };
  const s = f.open();
  await s.save(one);
  await s.save({ ...one, repeat: R.Daily }, true);
  assert.deepEqual(timelineOccurrences(s.list(), nov(4), nov(19)).map(b => b.startAt).sort((a,b) => a-b),
    [nov(4, 9), nov(17, 9), nov(18, 9)]);
  await s.remove(one.id, Scope.All, nov(18, 9));
  const old = timelineBlocksForDay(nov(4), f.open().list());
  assert.equal(old.length, 1);
  assert.equal(old[0].title, one.title);
  const oldSeries = fixture(nov(22), JSON.stringify({ version: 3, blocks: [{ ...one, repeat: R.Daily }], tags: [] }));
  const migrated = oldSeries.open();
  await migrated.save({ ...migrated.list()[0], title: '早读' }, true);
  assert.equal(timelineBlocksForDay(nov(5), oldSeries.open().list())[0].title, '早读');
});

test('跨夜单次删除两天同时更新，截断包含当次，保留前一夜的尾段与无关日程', async () => {
  const f = fixture(nov(14));
  let s = f.open();
  await s.save(series(nov(14, 23), nov(15, 2), R.Daily));
  await s.save({ id: 'once', title: '独立日程', note: '', startAt: nov(17, 15), endAt: nov(17, 16) });
  // 点击 17 日凌晨看到的 16 日夜班。
  const spill = timelineBlocksForDay(nov(17), s.list())[0];
  assert.equal(spill.startAt, nov(16, 23));
  await s.remove(spill.id, Scope.One, spill.startAt);
  s = f.open();
  for (const [day, count, minutes] of [[16, 1, 120], [17, 2, 120], [18, 2, 180]]) {
    assert.equal(timelineRingDays(nov(day), 1, s.list(), [])[0].count, count);
    assert.equal(timelineBlocksForDay(nov(day), s.list()).length, count);
    assert.equal(layoutTimelineDay(nov(day), s.list()).busyMinutes, minutes);
  }
  await s.remove('study', Scope.Following, nov(19, 23));
  s = f.open();
  const last = timelineBlocksForDay(nov(19), s.list());
  assert.deepEqual(last.map(b => b.startAt), [nov(18, 23)]);
  assert.equal(timelineRingDays(nov(20), 1, s.list(), [])[0].count, 0);
  await s.remove('study', Scope.All, nov(18, 23));
  assert.deepEqual(f.open().list().map(b => b.id), ['once']);
});

test('更新系列时保留已删日期与截止日期；失败、重复删除和过期编辑不会复活已删实例', async () => {
  const f = fixture(nov(14));
  let s = f.open();
  const block = series(nov(15, 9), nov(15, 10), R.Daily);
  await s.save(block);
  const before = f.saved();
  f.failWrites(true);
  await assert.rejects(s.remove(block.id, Scope.One, nov(16, 9)));
  assert.equal(f.saved(), before);
  assert.equal(timelineBlocksForDay(nov(16), s.list()).length, 1);
  f.failWrites(false);
  const stale = s.list()[0];
  await Promise.all([s.remove(block.id, Scope.One, nov(16, 9)), s.remove(block.id, Scope.Following, nov(19, 9)),
    s.save({ ...stale, startAt: nov(15, 11), endAt: nov(15, 12) }, true)]);
  await s.remove(block.id, Scope.One, nov(16, 9));
  s = f.open();
  assert.deepEqual(timelineOccurrences(s.list(), nov(14), nov(28)).map(b => b.startAt),
    [nov(15, 11), nov(17, 11), nov(18, 11)]);
  await s.remove(block.id, Scope.All);
  await assert.rejects(s.save(stale, true));
  assert.deepEqual(f.open().list(), []);
});

test('删除首个实例或在第一天截断，不留下仍可见的首次预览', async () => {
  const s = fixture(nov(14)).open();
  await s.save(series(nov(15, 9), nov(15, 10), R.Weekly));
  await s.remove('study', Scope.One, nov(15, 9));
  assert.equal(firstVisibleTimelineOccurrence(s.list()[0]).startAt, nov(22, 9));
  await s.remove('study', Scope.Following, nov(22, 9));
  assert.deepEqual(timelineOccurrences(s.list(), nov(1), nov(70)), []);
});

test('仅修改当前组会：跨日移动、重启后再编辑与删除，其他实例仍属同一系列', async () => {
  const f = fixture(nov(1));
  let s = f.open();
  await s.save(series(nov(9, 9), nov(9, 10), R.Daily));
  const original = timelineBlocksForDay(nov(11), s.list())[0];
  const changed = { ...original, title: '临时晚会', startAt: nov(12, 23), endAt: nov(13, 1) };
  const result = await s.saveOccurrence(changed, Edit.One, original.startAt);
  assert.equal(result.startAt, nov(12, 23));
  s = f.open();
  assert.deepEqual(timelineBlocksForDay(nov(11), s.list()), []);
  const twelve = timelineBlocksForDay(nov(12), s.list());
  assert.deepEqual(twelve.map(b => b.title), ['晨读', '临时晚会']);
  assert.equal(twelve[1].occurrenceOriginalStart, original.startAt);
  assert.equal(timelineRingDays(nov(13), 1, s.list(), [])[0].count, 2);
  await s.saveOccurrence({ ...twelve[1], title: '晚会跟进' }, Edit.One, twelve[1].occurrenceOriginalStart);
  assert.equal(timelineBlocksForDay(nov(12), s.list())[1].title, '晚会跟进');
  await s.remove(result.id, Scope.One, original.startAt);
  assert.deepEqual(timelineBlocksForDay(nov(12), s.list()).map(b => b.title), ['晨读']);
  assert.equal(timelineBlocksForDay(nov(13), s.list()).length, 1);
});

test('修改这次及以后：旧历史不动，新系列带上已删日期和截止日期，写入失败不拆分', async () => {
  const f = fixture(nov(1));
  let s = f.open();
  await s.save(series(nov(9, 9), nov(9, 10), R.Daily));
  await s.remove('study', Scope.One, nov(14, 9));
  await s.remove('study', Scope.Following, nov(16, 9));
  const selected = timelineBlocksForDay(nov(12), s.list())[0];
  const draft = { ...selected, title: '新组会', startAt: nov(12, 15), endAt: nov(12, 16) };
  const old = f.saved();
  f.failWrites(true);
  await assert.rejects(s.saveOccurrence(draft, Edit.Following, selected.startAt));
  assert.equal(old, f.saved());
  assert.equal(timelineBlocksForDay(nov(12), s.list())[0].title, '晨读');
  f.failWrites(false);
  const updated = await s.saveOccurrence(draft, Edit.Following, selected.startAt);
  assert.equal(updated.startAt, nov(12, 15));
  s = f.open();
  for (const d of [9, 10, 11]) assert.equal(timelineBlocksForDay(nov(d), s.list())[0].startAt, nov(d, 9));
  for (const d of [12, 13, 15]) {
    const items = timelineBlocksForDay(nov(d), s.list());
    assert.deepEqual(items.map(b => [b.startAt, b.title]), [[nov(d, 15), '新组会']]);
  }
  for (const d of [14, 16, 17]) assert.deepEqual(timelineBlocksForDay(nov(d), s.list()), []);
});

test('从后续实例修改整个系列，历史与未来同时改时刻且不复活排除的日期', async () => {
  const f = fixture(nov(1));
  const s = f.open();
  await s.save(series(nov(2, 9), nov(2, 10), R.Weekly));
  await s.remove('study', Scope.One, nov(9, 9));
  const chosen = timelineBlocksForDay(nov(16), s.list())[0];
  const after = await s.saveOccurrence({ ...chosen, startAt: nov(16, 15), endAt: nov(16, 17) }, Edit.All, chosen.startAt);
  assert.equal(after.startAt, nov(16, 15));
  for (const d of [2, 16, 23]) assert.deepEqual(timelineBlocksForDay(nov(d), f.open().list()).map(b =>
    [b.startAt, b.endAt]), [[nov(d, 15), nov(d, 17)]]);
  assert.deepEqual(timelineBlocksForDay(nov(9), f.open().list()), []);
});

test('修改后整组删除连同移出原日期的单次一起清理', async () => {
  const s = fixture(nov(1)).open();
  await s.save(series(nov(2, 9), nov(2, 10), R.Weekly));
  const chosen = timelineBlocksForDay(nov(9), s.list())[0];
  const moved = await s.saveOccurrence({ ...chosen, startAt: nov(8, 22), endAt: nov(9, 2) }, Edit.One, chosen.startAt);
  await s.remove(moved.id, Scope.All, moved.occurrenceOriginalStart);
  assert.deepEqual(timelineOccurrences(s.list(), nov(1), nov(40)), []);
});

test('从本次更换周期或停止重复：历史保留，后续以所选日期排期', async () => {
  for (const repeat of [R.Weekly, R.None]) {
    const s = fixture(nov(1)).open();
    await s.save(series(nov(9, 9), nov(9, 10), R.Daily));
    const chosen = timelineBlocksForDay(nov(12), s.list())[0];
    await s.saveOccurrence({ ...chosen, repeat }, Edit.Following, chosen.startAt);
    assert.equal(timelineBlocksForDay(nov(11), s.list()).length, 1);
    assert.equal(timelineBlocksForDay(nov(12), s.list()).length, 1);
    assert.deepEqual(timelineBlocksForDay(nov(13), s.list()), []);
    assert.equal(timelineBlocksForDay(nov(19), s.list()).length, repeat === R.Weekly ? 1 : 0);
  }
});

test('从周四的一次把整个每日系列改成每周或每月，以所选星期或日号为准', async () => {
  for (const repeat of [R.Weekly, R.Monthly]) {
    const s = fixture(nov(1)).open();
    await s.save(series(nov(2, 9), nov(2, 10), R.Daily));
    const thursday = timelineBlocksForDay(nov(12), s.list())[0];
    const saved = await s.saveOccurrence({ ...thursday, repeat }, Edit.All, thursday.startAt);
    assert.equal(saved.startAt, nov(12, 9));
    const dates = timelineOccurrences(s.list(), nov(1), date(2026, 12, 14)).map(b => b.startAt);
    const expected = repeat === R.Weekly
      ? [nov(5, 9), nov(12, 9), nov(19, 9), nov(26, 9), nov(33, 9), nov(40, 9)]
      : [nov(12, 9), date(2026, 12, 12, 9)];
    assert.deepEqual(dates, expected);
  }
});

test('两个实例改为同一时刻仍可分别选中并删除，重试不会多出便签', async () => {
  const f = fixture(nov(1));
  const s = f.open();
  await s.save(series(nov(9, 9), nov(9, 10), R.Daily));
  const before = timelineBlocksForDay(nov(10), s.list())[0];
  const draft = { ...before, title: '另一次晨读', startAt: nov(11, 9), endAt: nov(11, 10) };
  await s.saveOccurrence(draft, Edit.One, before.startAt);
  await s.saveOccurrence(draft, Edit.One, before.startAt);
  let same = timelineBlocksForDay(nov(11), f.open().list());
  assert.equal(same.length, 2);
  assert.equal(new Set(same.map(b => b.occurrenceOriginalStart ?? b.startAt)).size, 2);
  const moved = same.find(b => b.title === draft.title);
  await s.remove(moved.id, Scope.One, moved.occurrenceOriginalStart);
  same = timelineBlocksForDay(nov(11), f.open().list());
  assert.deepEqual(same.map(b => b.title), ['晨读']);
});

test('原先改过的一次与新的重复频率错开时，保留它的内容及实际时段', async () => {
  const f = fixture(nov(1));
  const s = f.open();
  await s.save(series(nov(2, 9), nov(2, 10), R.Daily));
  const wednesday = timelineBlocksForDay(nov(4), s.list())[0];
  await s.saveOccurrence({ ...wednesday, title: '和导师单聊', note: '带草稿', startAt: nov(4, 14), endAt: nov(4, 15) },
    Edit.One, wednesday.startAt);
  const thursday = timelineBlocksForDay(nov(12), s.list())[0];
  await s.saveOccurrence({ ...thursday, repeat: R.Weekly }, Edit.All, thursday.startAt);
  const items = timelineBlocksForDay(nov(4), f.open().list());
  assert.deepEqual(items.map(b => [b.startAt, b.endAt, b.title, b.note, b.repeat]),
    [[nov(4, 14), nov(4, 15), '和导师单聊', '带草稿', undefined]]);
  assert.equal(timelineBlocksForDay(nov(5), f.open().list())[0].repeat, R.Weekly);
});

test('跨时区重开 v5、v6 的单次改期，保留实际时段和内容，仍可再次编辑和删除', async () => {
  const originalZone = process.env.TZ;
  try {
    for (const version of [5, 6]) {
      process.env.TZ = 'Asia/Shanghai';
      const anchor = date(2026, 10, 29, 9);
      const originalStart = nov(2, 9);
      const edit = { originalStart, startAt: nov(2, 13), endAt: nov(2, 14), title: '单次组会', note: '讨论演示' };
      if (version === 6) {
        edit.reminderMinutes = 15;
        edit.attachments = [{ id: 'url', name: '资料', source: 'https://example.com/', kind: 'url' }];
      }
      const daily = { ...series(anchor, anchor + 3600000, R.Daily), overrides: [edit] };
      const raw = JSON.stringify({ version, blocks: [daily], tags: [] });
      const f = fixture(anchor, raw);
      process.env.TZ = 'America/New_York';
      const s = f.open();
      assert.equal(f.saved(), raw);
      const selected = timelineOccurrences(s.list(), originalStart - 3600000, edit.endAt);
      assert.equal(selected.length, 1);
      const item = selected[0];
      assert.equal(item.startAt, edit.startAt);
      assert.equal(item.endAt, edit.endAt);
      assert.equal(item.note, edit.note);
      assert.equal(item.reminderMinutes, edit.reminderMinutes);
      assert.deepEqual(item.attachments, edit.attachments);
      await s.saveOccurrence({ ...item, title: '已核对' }, Edit.One, item.occurrenceOriginalStart);
      process.env.TZ = 'Asia/Shanghai';
      const reopened = f.open();
      const [changed] = timelineBlocksForDay(nov(2), reopened.list());
      assert.equal(changed.title, '已核对');
      assert.equal(changed.occurrenceOriginalStart, originalStart);
      assert.deepEqual(changed.attachments, edit.attachments);
      await reopened.remove(changed.id, Scope.One, changed.occurrenceOriginalStart);
      assert.equal(timelineBlocksForDay(nov(2), f.open().list()).length, 0);
      assert.equal(timelineBlocksForDay(nov(3), f.open().list()).length, 1);
    }
  } finally {
    if (originalZone === undefined) delete process.env.TZ;
    else process.env.TZ = originalZone;
  }
});

test('校验重复例外时仍拒绝无对应日期、任意钟点偏移和重复关联，失败不写盘', () => {
  const block = series(nov(2, 9), nov(2, 10), R.Weekly);
  const edit = { originalStart: nov(9, 9), startAt: nov(9, 14), endAt: nov(9, 15), note: '', title: '改期' };
  for (const starts of [[nov(8, 9)], [nov(9, 9, 1)], [nov(9, 9), nov(9, 9)]]) {
    const overrides = starts.map(originalStart => ({ ...edit, originalStart }));
    const raw = JSON.stringify({ version: 5, tags: [], blocks: [{ ...block, overrides }] });
    const f = fixture(nov(1), raw);
    assert.throws(() => f.open());
    assert.equal(f.saved(), raw);
  }
});
