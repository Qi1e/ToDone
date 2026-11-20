import { MatterPersistence, MatterSnapshot } from '../contracts/MatterPersistence';
import { DefaultMatterService } from '../domain/DefaultMatterService';
import { TransactionalMatterRepository } from '../domain/TransactionalMatterRepository';
import { createSeedState } from '../model/Defaults';
import { AppState } from '../model/Types';

export class MemoryMatterPersistence implements MatterPersistence {
  private snapshot: MatterSnapshot;

  constructor(state: AppState = createSeedState()) {
    this.snapshot = { version: 1, revision: 0, state: JSON.parse(JSON.stringify(state)) as AppState, receipts: [] };
  }

  async read(): Promise<MatterSnapshot> {
    return JSON.parse(JSON.stringify(this.snapshot)) as MatterSnapshot;
  }

  async compareAndSwap(expectedRevision: number, next: MatterSnapshot): Promise<boolean> {
    if (this.snapshot.revision !== expectedRevision) return false;
    this.snapshot = JSON.parse(JSON.stringify(next)) as MatterSnapshot;
    return true;
  }
}

export class MemoryMatterRepository extends TransactionalMatterRepository {
  constructor(state: AppState = createSeedState()) {
    super(new MemoryMatterPersistence(state), state);
  }
}

// 预览与真实实现共用操作、冲突和重试逻辑，仅替换持久化适配器。
export class MockMatterService extends DefaultMatterService {
  constructor(state: AppState = createSeedState()) {
    super(new MemoryMatterRepository(state));
  }
}
