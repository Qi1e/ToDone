import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { loadPortableEts } from '../scripts/load-portable-ets.mjs';

const bundle = await loadPortableEts();
after(() => bundle.close());
const { planTimelineReminders } = bundle.modules['domain/TimelineReminderPlan'];
const { timelineDateNumber, timelineOccurrences } = bundle.modules['domain/TimelineRecurrence'];
const t = (day, hour = 0, minute = 0) => new Date(2026, 10, day, hour, minute).getTime();
const hour = 3600000;
const item = (id, startAt, reminderMinutes, repeat) => ({
  id, title: id, note: '', startAt, endAt: startAt + hour, reminderMinutes, repeat
});

test('八档提醒按触发时刻取最近的名额，只计未来提醒，零名额仍报告待排', () => {
  const from = t(11, 9), until = t(12, 9);
  const blocks = [
    item('昨天', t(10, 9), 0), item('此刻', from, 0), item('未设置', t(11, 10), undefined),
    ...[0, 5, 10, 15, 30, 60, 1440].map(n => item('提前' + n, until, n)),
    item('次日事项', t(13, 7, 59), 1440)
  ];
  const expected = ['提前60', '提前30', '提前15', '提前10', '提前5', '提前0'];
  const all = planTimelineReminders(blocks, from, 30, until);
  assert.deepEqual(all.entries.map(r => r.blockId), ['次日事项', ...expected]);
  assert.equal(all.entries[0].fireAt, t(12, 7, 59));
  assert.equal(all.hasMore, false);
  const capped = planTimelineReminders(blocks, from, 2, until);
  assert.deepEqual(capped.entries, all.entries.slice(0, 2));
  assert.equal(capped.hasMore, true);
  assert.deepEqual(planTimelineReminders(blocks, from, 0, until), { entries: [], hasMore: true });
  assert.deepEqual(planTimelineReminders(blocks.slice(0, 3), from, 0), { entries: [], hasMore: false });
  assert.deepEqual(planTimelineReminders([...blocks].reverse(), from, 30, until), all);
});

test('改单次提醒、取消一天、截断此后；跨日移动后同一时刻的两次拥有不同且稳定的标识', () => {
  const daily = item('组会', t(10, 9), 10, 'daily');
  const expectedKey = planTimelineReminders([daily], t(9), 20, t(16)).entries[1].key;
  daily.overrides = [
    { originalStart: t(11, 9), startAt: t(12, 9), endAt: t(12, 10), title: '单独评审', note: '', reminderMinutes: 5 },
    { originalStart: t(13, 9), startAt: t(13, 9), endAt: t(13, 10), title: '静音', note: '' }
  ];
  daily.excludedDays = [timelineDateNumber(t(14))];
  daily.repeatUntilDay = timelineDateNumber(t(16));
  const plan = planTimelineReminders([daily], t(9), 30);
  assert.deepEqual(plan.entries.map(r => r.fireAt), [t(10, 8, 50), t(12, 8, 50), t(12, 8, 55), t(15, 8, 50)]);
  const moved = plan.entries.find(r => r.title === '单独评审');
  assert.equal(moved.occurrenceStart, t(11, 9));
  assert.equal(moved.startAt, t(12, 9));
  assert.equal(moved.key, expectedKey);
  assert.equal(new Set(plan.entries.map(r => r.key)).size, 4);
  assert.equal(plan.hasMore, false);
  const withoutSeriesReminder = planTimelineReminders([{ ...daily, reminderMinutes: undefined }], t(9), 30);
  assert.deepEqual(withoutSeriesReminder.entries, [moved]);
  assert.deepEqual(planTimelineReminders([], t(9), 30), { entries: [], hasMore: false });
});

test('没有预设年限，远期一次和系列都能补排；只有最近的 capacity 个进入系统', () => {
  const start = new Date(2040, 0, 31, 15).getTime();
  const monthly = item('月报', start, 60, 'monthly');
  const single = item('结项', new Date(2040, 1, 15, 9).getTime(), 0);
  const plan = planTimelineReminders([monthly, single], t(15), 3);
  assert.equal(plan.hasMore, true);
  assert.deepEqual(plan.entries.map(r => r.startAt), [start, single.startAt, new Date(2040, 2, 31, 15).getTime()]);
  const next = planTimelineReminders([monthly, single], plan.entries[2].fireAt, 1);
  assert.equal(next.entries[0].startAt, new Date(2040, 4, 31, 15).getTime());
});

test('夏令时和仅工作日规则与网格投影一致，提前一天按触发时间边界筛选', () => {
  const previous = process.env.TZ;
  process.env.TZ = 'America/New_York';
  try {
    const march = (d, h, m = 0) => new Date(2026, 2, d, h, m).getTime();
    const block = item('早会', march(6, 9), 1440, 'weekdays');
    const from = march(7, 12);
    const until = march(13, 9);
    const plan = planTimelineReminders([block], from, 30, until);
    const grid = timelineOccurrences([block], from, until + 86400001)
      .map(b => b.startAt - 86400000).filter(fire => fire > from && fire <= until);
    assert.deepEqual(plan.entries.map(r => r.fireAt), grid);
    assert.equal(plan.entries[0].startAt, march(9, 9));
    assert.equal(plan.entries[0].fireAt, march(8, 9));
    assert.equal(plan.hasMore, false);
  } finally {
    if (previous === undefined) delete process.env.TZ;
    else process.env.TZ = previous;
  }
});
