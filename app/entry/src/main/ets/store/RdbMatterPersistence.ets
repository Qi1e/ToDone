import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { preferences, relationalStore } from '@kit.ArkData';
import { MatterPersistence, MatterSnapshot } from '../contracts/MatterPersistence';
import { decodeMatterSnapshot, MatterDataError, readLegacyMatterState } from '../domain/MatterSnapshot';
import { createSeedState } from '../model/Defaults';

export class RdbMatterPersistence implements MatterPersistence {
  private context: common.UIAbilityContext | common.FormExtensionContext;
  private opening?: Promise<relationalStore.RdbStore>;

  constructor(context: common.UIAbilityContext | common.FormExtensionContext) {
    this.context = context;
  }

  private database(): Promise<relationalStore.RdbStore> {
    if (!this.opening) {
      this.opening = this.open().catch((error: Error) => {
        this.opening = undefined;
        throw error;
      });
    }
    return this.opening;
  }

  private async open(): Promise<relationalStore.RdbStore> {
    const database = await relationalStore.getRdbStore(this.context, {
      name: 'todone_matter.db', securityLevel: relationalStore.SecurityLevel.S1
    });
    await database.executeSql('CREATE TABLE IF NOT EXISTS matter_state ' +
      '(id INTEGER PRIMARY KEY CHECK (id = 1), revision INTEGER NOT NULL, payload TEXT NOT NULL)');
    return database;
  }

  private async select(database: relationalStore.RdbStore): Promise<MatterSnapshot | undefined> {
    const rows = await database.querySql('SELECT revision, payload FROM matter_state WHERE id = 1');
    try {
      if (!rows.goToFirstRow()) return undefined;
      return decodeMatterSnapshot(rows.getString(1), rows.getLong(0));
    } finally {
      rows.close();
    }
  }

  private encode(snapshot: MatterSnapshot): string {
    const payload = JSON.stringify(snapshot);
    // RDB 单行过大可能写入成功但无法读回；在 2 MB 限制前留出读取余量。
    if (new util.TextEncoder().encodeInto(payload).byteLength > 1500000) {
      throw new MatterDataError('MAT-SIZE', '数据量超过当前版本保存上限，本次未保存，请保留草稿');
    }
    return payload;
  }

  async read(): Promise<MatterSnapshot> {
    const database = await this.database();
    const existing = await this.select(database);
    if (existing) return existing;

    // 旧存档只读导入。损坏时保留原文件，允许修复后再次读取。
    preferences.removePreferencesFromCacheSync(this.context, { name: 'todone_store' });
    const legacy = preferences.getPreferencesSync(this.context, { name: 'todone_store' });
    const initial: MatterSnapshot = { version: 1, revision: 0,
      state: legacy.hasSync('app_state_v1') ? readLegacyMatterState(legacy.getSync('app_state_v1', '') as string) :
        createSeedState(), receipts: [] };
    // App 和卡片可能同时首次启动，只有第一份导入可以建立状态。
    await database.executeSql('INSERT OR IGNORE INTO matter_state (id, revision, payload) VALUES (1, 0, ?)',
      [this.encode(initial)]);
    const imported = await this.select(database);
    if (!imported) throw new MatterDataError('MAT-IMPORT', '事项导入尚未完成，请重试');
    return imported;
  }

  async compareAndSwap(expectedRevision: number, next: MatterSnapshot): Promise<boolean> {
    if (next.revision !== expectedRevision + 1) {
      throw new MatterDataError('MAT-VERSION', '保存版本不连续');
    }
    const database = await this.database();
    const predicates = new relationalStore.RdbPredicates('matter_state')
      .equalTo('id', 1).equalTo('revision', expectedRevision);
    // 条件检查、状态与回执在一条 UPDATE 中原子生效，覆盖多个连接及进程。
    const changed = await database.update({ revision: next.revision, payload: this.encode(next) }, predicates);
    return changed === 1;
  }
}
