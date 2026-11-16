import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { loadPortableEts } from '../scripts/load-portable-ets.mjs';

const bundle = await loadPortableEts();
after(() => bundle.close());
const { DefaultTimelineService } = bundle.modules['domain/DefaultTimelineService'];
const { layoutTimelineDay, localDayStart, timelineBlocksForDay, timelineDayHeading, weekPageOffset } =
  bundle.modules['domain/TimelineLayout'];

const { browsePanelSizes, browseDragProgress, browseReleaseTarget, browseOpensFullCalendar,
  browseLevelProgress, browseHeight } =
  bundle.modules['components/TimelineBrowseMotion'];

test('月历跟手在周条与 55% 内容区之间滑动，双日网格始终有空间', () => {
  for (const height of [300, 520, 680, 840, 1024]) {
    const { closedHeight, openHeight, rowHeight, calendarLimit } = browsePanelSizes(height);
    const travel = openHeight - closedHeight;
    assert.equal(openHeight, Math.round(height * 0.55));
    assert.ok(height - openHeight >= height * 0.45 - 1);
    assert.ok(calendarLimit <= openHeight && rowHeight >= 36);
    assert.equal(browseDragProgress(0, -20, travel), 0);
    assert.equal(browseDragProgress(1, 20, travel), 1);
    for (const fraction of [0.25, 0.5, 0.75, 1]) {
      assert.equal(browseDragProgress(0, fraction * travel, travel), fraction);
      assert.equal(browseDragProgress(1, -fraction * travel, travel), 1 - fraction);
    }
  }
});

test('下拉展开、上推收回，短距离回弹，支持中途反向和快速甩动', () => {
  const travel = 320;
  const target = (start, offset, velocity = 0) =>
    browseReleaseTarget(browseDragProgress(start, offset, travel), offset, velocity, travel);
  assert.equal(target(0, 18), false);
  assert.equal(target(1, -18), true);
  assert.equal(target(0, 75), true);
  assert.equal(target(1, -75), false);
  assert.equal(target(0, 18, 700), true);
  assert.equal(target(1, -18, -700), false);
  assert.equal(target(1, 80, 700), true);
  assert.equal(target(0.7, -64), false);
  assert.equal(target(0.3, 64), true);
});

test('时间线须从二级再次下拉才进全屏；一级长拉、上滑和轻微晃动不会误入', () => {
  assert.equal(browseOpensFullCalendar(false, 300, 800), false);
  assert.equal(browseOpensFullCalendar(true, 64, 0), true);
  assert.equal(browseOpensFullCalendar(true, 12, 600), true);
  assert.equal(browseOpensFullCalendar(true, 12, 0), false);
  assert.equal(browseOpensFullCalendar(true, 4, 800), false);
  assert.equal(browseOpensFullCalendar(true, -64, -750), false);
});

test('二级拖开的每一步都与手指位移一致，到底即满屏，沿原路拖回即恢复', () => {
  for (const fullHeight of [300, 667, 844, 1024]) {
    const sizes = browsePanelSizes(fullHeight);
    const travel = fullHeight - sizes.openHeight;
    const observed = (start, level, distance) =>
      browseHeight(browseLevelProgress(start, level, distance, sizes, fullHeight), sizes, fullHeight);
    for (const fraction of [0, 0.25, 0.5, 0.75, 0.95, 1, 0.63, 0.17, 0]) {
      const offset = fraction * travel;
      assert.ok(Math.abs(observed(1, 1, offset) - (sizes.openHeight + offset)) < 1e-8);
      assert.ok(Math.abs(observed(2, 2, -offset) - (fullHeight - offset)) < 1e-8);
    }
    assert.equal(observed(1, 1, travel + 60), fullHeight);
    assert.equal(observed(2, 2, -travel - 60), sizes.openHeight);
    assert.equal(observed(0, 0, fullHeight), sizes.openHeight);
  }
});

test('打断按钮或返回的收尾动画时，从屏幕当前那一帧继续拖', () => {
  const fullHeight = 800;
  const sizes = browsePanelSizes(fullHeight);
  for (const [start, level, distance] of [[1.4, 2, 14], [1.6, 1, -17], [0.8, 2, 5], [1.2, 0, -5]]) {
    const initialHeight = browseHeight(start, sizes, fullHeight);
    assert.ok(Math.abs(browseLevelProgress(start, level, 0, sizes, fullHeight) - start) < 1e-8);
    const position = browseLevelProgress(start, level, distance, sizes, fullHeight);
    assert.ok(Math.abs(browseHeight(position, sizes, fullHeight) - (initialHeight + distance)) < 1e-8);
  }
});

// 使用本地日历构造测试日期，避免运行机器的时区改变跨日边界。
const at = (day, hour = 0, minute = 0) => new Date(2026, 10, day, hour, minute).getTime();
const block = (id, startAt, endAt) => ({ id, title: id, startAt, endAt, note: '' });

test('两列按真实今天标注日期，查看下周时显示对应星期', () => {
  const now = at(13, 19);
  const headings = day => [day, localDayStart(day, 1)].map(stamp => timelineDayHeading(stamp, now));
  assert.deepEqual(headings(at(13)), ['11月13日 · 今天', '11月14日 · 明天']);
  assert.deepEqual(headings(at(20)), ['11月20日 · 周五', '11月21日 · 周六']);
  assert.deepEqual(headings(at(12)), ['11月12日 · 周四', '11月13日 · 今天']);
});

test('月历事项小窗跟随选中日，空周日清空上次列表，返回周六可再次查看', () => {
  const first = block('1234', at(14, 9), at(14, 10));
  const laundry = block('洗衣服', at(14, 23), at(15));
  const overnight = block('夜班', at(16, 23), at(17, 2));
  const schedule = [first, laundry, overnight];
  const selected = day => timelineBlocksForDay(at(day, 12), schedule);

  assert.deepEqual(selected(14), [first, laundry]);
  assert.deepEqual(selected(15), []);
  assert.deepEqual(selected(16), [overnight]);
  assert.deepEqual(selected(17), [overnight]);
  assert.deepEqual(selected(14), [first, laundry]);
});

test('循环滑动周条可跨年并原路返回，同页回调保留已选日期', () => {
  const decemberFriday = new Date(2026, 11, 25).getTime();
  const januaryFriday = new Date(2027, 0, 1).getTime();
  let selected = decemberFriday;
  let page = 0;
  for (const [next, weeks] of [[1, 1], [2, 2], [0, 3], [0, 3], [2, 2], [1, 1], [0, 0]]) {
    selected = localDayStart(selected, 7 * weekPageOffset(next, page));
    page = next;
    assert.equal(selected, localDayStart(decemberFriday, weeks * 7));
    if (weeks === 1) assert.equal(selected, januaryFriday);
  }
  assert.equal(selected, decemberFriday);
});

test('逐日切换按本地日历跨越月末、年末及夏令时边界', () => {
  for (const [from, to] of [
    [new Date(2028, 1, 29), new Date(2028, 2, 1)],
    [new Date(2026, 11, 31), new Date(2027, 0, 1)],
    [new Date(2026, 2, 8), new Date(2026, 2, 9)],
    [new Date(2026, 10, 1), new Date(2026, 10, 2)]
  ]) {
    assert.equal(localDayStart(from.getTime(), 1), to.getTime());
    assert.equal(localDayStart(to.getTime(), -1), from.getTime());
  }
});

class MemoryStorage {
  text = '';
  read() { return this.text; }
  async write(text) { this.text = text; }
}

test('新增、改期和删除独立时间块后，重新实例化能从磁盘还原最终状态', async t => {
  const directory = mkdtempSync(join(tmpdir(), 'todone-timeline-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const file = join(directory, 'timeline.json');
  const storage = {
    read() {
      try { return readFileSync(file, 'utf8'); }
      catch (error) { if (error.code === 'ENOENT') return ''; throw error; }
    },
    write(text) { return writeFile(file, text, 'utf8'); }
  };
  const first = new DefaultTimelineService(storage);
  const meeting = block('组会', at(13, 14), at(13, 15));
  await first.save(meeting);
  const moved = { ...meeting, startAt: at(13, 15), endAt: at(13, 16), note: '带上汇报材料' };
  await first.save(moved);
  const reopened = new DefaultTimelineService(storage);
  assert.deepEqual(reopened.list(), [moved]);
  reopened.list()[0].title = '外部修改';
  assert.equal(reopened.list()[0].title, '组会');
  await reopened.remove(meeting.id);
  assert.deepEqual(new DefaultTimelineService(storage).list(), []);
});

test('无效标题及起止时间均拒绝写入，原有块仍保留', async () => {
  const storage = new MemoryStorage();
  const service = new DefaultTimelineService(storage);
  const meeting = block('组会', at(13, 14), at(13, 15));
  await service.save(meeting);
  const saved = storage.text;
  for (const change of [{ title: ' ' }, { endAt: meeting.startAt }, { startAt: at(14) }, { endAt: NaN }]) {
    await assert.rejects(async () => service.save({ ...meeting, ...change }));
  }
  assert.equal(storage.text, saved);
  assert.deepEqual(service.list(), [meeting]);
});

test('flush 失败能按同一 ID 重试，即使底层已暂存也只出现一个时间块', async () => {
  const storage = new MemoryStorage();
  let failOnce = true;
  storage.write = async text => {
    storage.text = text;
    if (failOnce) { failOnce = false; throw new Error('flush 失败'); }
  };
  const service = new DefaultTimelineService(storage);
  const meeting = block('组会', at(13, 14), at(13, 15));
  await assert.rejects(async () => service.save(meeting));
  assert.deepEqual(service.list(), []);
  await service.save(meeting);
  assert.deepEqual(new DefaultTimelineService(storage).list(), [meeting]);
});

test('同时提交创建、改期和删除时，按调用顺序保存且互不覆盖', async () => {
  const storage = new MemoryStorage();
  const gate = Promise.withResolvers();
  const entered = Promise.withResolvers();
  let writes = 0;
  storage.write = async text => {
    if (++writes === 1) { entered.resolve(); await gate.promise; }
    storage.text = text;
  };
  const service = new DefaultTimelineService(storage);
  const first = block('学习', at(13, 13), at(13, 16));
  const second = block('组会', at(13, 14), at(13, 15));
  const moved = { ...second, startAt: at(14, 14), endAt: at(14, 15) };
  const pending = service.save(first);
  await entered.promise;
  assert.deepEqual(service.list(), []);
  const pendingSecond = service.save(second);
  const pendingMove = service.save(moved);
  const pendingDelete = service.remove(first.id);
  gate.resolve();
  await Promise.all([pending, pendingSecond, pendingMove, pendingDelete]);
  assert.deepEqual(service.list(), [moved]);
  assert.deepEqual(new DefaultTimelineService(storage).list(), [moved]);
});

test('已有时间线数据损坏时保留原始快照', async () => {
  for (const invalid of ['{', '[{"id":"incomplete"}]']) {
    const storage = new MemoryStorage();
    storage.text = invalid;
    await assert.rejects(async () => {
      const service = new DefaultTimelineService(storage);
      await service.save(block('新建', at(13, 9), at(13, 10)));
    });
    assert.equal(storage.text, invalid);
  }
});

test('读取失败提供可定位的错误码，保留文件，修复读取条件后可重试', () => {
  const { timelineReadCode } = bundle.modules['domain/TimelineReadError'];
  const event = block('项目组会', at(13, 9), at(13, 10));
  const snapshot = { version: 6, blocks: [event], tags: [] };
  const cases = [
    ['{无效的私密标题', 'TL-JSON'],
    [JSON.stringify(null), 'TL-FORMAT'],
    [JSON.stringify({ ...snapshot, version: 99 }), 'TL-VERSION:99'],
    [JSON.stringify({ ...snapshot, tags: [null] }), 'TL-TAG#1'],
    [JSON.stringify({ ...snapshot, blocks: [event, { ...event, note: null }] }), 'TL-BLOCK#2'],
    [JSON.stringify({ ...snapshot, blocks: [{ ...event, repeatFromDay: 10 }] }), 'TL-RANGE#1'],
    [JSON.stringify({ ...snapshot, blocks: [{ ...event, repeat: 'daily', overrides: [null] }] }), 'TL-OVERRIDE#1'],
    [JSON.stringify({ ...snapshot, blocks: [event, event] }), 'TL-DUPLICATE#2'],
    [JSON.stringify({ ...snapshot, blocks: [{ ...event, tagId: 'private' }] }), 'TL-TAGREF#1']
  ];
  const storage = new MemoryStorage();
  for (const [raw, code] of cases) {
    storage.text = raw;
    assert.throws(() => new DefaultTimelineService(storage), error =>
      error.message === code && timelineReadCode(error, 'INIT') === code);
    assert.equal(storage.text, raw);
  }
  const fault = Object.assign(new Error(event.title), { code: 15500000 });
  const io = { read() { throw fault; }, write() { assert.fail('读档不应写入'); } };
  assert.throws(() => new DefaultTimelineService(io), { message: 'TL-READ:15500000' });
  assert.equal(timelineReadCode(fault, 'OPEN'), 'TL-OPEN:15500000');
  io.read = () => JSON.stringify(snapshot);
  assert.deepEqual(new DefaultTimelineService(io).list(), [event]);
});

test('同日重叠块按列并排；仅接壤的块独占整列；占用时长按区间并集', () => {
  const study = block('学习', at(13, 13), at(13, 16));
  const meeting = block('组会', at(13, 15), at(13, 17));
  const dinner = block('晚饭', at(13, 17), at(13, 18));
  const layout = layoutTimelineDay(at(13), [dinner, meeting, study]);
  const byId = new Map(layout.segments.map(s => [s.block.id, s]));
  assert.equal(layout.busyMinutes, 300);
  assert.equal(byId.size, 3);
  assert.equal(byId.get(study.id).laneCount, 2);
  assert.equal(byId.get(meeting.id).laneCount, 2);
  assert.notEqual(byId.get(study.id).lane, byId.get(meeting.id).lane);
  assert.equal(byId.get(dinner.id).laneCount, 1);
});

test('跨午夜切分到两天，在午夜结束的块不占用次日', () => {
  const overnight = block('跨午夜', at(13, 23, 30), at(14, 0, 30));
  const untilMidnight = block('到零点', at(13, 23, 15), at(14));
  const first = layoutTimelineDay(at(13), [overnight, untilMidnight]);
  const second = layoutTimelineDay(at(14), [overnight, untilMidnight]);
  const clipped = first.segments.find(s => s.block.id === overnight.id);
  assert.deepEqual([clipped.startMinute, clipped.endMinute], [1410, 1440]);
  assert.equal(first.busyMinutes, 45);
  assert.equal(second.busyMinutes, 30);
  assert.deepEqual(second.segments.map(s => [s.block.id, s.startMinute, s.endMinute]), [[overnight.id, 0, 30]]);
});
