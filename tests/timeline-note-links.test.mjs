import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import { loadPortableEts } from '../scripts/load-portable-ets.mjs';

const bundle = await loadPortableEts();
after(() => bundle.close());
const { timelineNoteParts } = bundle.modules['domain/TimelineNoteLinks'];

function links(note) {
  const parts = timelineNoteParts(note);
  assert.equal(parts.map(part => part.text).join(''), note);
  for (const part of parts) assert.equal(note.slice(part.start, part.start + part.text.length), part.text);
  return parts.filter(part => part.href).map(part => part.href);
}

test('备注识别多条地址并保留中英文、换行、emoji、原始大小写及标点', () => {
  assert.deepEqual(links('📚看HTTPS://example.com/资料?q=课#一，然后看（www.example.net）。\n同：https://example.com/资料?q=课#一。'),
    ['HTTPS://example.com/资料?q=课#一', 'https://www.example.net', 'https://example.com/资料?q=课#一']);
  assert.deepEqual(links('首页：https://例子.公司/资料，网址：www.example.net.'), ['https://例子.公司/资料', 'https://www.example.net']);
  assert.deepEqual(links('资料:https://example.com请看'), ['https://example.com']);
  assert.deepEqual(links('(https://example.com/wiki/Title_(topic)). http://[::1]:8080/q?x=1'),
    ['https://example.com/wiki/Title_(topic)', 'http://[::1]:8080/q?x=1']);
  assert.deepEqual(links('https://x.test/path,https://y.test/next.'), ['https://x.test/path', 'https://y.test/next']);
});

test('输入中的不完整地址、非网页协议及词中伪前缀保留为普通文字', () => {
  for (const value of ['', '会议待办', 'https://', 'www.', 'http://:8080', 'www.example', 'xhttps://example.com',
    'ftp://www.example.com', 'person@www.example.com', 'javascript:alert(1)', 'https://example.com:99999/a',
    'https://trusted.example@other.example', 'https://example.com:abc/资料', 'https://example.com:80abc/path']) {
    assert.deepEqual(links(value), [], value);
  }
});
