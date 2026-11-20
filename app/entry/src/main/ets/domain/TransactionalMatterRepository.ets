import { MatterRepository } from '../contracts/MatterService';
import { MatterOperation, MatterPersistence, MatterReceipt, MatterSnapshot } from '../contracts/MatterPersistence';
import { AppState } from '../model/Types';
import { emptyMatterState, MatterDataError } from './MatterSnapshot';

export class TransactionalMatterRepository implements MatterRepository {
  private committed: AppState = emptyMatterState();
  private pending: Promise<void> = Promise.resolve();
  private persistence: MatterPersistence;
  private receipts: MatterReceipt[] = [];

  constructor(persistence: MatterPersistence, initialState: AppState = emptyMatterState()) {
    this.persistence = persistence;
    this.committed = JSON.parse(JSON.stringify(initialState)) as AppState;
  }

  readState(): AppState {
    return JSON.parse(JSON.stringify(this.committed)) as AppState;
  }

  async reload(): Promise<void> {
    await this.enqueue(async (): Promise<void> => {
      this.accept(await this.persistence.read());
    });
  }

  transact<T>(operation: MatterOperation, change: (state: AppState) => T): Promise<T> {
    return this.enqueue(() => this.commit(operation, change));
  }

  latestOperationId(prefix: string): string {
    for (let index = this.receipts.length - 1; index >= 0; index--) {
      if (this.receipts[index].id.startsWith(prefix)) return this.receipts[index].id;
    }
    return '';
  }

  private accept(snapshot: MatterSnapshot): void {
    this.committed = snapshot.state;
    this.receipts = snapshot.receipts;
  }

  private enqueue<T>(work: () => Promise<T>): Promise<T> {
    const result = this.pending.then(work);
    this.pending = result.then((): void => {}, (): void => {});
    return result;
  }

  private receipt(snapshot: MatterSnapshot, operation: MatterOperation): MatterReceipt | undefined {
    const saved = snapshot.receipts.find((entry: MatterReceipt) => entry.id === operation.id);
    if (saved && saved.fingerprint !== operation.fingerprint) {
      throw new MatterDataError('MAT-OPERATION', '同一保存请求的内容已改变，请重新确认');
    }
    return saved;
  }

  private async commit<T>(operation: MatterOperation, change: (state: AppState) => T): Promise<T> {
    if (!operation.id || !operation.fingerprint) {
      throw new MatterDataError('MAT-OPERATION', '保存请求缺少操作标识');
    }
    for (let attempt = 0; attempt < 32; attempt++) {
      const latest = await this.persistence.read();
      this.accept(latest);
      const saved = this.receipt(latest, operation);
      if (saved) return JSON.parse(saved.result) as T;
      const next = JSON.parse(JSON.stringify(latest)) as MatterSnapshot;
      const result = change(next.state);
      next.revision++;
      next.receipts.push({ id: operation.id, fingerprint: operation.fingerprint,
        result: JSON.stringify(result) ?? 'null' });
      try {
        if (await this.persistence.compareAndSwap(latest.revision, next)) {
          this.accept(next);
          return result === undefined ? result : JSON.parse(JSON.stringify(result)) as T;
        }
      } catch (error) {
        // 写入可能已提交而响应丢失，先查持久化回执再向调用方报告结果。
        const recovered = await this.persistence.read();
        this.accept(recovered);
        const receipt = this.receipt(recovered, operation);
        if (receipt) return JSON.parse(receipt.result) as T;
        throw error as Error;
      }
    }
    throw new MatterDataError('MAT-BUSY', '其他操作正在保存，请重试原操作');
  }
}
