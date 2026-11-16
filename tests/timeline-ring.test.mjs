import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { loadPortableEts } from '../scripts/load-portable-ets.mjs';

const bundle = await loadPortableEts();
after(() => bundle.close());
const { DEFAULT_RING_COLOR, RING_DOT_DEGREES, calendarRingWeeks, timelineRingDays } = bundle.modules['domain/TimelineDayRing'];
const { DefaultTimelineService } = bundle.modules['domain/DefaultTimelineService'];
const { TimelineRepeat } = bundle.modules['contracts/TimelineService'];
const time = (day, hour = 0, minute = 0) => new Date(2026, 10, day, hour, minute).getTime();
const tags = [{ id: 'work', name: '工作', color: '#FFA337' }, { id: 'run', name: '跑步', color: '#56BE9E' }];
const block = (id, startAt, endAt, tagId) => ({ id, title: id, startAt, endAt, note: '', tagId });

test('同一周/月保存每天组会后更新未来日期的行键，改色也刷新，其余周保持原键', async () => {
  const service = new DefaultTimelineService({ read: () => '', write: async () => {} }, () => time(12));
  const rows = () => calendarRingWeeks(timelineRingDays(time(2), 28, service.list(), service.listTags()));
  const previous = rows();
  const meeting = { ...block('组会', time(12, 15), time(12, 16)), repeat: TimelineRepeat.Daily };
  await service.save(meeting);
  const saved = rows();
  assert.equal(saved[0].key, previous[0].key);
  for (let i = 1; i < saved.length; i++) assert.notEqual(saved[i].key, previous[i].key);
  assert.ok(saved.flatMap(row => row.days).slice(10).every(day => day.arcs[0].color === DEFAULT_RING_COLOR));
  await service.saveTag(tags[0]);
  await service.save({ ...meeting, tagId: tags[0].id });
  const recolored = rows();
  assert.equal(recolored[2].days[0].count, saved[2].days[0].count);
  assert.equal(recolored[2].days[0].arcs[0].color, tags[0].color);
  assert.notEqual(recolored[2].key, saved[2].key);
  assert.deepEqual(rows(), recolored);
  await service.remove(meeting.id);
  assert.deepEqual(rows(), previous);
});

test('空日无环；单个跨午夜日程按本地日期各点亮四分之一圈，结束边界不进次日', () => {
  const rings = timelineRingDays(time(12, 15), 4, [
    block('跨夜', time(13, 23), time(14, 2), 'work'),
    block('前一天', time(11), time(12), 'run'),
    block('尚未开始', time(16), time(17))
  ], tags);
  assert.deepEqual(rings.map(day => day.count), [0, 1, 1, 0]);
  assert.deepEqual(rings.map(day => day.arcs), [
    [], [{ color: tags[0].color, start: 0, sweep: 90 }],
    [{ color: tags[0].color, start: 0, sweep: 90 }], []
  ]);
});

test('同类别按当天实际时长合并；即使时间重叠仍各计入标签，取消与改期不留下旧弧', () => {
  const blocks = [
    block('早会', time(12, 23), time(13, 1), 'work'),
    block('复盘', time(13, 0, 30), time(13, 1), 'work'),
    block('跑步', time(13, 7), time(13, 7, 30), 'run')
  ];
  const rings = timelineRingDays(time(13), 1, blocks, tags);
  assert.equal(rings[0].count, 3);
  assert.deepEqual(rings[0].arcs.map(arc => arc.color), tags.map(tag => tag.color));
  assert.equal(rings[0].arcs[0].sweep / rings[0].arcs[1].sweep, 3);
  const moved = block('跑步', time(14, 7), time(14, 7, 30), 'run');
  assert.deepEqual(timelineRingDays(time(13), 2, [blocks[1], moved], tags)
    .map(day => day.arcs.map(arc => [arc.color, arc.sweep])), [[[tags[0].color, 90]], [[tags[1].color, 90]]]);
});

test('繁忙日合并细小类别，保留圆点和清晰间隔；旧日程或失去标签时使用默认色', () => {
  const many = ['#FF8800', '#7F75CD', '#66A965', '#428BD1', '#CF5485', '#639999', '#AA9123'];
  const labels = many.map((color, i) => ({ id: String(i), name: String(i), color }));
  const blocks = labels.map((tag, i) => block(tag.id, time(13, 10), time(13, i ? 10 : 16, i ? 1 : 0), tag.id));
  const day = timelineRingDays(time(13), 1, blocks, labels)[0];
  assert.equal(day.count, 7);
  assert.equal(day.arcs.length, 6);
  assert.equal(day.arcs[0].color, many[0]);
  assert.equal(day.arcs.at(-1).color, '#9DA4AE');
  assert.ok(day.arcs.slice(1).some(arc => Math.abs(arc.sweep - RING_DOT_DEGREES) < 0.001));
  for (let i = 1; i < day.arcs.length; i++) {
    assert.ok(day.arcs[i].start >= day.arcs[i - 1].start + day.arcs[i - 1].sweep + 6.99);
  }
  assert.ok(day.arcs.at(-1).start + day.arcs.at(-1).sweep < 360);
  assert.deepEqual(timelineRingDays(time(13), 1, [
    block('无', time(13, 9), time(13, 10)), block('失去标签', time(13, 11), time(13, 12), 'missing')
  ], tags)[0].arcs, [{ color: DEFAULT_RING_COLOR, start: 0, sweep: 353 }]);
});

test('系统排序规则不可用时仍能读取同一时段的日程、当日预览和等时长日期圈', t => {
  const { timelineBlocksForDay } = bundle.modules['domain/TimelineLayout'];
  const blocks = [block('b', time(12, 9), time(12, 10), 'work'), block('a', time(12, 9), time(12, 10), 'run')];
  const raw = JSON.stringify({ version: 6, blocks, tags });
  const service = new DefaultTimelineService({ read: () => raw, write: () => assert.fail('读取不应写盘') });
  t.mock.method(String.prototype, 'localeCompare', () => { throw new RangeError('invalid collation'); });
  assert.deepEqual(service.list().map(item => item.id), ['a', 'b']);
  assert.deepEqual(timelineBlocksForDay(time(12), blocks).map(item => item.id), ['a', 'b']);
  const [ring] = timelineRingDays(time(12), 1, blocks, tags);
  assert.deepEqual(ring.arcs.map(arc => arc.color), [tags[1].color, tags[0].color]);
});

test('全屏月历按本地周一至周日补足月首月尾，补位格保留实际安排', () => {
  const { homeCalendarWeeks } = bundle.modules['domain/HomeMonthCalendar'];
  const { localDayStart } = bundle.modules['domain/TimelineLayout'];
  const edge = block('跨月值班', time(0, 23), time(2), 'work');
  const after = block('下月例会', time(31, 8), time(31, 9), 'run');
  const six = homeCalendarWeeks(time(15), [after, edge], tags);
  assert.equal(six.length, 6);
  const days = six.flatMap(week => week.days);
  assert.equal(days[0].day, new Date(2026, 9, 26).getTime());
  assert.equal(days.at(-1).day, new Date(2026, 11, 6).getTime());
  assert.deepEqual(days.map(day => day.day), days.map((_, i) => localDayStart(days[0].day, i)));
  assert.deepEqual(days.filter(d => d.ring.count).map(d => [d.day, d.entries[0].title]), [
    [time(0), '跨月值班'], [time(1), '跨月值班'], [time(31), '下月例会']
  ]);
  const four = homeCalendarWeeks(new Date(2021, 1, 12).getTime(), [], []);
  assert.equal(four.length, 4);
  assert.equal(four[0].days[0].day, new Date(2021, 1, 1).getTime());
  assert.equal(four.at(-1).days.at(-1).day, new Date(2021, 1, 28).getTime());
});

test('月历显示改期例外和其他重复实例，单次改名与改色刷新对应周', async () => {
  const { homeCalendarWeeks } = bundle.modules['domain/HomeMonthCalendar'];
  const { TimelineEditScope } = bundle.modules['contracts/TimelineService'];
  const service = new DefaultTimelineService({ read: () => '', write: async () => {} }, () => time(1));
  await service.saveTag(tags[0]);
  const series = { ...block('每周组会', time(4, 9), time(4, 10), 'work'), repeat: TimelineRepeat.Weekly };
  await service.save(series);
  const project = () => homeCalendarWeeks(time(1), service.list(), service.listTags());
  const before = project();
  const selected = before[2].days[2].entries[0];
  assert.equal(selected.startAt, time(11, 9));
  const moved = await service.saveOccurrence({ ...selected, title: '周五组会', startAt: time(13, 23), endAt: time(14, 1) },
    TimelineEditScope.One, selected.startAt);
  const weeks = project();
  assert.deepEqual(weeks[2].days.map(d => d.entries.length), [0, 0, 0, 0, 1, 1, 0]);
  assert.equal(weeks[3].days[2].entries[0].title, '每周组会');
  assert.equal(weeks[2].days[5].entries[0].occurrenceOriginalStart, selected.startAt);
  assert.equal(weeks[1].key, before[1].key);
  assert.notEqual(weeks[2].key, before[2].key);
  await service.saveOccurrence({ ...moved, title: '周五复盘' }, TimelineEditScope.One, selected.startAt);
  const renamed = project();
  assert.notEqual(renamed[2].key, weeks[2].key);
  await service.saveTag({ ...tags[0], color: '#123456' });
  const recolored = project();
  assert.notEqual(recolored[2].key, renamed[2].key);
  assert.equal(recolored[2].days[4].ring.arcs[0].color, '#123456');
});

test('自定义标签以原色铺底，日期格的小字在深蓝、粉、黄和临界灰色上都达到 4.5:1', () => {
  const { calendarStripInk, homeCalendarWeeks } = bundle.modules['domain/HomeMonthCalendar'];
  function measuredLuminance(hex) {
    const [r, g, b] = hex.slice(1).match(/../g).map(pair => {
      const c = Number.parseInt(pair, 16) / 255;
      return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
    });
    return r * 0.2126 + g * 0.7152 + b * 0.0722;
  }
  for (const fill of ['#092E68', '#D85290', '#F3B840', '#000000', '#FFFFFF', '#747474', '#757575', '#767676', '#777777', '#787878']) {
    const ink = calendarStripInk(fill);
    const [a, b] = [fill, ink].map(measuredLuminance).sort((x, y) => x - y);
    assert.ok((b + 0.05) / (a + 0.05) >= 4.5, fill + ' / ' + ink);
  }
  const event = block('跨夜', time(13, 23), time(14, 1), 'work');
  const changed = [{ ...tags[0], color: '#D85290' }];
  const before = homeCalendarWeeks(time(13), [event], tags);
  const after = homeCalendarWeeks(time(13), [event], changed);
  const days = after.flatMap(week => week.days).filter(day => day.entries.length);
  assert.equal(days.length, 2);
  for (const day of days) {
    assert.ok(day.annotation.length > 0);
    assert.equal(day.strips[0].fill, '#D85290');
    assert.equal(day.strips[0].ink, calendarStripInk('#D85290'));
    assert.equal(day.strips[0].title, event.title);
  }
  assert.notDeepEqual(before.map(week => week.key), after.map(week => week.key));
});
