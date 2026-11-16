import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { loadPortableEts } from '../scripts/load-portable-ets.mjs';

const bundle = await loadPortableEts();
after(() => bundle.close());
const { calendarAnnotation } = bundle.modules['domain/CalendarAnnotation'];
const label = (y, m, d, h = 0) => calendarAnnotation(new Date(y, m - 1, d, h).getTime());

test('公历节日、农历节日及 29/30 天的除夕优先于普通日期', () => {
  assert.equal(label(2026, 1, 1), '元旦');
  assert.equal(label(2024, 2, 9), '除夕');   // 腊月三十
  assert.equal(label(2026, 2, 16), '除夕');  // 腊月廿九
  assert.equal(label(2026, 2, 17), '春节');
  assert.equal(label(2026, 6, 19), '端午节');
  assert.equal(label(2026, 9, 25), '中秋节');
  assert.equal(label(2020, 10, 1), '国庆节'); // 中秋同日
});

test('当天有节气时显示节气，月初含闰月显示月名，其余日子显示农历日', () => {
  assert.equal(label(2026, 4, 5), '清明');
  assert.equal(label(2026, 11, 22), '小雪');
  assert.equal(label(2026, 12, 22), '冬至');
  assert.equal(label(2025, 7, 25), '闰六月');
  assert.equal(label(2033, 12, 22), '闰冬月');
  assert.equal(label(2026, 11, 16), '初八');
});

test('年表边界和本地公历日期独立于 UTC 时刻', () => {
  assert.equal(label(1901, 1, 2), '十二');
  assert.equal(label(2100, 12, 31), '腊月');
  assert.equal(label(1899, 11, 16), '');
  assert.equal(label(2101, 1, 1), '元旦');
  assert.equal(label(2024, 3, 10, 0), '二月');
  assert.equal(label(2024, 3, 10, 23), '二月');
});
