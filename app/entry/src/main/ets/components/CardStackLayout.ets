// 所有距离都用 vp。每张卡先走完超出可读区域的内容，再与下一张之间吸附。
export interface DeckLocation {
  index: number;
  reading: number;
  turn: number;
  endLift: number; // 末尾回弹时整叠卡片共同上移的距离。
}

// 卡堆的坐标始终从日历下边缘开始。每个落点给中央两张分配阅读空间。
const PAIR_GAP: number = 7;
const HISTORY_LIMIT: number = 2;
const HISTORY_PEEK: number = 34;
const END_GAP: number = 4;
const MAX_END_LIFT: number = 32;
const CORNER_OVERLAP: number = 24;
const UPCOMING_LAYERS: number = 3;
const MIN_TURN: number = 48;

interface DeckStop {
  top: number;
  upper: number;
  read: number;
  history: number[]; // 从近到远，各张后卡的上沿。
  upcoming: number[]; // 中央两张以下的卡沿。
}

export class CardStackLayout {
  viewport: number;
  inset: number;
  step: number;
  limit: number = 0;
  private maxEndLift: number;
  private faces: number[] = [];
  private stops: DeckStop[] = [];
  private starts: number[] = [];
  private readEnds: number[] = [];

  constructor(viewport: number, bottomInset: number, heights: number[], pageHeight: number = viewport) {
    this.viewport = Math.max(0, viewport);
    const usable = Math.max(0, this.viewport - bottomInset);
    this.inset = Math.min(10, usable * 0.04);
    this.step = Math.max(56, Math.min(270, (usable - this.inset) * 0.47));
    this.faces = heights.map((h: number) => h > 0 ? h : this.step - 6);
    const center = this.viewport - pageHeight / 2;
    const last = heights.length - 1;
    this.maxEndLift = Math.min(MAX_END_LIFT, usable * 0.1, (this.faces[last] ?? 0) / 4);
    for (let i = 0; i < last - 1; i++) {
      this.stops.push(this.makeStop(i, usable, center));
    }
    if (last >= 0) {
      this.stops.push(this.makeEndStop(last, usable, center));
      this.alignEndApproach();
    }
    let start = 0;
    for (let i = 0; i < this.stops.length; i++) {
      this.starts.push(start);
      this.limit = start + this.stops[i].read;
      this.readEnds.push(this.limit);
      if (i + 1 < this.stops.length) {
        const travel = this.restingTop(i + 1, i) - this.restingTop(i + 1, i + 1);
        start = this.limit + Math.max(MIN_TURN, travel);
      }
    }
  }

  private makeStop(index: number, usable: number, center: number): DeckStop {
    const last = this.faces.length - 1;
    const above = Math.min(HISTORY_LIMIT, index);
    const below = Math.min(UPCOMING_LAYERS, Math.max(0, last - index - 1));
    const room = Math.max(1, usable - 2 * this.inset);
    const strip = Math.min(HISTORY_PEEK, room * 0.11);
    const firstFace = this.faces[index];
    const secondFace = this.faces[index + 1];
    const reservedAbove = above * strip;
    const spare = room - firstFace - PAIR_GAP - secondFace - reservedAbove;
    const edge = Math.min(26, room * 0.045, Math.max(room * 0.025, spare / Math.max(1, below)));
    const reservedBelow = Math.min(below * edge, Math.max(below > 0 ? 14 : 0, spare));
    const minimum = this.inset + reservedAbove;
    const roomForFaces = usable - minimum - PAIR_GAP;
    // 放得下两张整卡时优先露全。放不下时逐渐给下叠留边，避免只差几 vp 就截掉正文标题。
    const overflow = Math.max(0, firstFace + secondFace - roomForFaces);
    const budget = Math.max(2, roomForFaces - Math.min(this.inset + reservedBelow, overflow));
    const upper = Math.min(firstFace, Math.max(budget * 0.52, budget - secondFace));
    const lower = Math.min(secondFace, Math.max(1, budget - upper));
    const pairHeight = upper + PAIR_GAP + lower;
    let top = Math.max(minimum, Math.min(center - pairHeight / 2, usable - this.inset - reservedBelow - pairHeight));
    if (index === 0) {
      top = Math.max(this.inset, top - 18);
    }
    const history: number[] = [];
    for (let d = 1; d <= above; d++) history.push(top - d * strip);
    const freeBelow = usable - top - pairHeight - PAIR_GAP;
    const step = Math.max(10, Math.min(64, freeBelow / Math.max(1, below)));
    const upcoming: number[] = [];
    for (let d = 2; d <= Math.min(last - index, UPCOMING_LAYERS + 3); d++) {
      upcoming.push(top + pairHeight + PAIR_GAP + this.pileDistance(d - 2, below, step));
    }
    return { top, upper, read: firstFace - upper, history, upcoming };
  }

  private makeEndStop(last: number, usable: number, center: number): DeckStop {
    let bottom = Math.max(0, usable - END_GAP);
    if (last === 0) {
      const h = this.faces[0];
      const top = Math.max(this.inset, Math.min(bottom - h, center - h / 2));
      return { top, upper: h, read: Math.max(0, top + h - bottom), history: [], upcoming: [] };
    }
    const index = last - 1;
    const first = this.faces[index];
    const second = this.faces[last];
    // 内容少到可以整副平铺时，本身的高度就是边界。
    const naturalBottom = this.faces.reduce((sum: number, h: number) => sum + h, this.inset + last * PAIR_GAP);
    bottom = Math.min(bottom, naturalBottom);
    const strip = Math.min(HISTORY_PEEK, Math.max(0, bottom - 2 * this.inset) * 0.11);
    // 最后一组由底栏向上排，溢出的长度就是还能推动的距离。
    const fittedTop = bottom - first - PAIR_GAP - second;
    const shortfall = Math.max(0, this.inset - fittedTop);
    const historyRoom = Math.min(shortfall, Math.min(index, HISTORY_LIMIT) * strip);
    const top = Math.max(fittedTop, this.inset + historyRoom);
    const room = Math.max(0, bottom - top - PAIR_GAP);
    // 空间紧时让末张先露出卡头，给前一张留下读到操作行的空间。
    const upper = Math.min(first, room - Math.min(second, 64, room * 0.4));
    const read = Math.max(0, top + first + PAIR_GAP + second - bottom);
    const roomAbove = Math.max(0, top - this.inset);
    const count = Math.min(index, Math.max(HISTORY_LIMIT + 2, Math.floor(roomAbove / (2 * HISTORY_PEEK))));
    return { top, upper, read, history: this.historyTops(index, top, count), upcoming: [] };
  }

  private alignEndApproach(): void {
    const end = this.stops.length - 1;
    const oldest = end - this.stops[end].history.length;
    for (let i = end - 1; i >= 0; i--) {
      const stop = this.stops[i];
      const layers = i - oldest;
      const travel = Math.min(MIN_TURN, stop.upper / 2);
      const shift = Math.max(0, this.stops[i + 1].top + travel - (stop.top + stop.upper + PAIR_GAP));
      if (layers <= HISTORY_LIMIT && shift === 0 && i + UPCOMING_LAYERS + 2 < end) break;
      // 保留进入尾段时就在场的卡。高窗口里给即将进入末组的卡留出跟手移动的距离。
      stop.top += shift;
      if (layers > HISTORY_LIMIT) stop.history = this.historyTops(i, stop.top, layers);
      else if (shift > 0) stop.history = stop.history.map((y: number) => y + shift);
      for (let j = 0; j < stop.upcoming.length; j++) {
        stop.upcoming[j] = Math.max(stop.upcoming[j] + shift, this.restingTop(i + j + 2, i + 1));
      }
    }
  }

  private historyTops(index: number, top: number, count: number): number[] {
    const history: number[] = [];
    const room = Math.max(0, top - this.inset);
    const rim = Math.min(9, room / Math.max(1, count));
    let edge = top;
    for (let d = 1; d <= count; d++) {
      const space = edge - this.inset;
      const older = count - d;
      const spare = Math.max(0, space - (older + 1) * rim);
      const peek = d === 1 && older > 0 ? rim + spare * 0.70 : space - older * rim;
      const face = this.faces[index - d];
      edge -= Math.min(peek, face - Math.min(CORNER_OVERLAP + 1, face / 4));
      history.push(edge);
    }
    return history;
  }

  clamp(offset: number): number {
    return Math.max(0, Math.min(this.limit, offset));
  }

  dragBy(position: number, delta: number): number {
    const next = position + delta;
    if (next <= this.limit || delta <= 0 || this.maxEndLift === 0) {
      return Math.max(0, Math.min(this.limit + this.maxEndLift, next));
    }
    const lift = Math.max(0, position - this.limit);
    const push = next - Math.max(position, this.limit);
    // 每推一段只消耗剩余弹性行程的一部分，结果与手势的采样频率无关。回拉直接跟手。
    return this.limit + lift + (this.maxEndLift - lift) * (1 - Math.exp(-push / this.maxEndLift));
  }

  start(index: number): number {
    return this.starts[index] ?? (index === this.faces.length - 1 ? this.limit : 0);
  }

  faceHeight(index: number): number {
    return this.faces[index] ?? this.step;
  }

  locate(value: number): DeckLocation {
    const offset = this.clamp(value);
    let lo = 0;
    let hi = this.starts.length - 1;
    while (lo < hi) {
      const mid = Math.ceil((lo + hi) / 2);
      if (this.starts[mid] <= offset) lo = mid;
      else hi = mid - 1;
    }
    const end = this.readEnds[lo] ?? 0;
    const travel = this.start(lo + 1) - end;
    return { index: lo, reading: Math.min(offset, end) - this.start(lo),
      turn: travel > 0 ? Math.max(0, offset - end) / travel : 0,
      endLift: Math.min(this.maxEndLift, Math.max(0, value - this.limit)) };
  }

  offsetAt(index: number, reading: number, turn: number): number {
    if (index >= this.starts.length) return this.limit;
    const start = this.start(index);
    const end = this.readEnds[index] ?? 0;
    if (index + 1 < this.starts.length && turn > 0) {
      return end + (this.start(index + 1) - end) * turn;
    }
    return Math.min(start + reading, end);
  }

  private pileDistance(layers: number, count: number, step: number): number {
    if (layers === 0 || count <= 1 || step >= 32) return layers * step;
    // 空间很小时把最近一层的标题露出来，更远的层只留卡边。
    const extra = Math.min(32 - step, (step - 5) * (count - 1));
    return layers * step + extra * Math.max(0, (count - layers) / (count - 1));
  }

  private restingTop(index: number, stopIndex: number): number {
    const stop = this.stops[stopIndex];
    if (!stop) return this.inset;
    const depth = index - stopIndex;
    if (depth < 0) return stop.history[Math.min(-depth, stop.history.length) - 1] ?? stop.top;
    if (depth === 0) return stop.top;
    if (depth === 1) return stop.top + stop.upper + PAIR_GAP;
    return stop.upcoming[Math.min(depth - 2, stop.upcoming.length - 1)] ?? this.viewport;
  }

  sheetTop(index: number, at: DeckLocation): number {
    const start = this.restingTop(index, at.index);
    const t = at.turn;
    if (t === 0) {
      if (at.index === this.stops.length - 1 && at.index + 1 < this.faces.length) {
        const firstRead = this.faces[at.index] - this.stops[at.index].upper;
        // 先读完前卡并停住它，再让末张推上来遮住它的下沿。回拉逐步揭开同一张卡。
        if (index === at.index) return start - Math.min(at.reading, firstRead);
        if (index === at.index + 1) return start - Math.max(0, at.reading - firstRead);
      }
      if (index === at.index) return start - at.reading;
      return start;
    }
    if (!this.stops[at.index + 1]) return start;
    const end = this.restingTop(index, at.index + 1);
    if (index <= at.index) {
      // 以最靠后的上沿为基准。叠满前保留已有卡位，叠满后相邻卡一起退一层。
      const back = this.restingTop(0, at.index);
      const nextBack = this.restingTop(0, at.index + 1);
      const fromEdge = start - back;
      const toEdge = end - nextBack;
      const slide = Math.min(1, 2 * t);
      const reading = index === at.index ? at.reading * (1 - t) : 0;
      return back + (nextBack - back) * t + fromEdge + (toEdge - fromEdge) * slide * (2 - slide) -
        reading;
    }
    return start + (end - start) * t;
  }

  private coveringEdge(index: number, at: DeckLocation): number {
    let edge = this.sheetTop(index + 1, at);
    if (index < at.index - 1) edge = Math.min(edge, this.sheetTop(at.index, at));
    if (index < at.index && at.index === this.faces.length - 2) {
      edge = Math.min(edge, this.sheetTop(at.index + 1, at));
    }
    return edge;
  }

  private underFront(index: number, at: DeckLocation): boolean {
    return index < at.index || (index === at.index && index === this.faces.length - 2);
  }

  paintTop(index: number, at: DeckLocation): number {
    const top = this.sheetTop(index, at);
    if (this.underFront(index, at)) {
      const exposed = Math.max(0, this.coveringEdge(index, at) - top);
      return Math.max(0, top - Math.min(PAIR_GAP, exposed));
    }
    return Math.max(0, top - PAIR_GAP);
  }

  paintHeight(index: number, at: DeckLocation): number {
    if (index < 0 || index >= this.faces.length) return 0;
    const top = this.sheetTop(index, at);
    let end = Math.min(this.viewport, top + this.faceHeight(index) + PAIR_GAP);
    if (index + 1 < this.faces.length) {
      const front = this.coveringEdge(index, at);
      // 后卡的完整卡身延伸到前卡圆角下面。裁去已被盖住的部分，避免长卡从下一张底部穿出来。
      let overlap = this.faceHeight(index + 1);
      if (this.underFront(index, at)) overlap = Math.min(CORNER_OVERLAP, 2 * Math.max(0, front - top));
      else if (index === at.index) overlap = CORNER_OVERLAP;
      end = Math.min(end, front + overlap);
    }
    return Math.max(0, end - this.paintTop(index, at));
  }

  depthAt(index: number, at: DeckLocation): number {
    return index - at.index - at.turn;
  }

  widthScaleAt(depth: number): number {
    if (depth >= 0) return 1 - this.tiltAt(depth) * 0.003;
    const extra = Math.max(0, -depth - HISTORY_LIMIT);
    return 1 - Math.min(-depth, HISTORY_LIMIT) * 0.04 - 0.06 * extra / (extra + 3);
  }

  tiltAt(depth: number): number {
    // 平展区在两端各延伸半个牌位，双卡交接时仍可阅读共用的那张。
    const distance = Math.max(0, -depth - 0.5, depth - 1.5);
    if (distance === 0) return 0;
    const near = Math.min(1, distance * 2);
    const far = Math.min(1, Math.max(0, (distance - 0.5) / 2));
    if (depth < 0) return -4 * near * near * (3 - 2 * near) - 2 * far * far * (3 - 2 * far);
    return 32 * near * near * (3 - 2 * near) + 22 * far * far * (3 - 2 * far);
  }

  opacityAt(depth: number): number {
    // 上叠靠实物遮挡退出。仅下方的远景随纵深淡出。
    return Math.max(0, Math.min(1, UPCOMING_LAYERS + 2 - depth));
  }

  visibleSlots(at: DeckLocation): number[] {
    const slots: number[] = [];
    const focus = -this.depthAt(0, at);
    const stop = this.stops[at.index];
    if (!stop) return slots;
    let back = at.index - stop.history.length;
    const next = this.stops[at.index + 1];
    if (at.turn > 0 && next) back = Math.min(back, at.index + 1 - next.history.length);
    const first = Math.max(0, back - 1);
    const last = Math.min(this.faces.length - 1, Math.ceil(focus) + UPCOMING_LAYERS + 2);
    for (let i = first; i <= last; i++) slots.push(i);
    return slots;
  }

  release(offset: number, began: number, speed: number): number {
    const at = this.locate(offset);
    if (at.turn <= 0) return this.clamp(offset);
    const near = this.readEnds[at.index];
    const far = Math.min(this.limit, this.start(at.index + 1));
    if (offset >= far) return far;
    // 快推仅微调相邻两个落点的分界。短拖和反向收手均以眼前位置为准。
    const projection = Math.abs(offset - began) < 18 ? 0 :
      Math.max(-0.15, Math.min(0.15, speed * 0.085 / (far - near)));
    const threshold = began <= near ? 0.55 : began >= far ? 0.45 : 0.5;
    return (offset - near) / (far - near) + projection >= threshold ? far : near;
  }
}

export const DECK_PAN_SLOP: number = 8;

// 认出纵向拖动后逐渐交给手指控制，越过缓冲区时位移和速度都连续。
export function deckDragDistance(delta: number): number {
  const distance = Math.max(0, Math.abs(delta) - DECK_PAN_SLOP);
  const ramp = Math.min(DECK_PAN_SLOP, distance);
  return Math.sign(delta) * (ramp * ramp / (2 * DECK_PAN_SLOP) + distance - ramp);
}
