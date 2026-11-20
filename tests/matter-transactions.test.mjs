import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { after, test } from 'node:test';
import { DatabaseSync } from 'node:sqlite';
import { loadPortableEts } from '../scripts/load-portable-ets.mjs';

const bundle = await loadPortableEts();
after(() => bundle.close());
const { TransactionalMatterRepository: Repository } = bundle.modules['domain/TransactionalMatterRepository'];
const { MatterState } = bundle.modules['domain/MatterState'];
const { DefaultMatterService } = bundle.modules['domain/DefaultMatterService'];
const { MemoryMatterPersistence } = bundle.modules['mocks/MockMatterService'];
const { emptyMatterState, readLegacyMatterState, decodeMatterSnapshot } = bundle.modules['domain/MatterSnapshot'];
const { ModuleType } = bundle.modules['model/Types'];
const clone = value => JSON.parse(JSON.stringify(value));
const operation = (id, fingerprint = id) => ({ id, fingerprint });

function initialState() {
  const state = emptyMatterState();
  const matter = new MatterState(state).addMatter({ title: '计数事项', enabledModuleTypes: [ModuleType.Counter] });
  return { state, matterId: matter.id };
}
function fixture() {
  const { state, matterId } = initialState();
  const storage = new MemoryMatterPersistence(state);
  return { storage, app: new Repository(storage), card: new Repository(storage), matterId };
}
function increment(repository, id, matterId, value = 1) {
  return repository.transact(operation(id, `counter:${matterId}:${value}`), state =>
    new MatterState(state).addCounterEntry(matterId, value));
}
function count(state, matterId) {
  return new MatterState(state).counterTotal(matterId);
}

test('复现旧覆盖顺序：卡片 +1、旧 App 新建、卡片 +1 后两条计数与新事项均保留', async () => {
  const { storage, app, card, matterId } = fixture();
  await Promise.all([app.reload(), card.reload()]);
  await increment(card, 'card-1', matterId);
  const service = new DefaultMatterService(app);
  assert.equal((await service.createMatter({ intent: { title: 'App 新事项' } })).success, true);
  await increment(card, 'card-2', matterId);
  const saved = await storage.read();
  assert.equal(count(saved.state, matterId), 2);
  assert.equal(saved.state.matters.length, 2);
  await app.reload();
  assert.deepEqual(app.readState(), saved.state);
});

test('独立仓库并发冲突后在最新状态重放操作，同实例队列也不覆盖', async () => {
  const { storage, app, card, matterId } = fixture();
  await Promise.all(Array.from({ length: 20 }, (_, i) => increment(i % 2 ? app : card, `op-${i}`, matterId)));
  const saved = await storage.read();
  assert.equal(saved.revision, 20);
  assert.equal(saved.receipts.length, 20);
  assert.equal(saved.state.counterEntries.length, 20);
  assert.equal(count(saved.state, matterId), 20);
});

test('存储拒绝写入时不发布候选状态，后续操作不会夹带失败数据', async () => {
  const { storage, matterId } = fixture();
  const realWrite = storage.compareAndSwap.bind(storage);
  storage.compareAndSwap = async () => { throw new Error('disk full'); };
  const app = new Repository(storage);
  await app.reload();
  const before = app.readState();
  await assert.rejects(increment(app, 'failed', matterId, 10), /disk full/);
  assert.deepEqual(app.readState(), before);
  assert.deepEqual((await storage.read()).state, before);
  storage.compareAndSwap = realWrite;
  await increment(app, 'next', matterId);
  assert.equal(count(app.readState(), matterId), 1);
});

test('写入已提交但响应丢失时读取回执确认成功，重复请求跨重启仍只执行一次', async () => {
  const { storage, app, card, matterId } = fixture();
  const realWrite = storage.compareAndSwap.bind(storage);
  storage.compareAndSwap = async (...args) => {
    const written = await realWrite(...args);
    if (written) throw new Error('commit response lost');
    return false;
  };
  await increment(app, 'stable', matterId);
  await increment(card, 'later', matterId, 10);
  const restarted = new Repository(storage);
  await increment(restarted, 'stable', matterId);
  assert.equal(count(restarted.readState(), matterId), 11);
  assert.equal((await storage.read()).revision, 2);
});

test('提交与结果读取均中断后不报成功，恢复后同一操作 ID 可确认原提交', async () => {
  const { storage, app, matterId } = fixture();
  const realWrite = storage.compareAndSwap.bind(storage);
  const realRead = storage.read.bind(storage);
  storage.compareAndSwap = async (...args) => {
    await realWrite(...args);
    storage.read = async () => { throw new Error('storage unavailable'); };
    throw new Error('response lost');
  };
  await assert.rejects(increment(app, 'stable', matterId), /storage unavailable/);
  assert.equal(count(app.readState(), matterId), 0);
  storage.read = realRead;
  storage.compareAndSwap = realWrite;
  await increment(new Repository(storage), 'stable', matterId);
  assert.equal(count((await storage.read()).state, matterId), 1);
});

test('相同操作 ID 的不同内容被拒绝；成功结果与读取快照不能从外部修改仓库', async () => {
  const { storage, app, matterId } = fixture();
  await increment(app, 'same', matterId);
  await assert.rejects(increment(app, 'same', matterId, 10), /内容已改变/);
  const created = await app.transact(operation('create'), state => new MatterState(state).addMatter({ title: '新事项' }));
  created.title = '污染结果';
  app.readState().matters[0].title = '污染快照';
  assert.equal(app.readState().matters.at(-1).title, '新事项');
  assert.equal(app.readState().matters[0].title, '计数事项');
  assert.equal(count((await storage.read()).state, matterId), 1);
});

test('编辑使用最新状态保留并发记录，过期编辑拒绝覆盖已修改字段', async () => {
  const { app, card, matterId } = fixture();
  await app.reload();
  const service = new DefaultMatterService(app);
  const edit = service.loadEditor(matterId);
  const stale = clone(edit);
  await increment(card, 'card-count', matterId);
  edit.title = '新名称';
  assert.equal((await service.saveEditor(edit, '')).success, true);
  assert.equal(count(app.readState(), matterId), 1);
  stale.title = '过期名称';
  assert.equal((await service.saveEditor(stale, '')).success, false);
  assert.equal(service.findMatter(matterId).title, '新名称');
});

test('事务中的校验失败不留下部分内容；删除后卡片旧操作不能产生孤立记录', async () => {
  const { storage, app, card, matterId } = fixture();
  await assert.rejects(app.transact(operation('invalid'), state => {
    new MatterState(state).addMatter({ title: '不应保留' });
    throw new Error('validation failed');
  }), /validation failed/);
  await app.transact(operation('delete'), state => new MatterState(state).deleteMatter(matterId));
  await assert.rejects(increment(card, 'stale-card', matterId), /事项已不存在/);
  const saved = await storage.read();
  assert.equal(saved.state.matters.length, 0);
  assert.equal(saved.state.counterEntries.length, 0);
  assert.equal(saved.revision, 1);
});

test('旧数据导入保留隐藏配置、关联、卡片绑定和附加字段；缺省旧字段可读取', () => {
  const { state } = initialState();
  state.cardFormIds = ['form-A', 'form-B'];
  state.singleCardMatterId = state.matters[0].id;
  state.matters[0].disabledModules = [{ id: 'note', matterId: state.matters[0].id,
    moduleType: 'Note', configJson: '{"text":"保留"}', createdAt: 1, updatedAt: 1 }];
  state.futureField = { retained: true };
  assert.deepEqual(readLegacyMatterState(JSON.stringify(state)), clone(state));
  const minimal = readLegacyMatterState(JSON.stringify({ matters: state.matters }));
  assert.equal(minimal.summaryCardMatterIds[0], state.matters[0].id);
  assert.deepEqual(minimal.counterEntries, []);
  assert.throws(() => readLegacyMatterState('{bad json'), /无法读取/);
  assert.throws(() => readLegacyMatterState('{"matters":[null]}'), /内容损坏/);
  assert.throws(() => readLegacyMatterState('{"matters":{}}'), /格式错误/);
  assert.throws(() => decodeMatterSnapshot(JSON.stringify({ version: 2, revision: 0, state, receipts: [] }), 0), /版本/);
  assert.throws(() => decodeMatterSnapshot(JSON.stringify({ version: 1, revision: 2, state, receipts: [] }), 3), /版本/);
});

test('恢复演示只替换业务内容，已经登记的桌面卡片仍可刷新', async () => {
  const { app } = fixture();
  await app.transact(operation('register'), state => new MatterState(state).rememberCardForm('existing-form'));
  await app.transact(operation('reset'), state => new MatterState(state).resetDemoData());
  assert.deepEqual(app.readState().cardFormIds, ['existing-form']);
  assert.equal(app.readState().matters.length, 7);
});

// 与原生适配器使用相同的条件 UPDATE；下方通过两个真正的进程验证数据库边界。
class SqlitePersistence {
  constructor(database, decode) { this.database = database; this.decode = decode; }
  async read() {
    const row = this.database.prepare('SELECT revision, payload FROM matter_state WHERE id = 1').get();
    return this.decode(row.payload, row.revision);
  }
  async compareAndSwap(revision, next) {
    return this.database.prepare('UPDATE matter_state SET revision = ?, payload = ? WHERE id = 1 AND revision = ?')
      .run(next.revision, JSON.stringify(next), revision).changes === 1;
  }
}

test('两个独立进程使用 SQLite CAS，共同从旧版本开始并发计数，重启重放也不丢不重', { timeout: 20000 }, async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'todone-cas-'));
  const filename = path.join(directory, 'matter.db');
  const db = new DatabaseSync(filename);
  t.after(() => { db.close(); fs.rmSync(directory, { recursive: true, force: true }); });
  db.exec('PRAGMA journal_mode = WAL; CREATE TABLE matter_state (id INTEGER PRIMARY KEY, revision INTEGER NOT NULL, payload TEXT NOT NULL)');
  const { state, matterId } = initialState();
  db.prepare('INSERT INTO matter_state VALUES (1, 0, ?)').run(JSON.stringify({ version: 1, revision: 0, state, receipts: [] }));
  const worker = `
    import { DatabaseSync } from 'node:sqlite';
    import { TransactionalMatterRepository } from ${JSON.stringify(bundle.moduleUrl('domain/TransactionalMatterRepository'))};
    import { MatterState } from ${JSON.stringify(bundle.moduleUrl('domain/MatterState'))};
    import { decodeMatterSnapshot } from ${JSON.stringify(bundle.moduleUrl('domain/MatterSnapshot'))};
    ${SqlitePersistence.toString()}
    const db = new DatabaseSync(${JSON.stringify(filename)});
    db.exec('PRAGMA busy_timeout = 5000');
    const storage = new SqlitePersistence(db, decodeMatterSnapshot);
    const originalRead = storage.read.bind(storage);
    let first = true;
    storage.read = async () => {
      const snapshot = await originalRead();
      if (first) { first = false; await new Promise(resolve => { process.once('message', resolve); process.send('ready'); }); }
      await new Promise(resolve => setTimeout(resolve, 2));
      return snapshot;
    };
    const repository = new TransactionalMatterRepository(storage);
    for (let i = 0; i < 16; i++) {
      await repository.transact({ id: process.argv[1] + i, fingerprint: 'increment' }, state =>
        new MatterState(state).addCounterEntry(${JSON.stringify(matterId)}, 1));
    }
    db.close();
    process.disconnect();
  `;
  const children = ['app-', 'form-'].map(prefix => {
    const child = spawn(process.execPath, ['--input-type=module', '-e', worker, prefix], { stdio: ['ignore', 'pipe', 'pipe', 'ipc'] });
    let output = '';
    child.stderr.on('data', data => { output += data; });
    child.stdout.on('data', data => { output += data; });
    const ready = new Promise((resolve, reject) => {
      child.once('message', resolve);
      child.once('error', reject);
      child.once('exit', code => { if (code) reject(new Error(output)); });
    });
    const done = new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('exit', code => code === 0 ? resolve() : reject(new Error(output)));
    });
    t.after(() => { if (child.exitCode === null) child.kill(); });
    return { child, ready, done };
  });
  await Promise.all(children.map(child => child.ready));
  children.forEach(({ child }) => child.send('start'));
  await Promise.all(children.map(child => child.done));
  const storage = new SqlitePersistence(db, decodeMatterSnapshot);
  const saved = await storage.read();
  assert.equal(saved.revision, 32);
  assert.equal(saved.receipts.length, 32);
  assert.equal(new Set(saved.state.counterEntries.map(entry => entry.id)).size, 32);
  assert.equal(count(saved.state, matterId), 32);
  const restarted = new Repository(storage);
  await restarted.transact(operation('app-0', 'increment'), state => new MatterState(state).addCounterEntry(matterId, 1));
  assert.equal(count(restarted.readState(), matterId), 32);
  assert.equal((await storage.read()).revision, 32);
});
