import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { loadPortableEts } from '../scripts/load-portable-ets.mjs';

const bundle = await loadPortableEts();
after(() => bundle.close());
const { DefaultTimelineService } = bundle.modules['domain/DefaultTimelineService'];
const { timelineOccurrences } = bundle.modules['domain/TimelineRecurrence'];
const { TimelineEditScope: Edit, TimelineDeleteScope: Drop, TimelineRepeat: R, TimelineAttachmentKind: K,
  TIMELINE_REMINDER_MINUTES, isTimelineAttachmentUrl } = bundle.modules['contracts/TimelineService'];
const at = (day, hour = 0) => new Date(2026, 10, day, hour).getTime();
const meeting = { id: 'meeting', title: '评审', startAt: at(10, 9), endAt: at(10, 10), note: '带电脑' };
const file = { id: 'doc', name: '报告 终稿.pdf', kind: K.File, source: '6bed6b02-41a6.pdf' };
const image = { id: 'fig', name: '示意图.png', kind: K.Image, source: 'image01.png' };
const audio = { id: 'memo', name: '语音.m4a', kind: K.Audio, source: 'audio-1.m4a' };
const url = { id: 'url', name: '组会资料', kind: K.Url, source: 'https://例子.测试/资料?周次=8#总结' };
const ids = item => item.attachments?.map(a => a.id) ?? [];
const occurrence = (service, day) => timelineOccurrences(service.list(), at(day), at(day + 1))[0];

function fixture(raw = '') {
  const storage = { read: () => raw, write: async next => { raw = next; } };
  return { open: () => new DefaultTimelineService(storage, () => at(1)), text: () => raw };
}

test('旧存档无提醒和附件，无写入读取；新增四种附件、开始时与其他提醒设置重开可用', async () => {
  for (const version of [2, 3, 4, 5]) {
    const raw = JSON.stringify({ version, blocks: [meeting], tags: [] });
    const f = fixture(raw);
    const service = f.open();
    assert.deepEqual(service.list(), [meeting]);
    assert.equal(f.text(), raw);
    for (const minutes of TIMELINE_REMINDER_MINUTES) {
      await service.save({ ...meeting, attachments: [file, image, audio, url], reminderMinutes: minutes }, true);
      assert.deepEqual(f.open().list()[0], { ...meeting, attachments: [file, image, audio, url], reminderMinutes: minutes });
    }
    assert.equal(JSON.parse(f.text()).version, 6);
    await service.save({ ...meeting, attachments: [] }, true);
    assert.deepEqual(f.open().list(), [meeting]);
  }
});

test('保存与查询均隔离附件对象，修改保存草稿、返回值与列表不改变已提交的系列或单次特例', async () => {
  const f = fixture();
  const s = f.open();
  const input = { ...meeting, repeat: R.Daily, attachments: [{ ...image }], reminderMinutes: 0 };
  const pending = s.save(input);
  input.attachments[0].source = 'unrelated.png';
  await pending;
  assert.equal(s.list()[0].attachments[0].source, image.source);
  const edit = occurrence(s, 12);
  const result = await s.saveOccurrence({ ...edit, attachments: [{ ...file }], reminderMinutes: 10 }, Edit.One, edit.startAt);
  result.attachments[0].name = '';
  const list = s.list();
  list[0].overrides[0].attachments[0].source = 'bad.pdf';
  const [copy1, , copy3] = timelineOccurrences(list, at(10), at(13));
  copy1.attachments[0].name = '只改投影';
  copy3.attachments[0].source = 'other.pdf';
  assert.equal(list[0].attachments[0].name, image.name);
  assert.equal(list[0].overrides[0].attachments[0].source, 'bad.pdf');
  assert.deepEqual(occurrence(s, 12).attachments, [file]);
  assert.equal(occurrence(s, 10).reminderMinutes, 0);
  assert.equal(occurrence(f.open(), 12).reminderMinutes, 10);
});

test('单次、后段及整组更新提醒/附件：先前日期、排除日期以及其他单次的专用资料都保留', async () => {
  const f = fixture();
  const s = f.open();
  await s.save({ ...meeting, repeat: R.Daily, attachments: [file], reminderMinutes: 30 });
  const extra = occurrence(s, 15);
  await s.saveOccurrence({ ...extra, attachments: [file, url], reminderMinutes: 5 }, Edit.One, extra.startAt);
  await s.remove(meeting.id, Drop.One, at(14, 9));
  const selected = occurrence(s, 12);
  await s.saveOccurrence({ ...selected, attachments: [audio], reminderMinutes: 0 }, Edit.Following, selected.startAt);
  assert.deepEqual([occurrence(s, 11).reminderMinutes, ids(occurrence(s, 11))], [30, [file.id]]);
  assert.deepEqual([occurrence(s, 13).reminderMinutes, ids(occurrence(s, 13))], [0, [audio.id]]);
  assert.equal(occurrence(s, 14), undefined);
  const later = occurrence(s, 15);
  assert.deepEqual(new Set(ids(later)), new Set([audio.id, url.id]));
  assert.equal(later.reminderMinutes, 0);
  // 从带私人资料的例外，给整个后段加一份图片，不把私人网址扩散到每一次。
  await s.saveOccurrence({ ...later, attachments: [...later.attachments, image] }, Edit.All, later.occurrenceOriginalStart);
  assert.deepEqual(ids(occurrence(f.open(), 13)), [audio.id, image.id]);
  assert.deepEqual(new Set(ids(occurrence(s, 15))), new Set([audio.id, url.id, image.id]));
  const chosen = occurrence(s, 16);
  await s.saveOccurrence({ ...chosen, attachments: [], reminderMinutes: undefined }, Edit.One, chosen.startAt);
  assert.equal(occurrence(f.open(), 16).reminderMinutes, undefined);
  assert.deepEqual(ids(occurrence(f.open(), 16)), []);
  const restored = occurrence(s, 16);
  await s.saveOccurrence({ ...restored, attachments: [audio, image], reminderMinutes: 0 }, Edit.One,
    restored.occurrenceOriginalStart);
  assert.equal(occurrence(f.open(), 16).occurrenceOriginalStart, undefined);
});

test('不支持的提醒、重复的附件 ID、损坏的例外与不安全文件来源均拒绝且保留原始存档', async () => {
  const f = fixture();
  const s = f.open();
  await s.save(meeting);
  const prior = f.text();
  for (const fields of [
    { reminderMinutes: 3 }, { reminderMinutes: -1 }, { reminderMinutes: '10' }, { reminderMinutes: null },
    { attachments: null }, { attachments: [file, file] }, { attachments: [{ ...file, name: ' ' }] },
    ...['../secret.m4a', 'a/b.jpg', '/sdcard/external', '.hidden', 'a%2fb', 'a\\b', 'file://test.com/a'].map(source =>
      ({ attachments: [{ ...file, source }] })),
    ...['javascript:open()', '://a', 'https://', 'https://:123/x', 'https://\/ bad',
      'https://host:99999/path', 'http://bad\\other'].map(source => ({ attachments: [{ ...url, source }] })),
    { attachments: [{ ...file, kind: 'other' }] }
  ]) {
    await assert.rejects(s.save({ ...meeting, ...fields }));
    assert.equal(f.text(), prior);
  }
  for (const address of ['HTTP://a.me/q?x=1#2', 'https://[::1]:5555/file', url.source]) {
    assert.equal(isTimelineAttachmentUrl(address), true);
  }
  const series = { ...meeting, repeat: R.Daily, overrides: [{ ...meeting, originalStart: meeting.startAt,
    attachments: [{ ...url, source: 'file:///etc' }] }] };
  const broken = JSON.stringify({ version: 6, blocks: [series], tags: [] });
  const invalid = fixture(broken);
  assert.throws(() => invalid.open());
  assert.equal(invalid.text(), broken);
});
