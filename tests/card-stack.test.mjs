import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import { loadPortableEts } from '../scripts/load-portable-ets.mjs';

const bundle = await loadPortableEts();
const { CardStackLayout, deckDragDistance } = bundle.modules['components/CardStackLayout'];
after(() => bundle.close());

const viewport = 570;
const dock = 51;
const endGap = 4;
const chrome = 146;
const pageHeight = viewport + chrome;
const cards = [184, 196, 184, 196, 735];
const deck = new CardStackLayout(viewport, dock, cards, pageHeight);

function close(actual, expected) {
  assert.ok(Math.abs(actual - expected) < 1e-6, `${actual} ≠ ${expected}`);
}

function exposedBackCards(layout, at) {
  return layout.visibleSlots(at).filter(i => i < at.index && layout.paintHeight(i, at) > 1e-6);
}

test('第一张紧靠日期，第二张露出摘要和操作空间，第三张标题在底栏上方', () => {
  const at = deck.locate(0);
  assert.equal(at.index, 0);
  const [first, second, third] = [0, 1, 2].map(i => deck.sheetTop(i, at));
  assert.ok(first >= 0 && first <= 12);
  assert.ok(second - first >= 184 && third - second >= 125);
  assert.ok(viewport - dock - third > 58);
  assert.deepEqual([0, 1, 2].map(i => deck.tiltAt(deck.depthAt(i, at))), [0, 0, 32]);
  for (const i of [0, 1]) {
    assert.ok(deck.sheetTop(i, at) + deck.faceHeight(i) <= deck.sheetTop(i + 1, at));
    assert.ok(deck.paintTop(i, at) + deck.paintHeight(i, at) >= deck.sheetTop(i, at) + deck.faceHeight(i));
  }
});

test('每张卡跨过吸附点和半程时，卡面位置与倾角连续，顺序稳定', () => {
  for (let i = 0; i < cards.length - 1; i++) {
    const start = deck.start(i);
    const end = deck.start(i + 1);
    for (const fraction of [0.5, 1]) {
      const location = start + fraction * (end - start);
      const before = deck.locate(location - 0.0001);
      const after = deck.locate(location + 0.0001);
      for (let j = Math.max(0, i - 2); j < Math.min(cards.length, i + 4); j++) {
        assert.ok(Math.abs(deck.sheetTop(j, before) - deck.sheetTop(j, after)) < 0.001);
        assert.ok(Math.abs(deck.paintTop(j, before) - deck.paintTop(j, after)) < 0.001);
        assert.ok(Math.abs(deck.paintHeight(j, before) - deck.paintHeight(j, after)) < 0.001);
        const oldDepth = deck.depthAt(j, before);
        const newDepth = deck.depthAt(j, after);
        assert.ok(Math.abs(deck.tiltAt(oldDepth) - deck.tiltAt(newDepth)) < 0.001);
        assert.ok(Math.abs(deck.widthScaleAt(oldDepth) - deck.widthScaleAt(newDepth)) < 0.001);
        assert.ok(Math.abs(deck.opacityAt(oldDepth) - deck.opacityAt(newDepth)) < 0.001);
        if (j > i && deck.sheetTop(j, after) <= deck.sheetTop(j - 1, after)) {
          assert.equal(j, cards.length - 1);
          assert.equal(after.index, j - 1);
          assert.equal(deck.paintHeight(j - 1, after), 0);
        }
      }
    }
  }
});

test('长卡整张随手指推到卡尾，交接时共用的平卡跟手，反向原路返回', () => {
  const long = new CardStackLayout(viewport, dock, [590, 195, 205], pageHeight);
  const readingEnd = long.offsetAt(0, Number.MAX_SAFE_INTEGER, 0);
  const initialY = long.sheetTop(0, long.locate(0)) + chrome;
  const nextStart = long.sheetTop(1, long.locate(0)) + chrome;
  for (const offset of [0, 40, readingEnd, readingEnd + 1, long.start(1) - 1, long.start(1), readingEnd, 0]) {
    const at = long.locate(offset);
    if (offset <= readingEnd) {
      close(long.sheetTop(0, at) + chrome, initialY - offset);
      close(long.sheetTop(1, at) + chrome, nextStart);
      assert.equal(at.turn, 0);
      assert.equal(long.release(offset, 0, 1800), offset);
    } else {
      close(long.sheetTop(1, at) + chrome, nextStart - (offset - readingEnd));
      assert.equal(long.tiltAt(long.depthAt(1, at)), 0);
    }
  }
  const parked = long.locate(long.start(1));
  assert.ok(long.sheetTop(0, parked) >= 0);
  assert.deepEqual(exposedBackCards(long, parked), [0]);
  assert.ok(long.sheetTop(0, parked) + long.faceHeight(0) > long.sheetTop(1, parked));
});

test('轻微晃动留给点击，缓冲后每推一 vp 移动一 vp，两方向一致', () => {
  for (const value of [-8, -3, 0, 3, 8]) assert.ok(deckDragDistance(value) === 0);
  close(deckDragDistance(12), 1);
  close(deckDragDistance(16), 4);
  close(deckDragDistance(97) - deckDragDistance(96), 1);
  close(deckDragDistance(-123), -deckDragDistance(123));
});

test('慢放保留原卡，越过分界可翻页，快推与反向收手只影响眼前相邻落点', () => {
  const next = deck.start(1);
  assert.equal(deck.release(next * 0.51, 0, 0), 0);
  assert.equal(deck.release(next * 0.56, 0, 0), next);
  assert.equal(deck.release(next * 0.5, next, 0), next);
  assert.equal(deck.release(next * 0.43, 0, 1600), next);
  assert.equal(deck.release(next * 0.35, 0, 9000), 0);
  assert.equal(deck.release(next * 0.59, next, -1600), 0);
  const far = deck.offsetAt(2, 0, 0.7);
  assert.equal(deck.release(far, 0, 9000), deck.start(3));
  assert.equal(deck.release(next * 0.49, next * 0.49 - 2, 9000), 0);
});

test('首尾不越界，末张长卡的最后一行能推到胶囊上方，单张和空结果都能收住', () => {
  for (const heights of [[], [760], [188, 760]]) {
    const sized = new CardStackLayout(viewport, dock, heights, pageHeight);
    assert.equal(sized.clamp(-25), 0);
    assert.equal(sized.clamp(9999), sized.limit);
    assert.equal(sized.locate(sized.limit).index, Math.max(0, heights.length - 2));
    if (heights.length === 0) {
      const at = sized.locate(0);
      assert.deepEqual(sized.visibleSlots(at), []);
      assert.deepEqual(exposedBackCards(sized, at), []);
      assert.equal(sized.paintHeight(0, at), 0);
      close(sized.sheetTop(0, at), sized.inset);
      close(sized.sheetTop(0, deck.locate(deck.start(1) / 2)), sized.inset);
    } else {
      const at = sized.locate(sized.limit);
      const last = heights.length - 1;
      close(sized.sheetTop(last, at) + sized.faceHeight(last), viewport - dock - endGap);
      assert.ok(sized.paintTop(last, at) + sized.paintHeight(last, at) >= viewport - dock - endGap);
      assert.equal(sized.release(sized.limit, 0, 2000), sized.limit);
    }
  }
});

test('搜索、展开月历和窗口改尺后保留阅读位置或翻页进度，长清单只挂载邻近卡片', () => {
  const heights = Array(400).fill(400);
  const original = new CardStackLayout(viewport, dock, heights, pageHeight);
  for (const smaller of [0, 64, 100, 210, 320, 844]) {
    const sized = new CardStackLayout(smaller, dock, heights, pageHeight);
    assert.ok(sized.inset <= Math.max(0, smaller - dock));
    assert.ok(sized.step > 0);
    const turn = sized.locate(sized.offsetAt(210, 0, 0.39));
    assert.equal(turn.index, 210);
    close(turn.turn, 0.39);
    assert.ok(sized.visibleSlots(turn).length < 20);
    const reading = original.locate(original.start(210) + 26);
    close(sized.locate(sized.offsetAt(210, reading.reading, 0)).reading, 26);
  }
});

test('末张与倒数第二张完整平铺，卡尾在底栏上方停住，继续上推或松手没有额外一档', () => {
  for (const faces of [[168, 184, 182], [174, 174, 219, 174, 174, 174], Array(30).fill(172)]) {
    const sized = new CardStackLayout(viewport, dock, faces, pageHeight);
    const last = faces.length - 1;
    const end = sized.locate(sized.limit);
    assert.equal(end.index, last - 1);
    assert.equal(end.turn, 0);
    close(end.reading, 0);
    close(sized.sheetTop(last, end) - sized.sheetTop(last - 1, end), faces[last - 1] + 7);
    close(sized.sheetTop(last, end) + faces[last], viewport - dock - endGap);
    for (const i of [last - 1, last]) {
      assert.equal(sized.tiltAt(sized.depthAt(i, end)), 0);
      assert.ok(sized.paintTop(i, end) + sized.paintHeight(i, end) >= sized.sheetTop(i, end) + faces[i]);
    }
    assert.deepEqual(sized.locate(sized.clamp(sized.limit + 500)), end);
    assert.equal(sized.release(sized.limit + 500, 0, 3000), sized.limit);
    assert.equal(sized.start(last), sized.limit);
    assert.equal(sized.offsetAt(last, 0, 0), sized.limit);
    const from = sized.start(last - 2);
    assert.equal(sized.release(from + (sized.limit - from) * 0.8, from, 0), sized.limit);
    assert.equal(sized.release(from + (sized.limit - from) * 0.2, sized.limit, 0), from);
    close(sized.sheetTop(last - 1, sized.locate(sized.limit - 1)), sized.sheetTop(last - 1, end) + 1);
  }
});

test('跨过末尾时整叠卡片共用一段有阻力的位移，各层间距和遮挡范围稳定，松手回到原落点', () => {
  for (const [height, faces] of [[570, [174, 174, 219, 174, 174, 174]], [367, [214, 219, 185]], [367, [210, 219, 760]]]) {
    const sized = new CardStackLayout(height, dock, faces, height + chrome);
    const end = sized.locate(sized.limit);
    assert.equal(sized.locate(sized.dragBy(sized.limit - 12, 10)).endLift, 0);
    const nudges = [12, 36, 60, 10000].map(extra => sized.dragBy(sized.limit - 12, 12 + extra));
    const lifts = nudges.map(pos => sized.locate(pos).endLift);
    assert.ok(lifts[0] > 0 && lifts[0] < 12);
    assert.ok(lifts[2] > lifts[1] && lifts[2] - lifts[1] < lifts[1] - lifts[0]);
    assert.ok(lifts[3] > lifts[2] && lifts[3] <= 32);
    for (const pos of nudges) {
      const frame = sized.locate(pos);
      assert.deepEqual({ ...frame, endLift: 0 }, end);
      assert.deepEqual(sized.visibleSlots(frame), sized.visibleSlots(end));
      for (const i of sized.visibleSlots(frame)) {
        close(sized.sheetTop(i, frame), sized.sheetTop(i, end));
        close(sized.paintTop(i, frame), sized.paintTop(i, end));
        close(sized.paintHeight(i, frame), sized.paintHeight(i, end));
      }
      const target = sized.release(pos, sized.limit - 12, 2500);
      assert.deepEqual(sized.locate(target), end);
    }
  }
});

test('快推与慢推的卡堆位移一致，反拖只收回看得见的位移，随后可继续翻回', () => {
  const limit = deck.limit;
  const whole = deck.dragBy(limit, 120);
  let stepped = limit;
  for (let i = 0; i < 24; i++) stepped = deck.dragBy(stepped, 5);
  close(whole, stepped);
  const saturated = deck.dragBy(whole, 10000);
  const back = deck.dragBy(saturated, -3);
  close(back, saturated - 3);
  close(deck.dragBy(back, -(back - limit + 21)), limit - 21);
  const caught = limit + (whole - limit) / 2;
  close(deck.dragBy(caught, 0), caught);
  assert.ok(deck.dragBy(caught, 7) > caught);
  assert.equal(deck.release(caught, limit, -900), limit);
});

test('单张和已露全的两张短卡也有末尾反馈，空清单和清单起点不产生反向位移', () => {
  for (const faces of [[], [180], [170, 180]]) {
    const sized = new CardStackLayout(viewport, dock, faces, pageHeight);
    assert.equal(sized.limit, 0);
    assert.equal(sized.dragBy(0, -50), 0);
    const pushed = sized.dragBy(0, 65);
    const frame = sized.locate(pushed);
    if (!faces.length) {
      assert.equal(pushed, 0);
      continue;
    }
    assert.ok(frame.endLift > 0);
    const rest = sized.locate(sized.release(pushed, 0, 500));
    assert.equal(rest.endLift, 0);
    for (const i of sized.visibleSlots(frame)) close(sized.sheetTop(i, frame), sized.sheetTop(i, rest));
  }
  assert.equal(deck.dragBy(0, -90), 0);
  assert.equal(deck.locate(deck.dragBy(0, 90)).endLift, 0);
});

test('窗口刚好放下末组时，重新测量一 vp 以内的变化不会突然挪动卡面', () => {
  const faces = [174, 174, 174, 190, 182];
  const penultimate = faces.length - 2;
  const fits = dock + endGap + 10 + faces[penultimate] + 7 + faces.at(-1);
  const layouts = [-0.4, 0, 0.4].map(delta => new CardStackLayout(fits + delta, dock, faces, fits + chrome + delta));
  for (const index of [penultimate, penultimate + 1]) {
    const tops = layouts.map(sized => sized.sheetTop(index, sized.locate(sized.start(penultimate))));
    assert.ok(Math.max(...tops) - Math.min(...tops) < 1);
  }
});

test('窄屏先读完倒数第二张，末张跟手盖过它的下沿，往返都能中途停读', () => {
  for (const [height, faces] of [[367, [214, 219, 185]], [285, [140, 900]], [367, [190, 720, 690]]]) {
    const sized = new CardStackLayout(height, dock, faces, height + chrome);
    const penultimate = faces.length - 2;
    const last = penultimate + 1;
    const start = sized.start(penultimate);
    const at = sized.locate(start);
    const firstTop = sized.sheetTop(penultimate, at);
    const nextTop = sized.sheetTop(last, at);
    const joined = start + firstTop + faces[penultimate] + 7 - nextTop;
    assert.ok(firstTop >= sized.inset && nextTop + 50 <= height - dock);
    for (const offset of [start, (start + joined) / 2, joined, sized.limit, (joined + sized.limit) / 2, start]) {
      const frame = sized.locate(offset);
      close(sized.sheetTop(penultimate, frame), firstTop - (Math.min(joined, offset) - start));
      close(sized.sheetTop(last, frame), nextTop - Math.max(0, offset - joined));
      close(sized.release(offset, start, 1800), offset);
      assert.equal(sized.tiltAt(sized.depthAt(penultimate, frame)), 0);
      assert.equal(sized.tiltAt(sized.depthAt(last, frame)), 0);
    }
    const edge = sized.locate(joined);
    close(sized.sheetTop(penultimate, edge) + faces[penultimate] + 7, sized.sheetTop(last, edge));
    const end = sized.locate(sized.limit);
    assert.ok(sized.sheetTop(last, end) < sized.sheetTop(penultimate, end) + faces[penultimate]);
    if (height === 367 && faces[penultimate] === 219) {
      assert.ok(sized.sheetTop(penultimate, end) >= 0);
      assert.ok(sized.sheetTop(last, end) - sized.sheetTop(penultimate, end) >= 65);
    }
    close(sized.sheetTop(last, end) + faces[last], height - dock - endGap);
    for (let past = 0; past < penultimate; past++) {
      if (sized.sheetTop(penultimate, end) <= sized.sheetTop(past, end)) assert.equal(sized.paintHeight(past, end), 0);
    }
  }
});

test('窄屏中段的下张留在原位，读完上张的卡尾后才翻页', () => {
  const compact = new CardStackLayout(367, dock, [214, 219, 185, 190, 174, 214], 367 + chrome);
  for (const index of [0, 1]) {
    const head = compact.locate(compact.start(index));
    const end = compact.locate(compact.offsetAt(index, Number.MAX_SAFE_INTEGER, 0));
    assert.ok(compact.paintTop(index, head) >= 0 && end.reading > 0);
    assert.ok(compact.sheetTop(index + 1, head) + 50 <= 367 - dock);
    close(compact.paintTop(index, end), Math.max(0, compact.sheetTop(index, end) - 7));
    close(compact.sheetTop(index, end) + compact.faceHeight(index) + 7, compact.sheetTop(index + 1, end));
    close(compact.sheetTop(index + 1, end), compact.sheetTop(index + 1, head));
  }
});

test('单张仍能居中阅读，仅两张短卡时直接读全，两张长卡按实际溢出距离收住', () => {
  const single = new CardStackLayout(viewport, dock, [185], pageHeight);
  close(chrome + single.sheetTop(0, single.locate(0)) + 185 / 2, pageHeight / 2);
  assert.equal(single.limit, 0);
  for (const first of [120, 680]) {
    const pair = new CardStackLayout(viewport, dock, [first, 150], pageHeight);
    const head = pair.locate(0);
    close(pair.sheetTop(0, head), pair.inset);
    close(pair.limit, Math.max(0, pair.inset + first + 7 + 150 - (viewport - dock - endGap)));
    const end = pair.locate(pair.limit);
    if (first === 120) {
      assert.equal(pair.limit, 0);
      close(pair.sheetTop(0, end) + first + 7, pair.sheetTop(1, end));
    }
    else close(pair.sheetTop(1, end) + 150, viewport - dock - endGap);
  }
});

test('长卡、矮卡和高窗口下，末张沿上推方向进入双卡落点，长清单末尾仍贴近底栏', () => {
  for (const [height, faces] of [[920, [120, 610, 130]], [850, Array(400).fill(125)], [570, [780, 156, 175]]]) {
    const sized = new CardStackLayout(height, dock, faces, height + chrome);
    const last = faces.length - 1;
    let previous = Infinity;
    const from = sized.start(Math.max(0, last - 3));
    for (let i = 0; i <= 80; i++) {
      const at = sized.locate(from + (sized.limit - from) * i / 80);
      const y = sized.sheetTop(last, at);
      assert.ok(y <= previous + 1e-6);
      previous = y;
    }
    close(previous + faces[last], height - dock - endGap);
    const end = sized.locate(sized.limit);
    if (faces.length > 100) {
      assert.ok(exposedBackCards(sized, end).length > 4);
      assert.ok(sized.visibleSlots(end).length < 20);
    }
  }
});

test('显示区足够时两张中央卡完整居中，最近两张历史卡只露标题，下叠保留倾角', () => {
  const faces = [174, 216, 174, 192, 174, 174, 186];
  const sized = new CardStackLayout(720, dock, faces, 720 + chrome);
  const at = sized.locate(sized.start(3));
  const top = sized.sheetTop(3, at);
  const bottom = sized.sheetTop(4, at) + sized.faceHeight(4);
  close(chrome + (top + bottom) / 2, (720 + chrome) / 2);
  for (const i of [3, 4]) {
    assert.equal(sized.tiltAt(sized.depthAt(i, at)), 0);
    assert.ok(sized.paintTop(i, at) + sized.paintHeight(i, at) >= sized.sheetTop(i, at) + faces[i]);
  }
  assert.ok(top + faces[3] < sized.sheetTop(4, at));
  assert.equal(sized.paintHeight(0, at), 0);
  for (const i of [1, 2]) {
    const depth = sized.depthAt(i, at);
    assert.equal(sized.opacityAt(depth), 1);
    assert.ok(Math.abs(sized.tiltAt(depth)) < 8);
    const peek = sized.sheetTop(i + 1, at) - sized.sheetTop(i, at);
    assert.ok(sized.sheetTop(i, at) >= 0 && sized.paintHeight(i, at) > peek);
    assert.ok(peek <= 34 && peek >= 26);
  }
  for (const i of [5, 6]) {
    assert.ok(sized.tiltAt(sized.depthAt(i, at)) > 0);
    assert.ok(sized.sheetTop(i, at) > bottom && sized.sheetTop(i, at) < 720 - dock);
  }
});

test('中途反拖时仍有两张正面，完全遮住的后卡和最远的下叠在挂载或卸载时不可见', () => {
  const sized = new CardStackLayout(viewport, dock, Array(28).fill(180), pageHeight);
  for (const t of [0, 0.2, 0.49, 0.5, 0.51, 0.9, 1, 0.52, 0]) {
    const at = sized.locate(sized.offsetAt(11, 0, t));
    const slots = sized.visibleSlots(at);
    const depths = slots.map(i => sized.depthAt(i, at));
    const flat = depths.filter(depth => sized.tiltAt(depth) === 0);
    assert.ok(flat.length >= 2 && flat.length <= 3);
    assert.equal(sized.tiltAt(sized.depthAt(12, at)), 0);
    assert.equal(sized.paintHeight(slots[0], at), 0);
    assert.equal(sized.opacityAt(depths.at(-1)), 0);
    assert.ok(slots.length <= 10);
  }
});

test('中段正反推最多露两张历史卡，旧卡完全被下一张遮住', () => {
  const faces = Array(15).fill(170);
  const sized = new CardStackLayout(viewport, dock, faces, pageHeight);
  for (let i = 0; i < faces.length - 4; i++) {
    const previous = exposedBackCards(sized, sized.locate(sized.start(i)));
    assert.deepEqual(previous, Array.from({ length: Math.min(i, 2) }, (_, n) => i - Math.min(i, 2) + n));
    for (const fraction of [0, 0.25, 0.49, 0.5, 0.51, 0.8, 1, 0.6, 0.3, 0]) {
      const frame = sized.locate(sized.offsetAt(i, 0, fraction));
      const exposed = exposedBackCards(sized, frame);
      assert.ok(exposed.length <= 2);
      for (const j of exposed) assert.ok(sized.sheetTop(j, frame) >= sized.inset - 1e-6);
      for (const j of previous) assert.equal(sized.opacityAt(sized.depthAt(j, frame)), 1);
      if (i >= 2 && fraction >= 0.5) {
        assert.equal(sized.paintHeight(i - 2, frame), 0);
        close(sized.sheetTop(i - 2, frame), sized.sheetTop(i - 1, frame));
      }
    }
  }
});

test('从倒数第四张开始翻，已露出的卡逐层留在原叠，反向沿原路回到两层', () => {
  const faces = Array(12).fill(172);
  const sized = new CardStackLayout(viewport, dock, faces, pageHeight);
  const first = faces.length - 4;
  const from = sized.start(first);
  const to = sized.limit;
  const parked = [first, first + 1, first + 2].map(i => exposedBackCards(sized, sized.locate(sized.start(i))));
  assert.deepEqual(parked, [[first - 2, first - 1], [first - 2, first - 1, first],
    [first - 2, first - 1, first, first + 1]]);
  for (const t of [0, 0.13, 0.44, 0.68, 0.91, 1, 0.84, 0.57, 0.32, 0]) {
    const at = sized.locate(from + (to - from) * t);
    const exposed = exposedBackCards(sized, at);
    assert.ok(exposed.includes(first - 1) && exposed.includes(first - 2));
    for (const i of exposed) {
      const edge = sized.sheetTop(i + 1, at);
      assert.ok(edge > sized.sheetTop(i, at));
      assert.ok(sized.paintTop(i, at) + sized.paintHeight(i, at) > edge);
      assert.equal(sized.opacityAt(sized.depthAt(i, at)), 1);
    }
  }
  const end = sized.locate(to);
  const peek = i => sized.sheetTop(i + 1, end) - sized.sheetTop(i, end);
  assert.ok(peek(first + 1) > peek(first) && peek(first) >= 34);
});

test('从课程汇报回推六级考试时，前卡跟手移动并逐渐揭开完整后卡，反推沿原路盖回', () => {
  for (const height of [367, 534, 570, 720]) {
    const faces = [174, 174, 219, 174, 174, 174, 214];
    const sized = new CardStackLayout(height, dock, faces, height + chrome);
    const exam = 2;
    const report = 3;
    const start = sized.offsetAt(exam, Number.MAX_SAFE_INTEGER, 0);
    const next = sized.start(report);
    const previous = sized.locate(start);
    const initialTop = sized.sheetTop(exam, previous);
    const initialFront = sized.sheetTop(report, previous);
    if (height >= 534) close(previous.reading, 0);
    assert.ok(next - start > 80);
    close(initialTop + sized.faceHeight(exam) + 7, initialFront);
    const parkedTop = sized.sheetTop(exam, sized.locate(next));
    for (const fraction of [1, 0.9, 0.65, 0.5, 0.28, 0, 0.34, 0.72, 1]) {
      const offset = start + (next - start) * fraction;
      const at = sized.locate(offset);
      close(sized.sheetTop(report, at), initialFront - (offset - start));
      assert.equal(sized.faceHeight(exam), faces[exam]);
      assert.equal(sized.opacityAt(sized.depthAt(exam, at)), 1);
      if (fraction > 0.28) assert.ok(sized.sheetTop(report, at) < sized.sheetTop(exam, at) + faces[exam]);
    }
    const tucked = sized.locate(next);
    assert.ok(sized.sheetTop(report, tucked) - parkedTop <= 34);
    assert.ok(exposedBackCards(sized, tucked).includes(exam));
  }
});

test('书单、健身和六级考试同向叠放，前卡的圆角有后卡垫底，两道后卡底边都藏在前卡内', () => {
  for (const viewportHeight of [367, 570, 720]) {
    const heights = [760, 174, 215, 190];
    const sized = new CardStackLayout(viewportHeight, dock, heights, viewportHeight + chrome);
    const at = sized.locate(sized.start(2));
    assert.deepEqual(exposedBackCards(sized, at), [0, 1]);
    for (const i of [0, 1]) {
      const back = sized.sheetTop(i, at);
      const front = sized.sheetTop(i + 1, at);
      const drawnEnd = sized.paintTop(i, at) + sized.paintHeight(i, at);
      assert.ok(front > back && front < back + heights[i]);
      assert.ok(drawnEnd >= front + 18 && drawnEnd < back + heights[i]);
      assert.ok(drawnEnd < front + heights[i + 1]);
      assert.ok(sized.widthScaleAt(sized.depthAt(i, at)) < sized.widthScaleAt(sized.depthAt(i + 1, at)));
    }
  }
});
